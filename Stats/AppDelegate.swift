//
//  AppDelegate.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 28.05.2019.
//  Copyright © 2019 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

import Kit
import UserNotifications

import CPU
import RAM
import Disk
import Net
import Battery
import Sensors
import GPU
import Bluetooth
import Clock
import Remote

internal enum StatsLinks {
    static let repository = "nashgao/stats"
    static let repositoryURL = URL(string: "https://github.com/\(repository)")!
    static let releaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let newIssue = repositoryURL.appendingPathComponent("issues/new")

    static func release(tag: String) -> URL {
        repositoryURL
            .appendingPathComponent("releases")
            .appendingPathComponent("tag")
            .appendingPathComponent(tag)
    }
}

let updater = Updater(
    github: StatsLinks.repository,
    url: StatsLinks.releaseAPI.absoluteString
)
let isCustomBuild = true
var modules: [Module] = [
    CPU(),
    GPU(),
    RAM(),
    Disk(),
    Sensors(),
    Network(),
    Battery(),
    Bluetooth(),
    Clock(),
    Remote()
]

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    internal var settingsWindow: SettingsWindow?
    internal var updateWindow: UpdateWindow?
    internal var setupWindow: SetupWindow?
    internal var supportWindow: SupportWindow?
    
    internal var menuBarItem: NSStatusItem? = nil
    internal var combinedView: CombinedView = CombinedView()
    internal var modulesMounted: Bool = false
    
    internal let updateActivity = NSBackgroundActivityScheduler(identifier: "eu.exelban.Stats.updateCheck")
    internal let supportActivity = NSBackgroundActivityScheduler(identifier: "eu.exelban.Stats.support")
    internal let supportRetryActivity = NSBackgroundActivityScheduler(identifier: "eu.exelban.Stats.supportRetry")
    
    internal var clickInNotification: Bool = false
    
    internal var pauseState: Bool {
        Store.shared.bool(key: "pause", defaultValue: false)
    }
    
    private var startTS: Date?
    private var launchStart: Date?
    
    static func main() {
        let launchStart = Date()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        delegate.launchStart = launchStart
        app.delegate = delegate
        app.run()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let startingPoint = self.launchStart ?? Date()

        switch ProcessInfo.processInfo.environment["STATS_APPEARANCE"]?.lowercased() {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        
        self.suppressStatusBarTilingConstraintUpdates()
        if ProcessInfo.processInfo.environment["STATS_CAPTURE_FIXTURE"] == "1" {
            CaptureFixture.run(self)
            return
        }
        self.parseArguments()
        self.parseVersion()
        SMCHelper.shared.checkForUpdate()
        self.setup {
            modules.reversed().forEach{ $0.mount() }
            self.modulesMounted = true
            if let module = ProcessInfo.processInfo.environment["STATS_POPUP_MODULE"] {
                if module == "All" {
                    // Unified popup prototype: mount all seven telemetry modules
                    // in memory (no Store writes) and open the shared panel.
                    modules.forEach { m in
                        if UnifiedPopupController.moduleOrder.contains(m.config.name) && !m.enabled {
                            m.enabled = true
                            m.mount()
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        let screen = NSScreen.main?.frame ?? .zero
                        UnifiedPopupController.shared.show(origin: NSPoint(x: screen.midX, y: screen.maxY - Constants.Widget.height))
                    }
                } else {
                    // The requested module can be disabled in the shared preferences
                    // (the live instance keeps its own config). Enable it in memory
                    // so the capture populates, without persisting the state.
                    let moduleName = ModuleType.popupNameAliases[module] ?? module
                    modules.forEach { m in
                        if m.config.name == moduleName && !m.enabled {
                            m.enabled = true
                            m.mount()
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        let screen = NSScreen.main?.frame ?? .zero
                        NotificationCenter.default.post(
                            name: .togglePopup,
                            object: nil,
                            userInfo: [
                                "module": module,
                                "origin": CGPoint(x: screen.midX, y: screen.maxY - Constants.Widget.height),
                                "center": CGFloat.zero
                            ]
                        )
                    }
                }
            } else if let destination = ProcessInfo.processInfo.environment["STATS_SETTINGS_DESTINATION"] {
                self.ensureSettingsWindow().open(module: destination)
            } else {
                self.showSettingsIfNoActiveWidgets()
            }
        }
        self.defaultValues()
        self.icon()
        if UnifiedPopupRouting.isEnabled {
            UnifiedPopupController.shared.ensurePanelModulesRunning()
        }
        UnifiedPopupController.shared.setupStatusItem()
        
        NotificationCenter.default.addObserver(self, selector: #selector(listenForAppPause), name: .pause, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleToggleSettings), name: .toggleSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRemoteAuthenticated), name: .remoteAuthenticated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRemoteUpdate), name: .remoteUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePopupVisibility), name: .popupVisibilityChanged, object: nil)
        
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
        
        info("Stats started in \((startingPoint.timeIntervalSinceNow * -1).rounded(toPlaces: 4)) seconds")
        self.startTS = Date()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        modules.forEach{ $0.terminate() }
        SystemStats.shared.terminate()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if self.clickInNotification {
            self.clickInNotification = false
            return true
        }
        guard let startTS = self.startTS, Date().timeIntervalSince(startTS) > 2 else { return false }
        
        let window = self.ensureSettingsWindow()
        if flag {
            window.makeKeyAndOrderFront(self)
        } else {
            window.setIsVisible(true)
        }
        
        return true
    }
    
    @objc private func handleToggleSettings(_ notification: Notification) {
        let module = notification.userInfo?["module"] as? String
        UnifiedPopupController.shared.hide()
        self.ensureSettingsWindow().open(module: module)
    }
    
    @objc private func handleRemoteAuthenticated() {
        DispatchQueue.main.async {
            self.checkIfShouldShowSupportWindow()
        }
    }
    
    @objc private func handleRemoteUpdate() {
        DispatchQueue.main.async {
            self.checkForNewVersion(silent: true)
        }
    }
    
    @objc private func handlePopupVisibility(_ notification: Notification) {
        guard let state = notification.userInfo?["state"] as? Bool, !state else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.tryToShowSupportWindow(interaction: true)
        }
    }
    
    private func showSettingsIfNoActiveWidgets() {
        if self.pauseState { return }
        let hasActive = modules.contains(where: { $0.enabled != false && $0.available != false && !$0.menuBar.widgets.filter({ $0.isActive }).isEmpty })
        if hasActive { return }
        self.ensureSettingsWindow().setIsVisible(true)
    }
    
    internal func ensureSettingsWindow() -> SettingsWindow {
        if let w = self.settingsWindow { return w }
        let w = SettingsWindow()
        w.onClose = { [weak self] in
            self?.settingsWindow = nil
            self?.tryToShowSupportWindow(interaction: true)
        }
        self.settingsWindow = w
        return w
    }
    
    internal func ensureUpdateWindow() -> UpdateWindow {
        if let w = self.updateWindow { return w }
        let w = UpdateWindow()
        w.onClose = { [weak self] in self?.updateWindow = nil }
        self.updateWindow = w
        return w
    }
    
    internal func ensureSetupWindow() -> SetupWindow {
        if let w = self.setupWindow { return w }
        let w = SetupWindow()
        w.onClose = { [weak self] in self?.setupWindow = nil }
        self.setupWindow = w
        return w
    }
    
    internal func ensureSupportWindow() -> SupportWindow {
        if let w = self.supportWindow { return w }
        let w = SupportWindow()
        w.onClose = { [weak self] in self?.supportWindow = nil }
        self.supportWindow = w
        return w
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        guard !isCustomBuild else {
            completionHandler()
            return
        }

        self.clickInNotification = true
        
        if let uri = response.notification.request.content.userInfo["url"] as? String {
            debug("Downloading new version of app...")
            if let url = URL(string: uri) {
                updater.download(url, completion: { path in
                    updater.install(path: path) { error in
                        if let error {
                            showAlert("Error update Stats", error, .critical)
                        }
                    }
                })
            }
        }
        
        completionHandler()
    }
}

// MARK: - Capture fixture (STATS_CAPTURE_FIXTURE=1, penpot-sync harness)

/// Launch-only source capture: original windows with synthetic sample data,
/// without mounting readers or entering the version/first-run/helper paths.
/// The extractor supplies a separate bundle identity, synthetic HOME and a
/// network-denied sandbox; preference controls are never exercised.
private enum CaptureFixture {
    static func run(_ delegate: AppDelegate) {
        let environment = ProcessInfo.processInfo.environment
        let surface = environment["STATS_CAPTURE_SURFACE"] ?? "panel"
        guard let samples = self.decodeSamples() else {
            NSLog("[CaptureFixture] fixture decode failed")
            exit(1)
        }
        switch surface {
        case "panel", "sensors":
            if surface == "sensors" { _ = SensorsAllPopover.shared }
            let screen = NSScreen.main?.frame ?? .zero
            UnifiedPopupController.shared.show(origin: NSPoint(x: screen.midX, y: screen.maxY - Constants.Widget.height))
        case "menu", "context-menu":
            UnifiedPopupController.shared.setupStatusItem()
        case "settings":
            let destination = environment["STATS_SETTINGS_DESTINATION"] ?? "Dashboard"
            guard destination == "Dashboard" || destination == "Settings"
                    || modules.contains(where: { $0.config.name == destination && $0.window != nil }) else {
                NSLog("[CaptureFixture] unavailable settings destination: %@", destination)
                exit(1)
            }
            delegate.ensureSettingsWindow().open(module: destination)
        case "setup":
            delegate.ensureSetupWindow().show()
        case "support":
            delegate.ensureSupportWindow().show()
        case "update":
            let state = environment["STATS_CAPTURE_UPDATE_STATE"] ?? "available"
            guard state == "available" || state == "current" else {
                NSLog("[CaptureFixture] invalid update state: %@", state)
                exit(1)
            }
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
            delegate.ensureUpdateWindow().open(version_s(
                current: current, latest: state == "available" ? "99.0.0" : current,
                newest: state == "available", url: StatsLinks.release(tag: "v99.0.0").absoluteString
            ))
        default:
            NSLog("[CaptureFixture] invalid surface: %@", surface)
            exit(1)
        }
        let dashboardSamples = self.dashboardSamples()
        func post() {
            self.post(samples)
            for sample in dashboardSamples {
                NotificationCenter.default.post(name: .telemetrySample, object: sample)
            }
        }
        post()
        NSLog("[CaptureFixture] surface=%@ posted %d samples", surface, samples.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { post() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { post() }
    }

    private static func post(_ samples: [(object: Any, userInfo: [AnyHashable: Any]?)]) {
        for sample in samples {
            NotificationCenter.default.post(name: .unifiedPanelSample, object: sample.object, userInfo: sample.userInfo)
        }
    }

    private static func dashboardSamples() -> [TelemetrySample] {
        // Synthetic values match the embedded panel fixture; fixed timestamp
        // keeps the original Dashboard's update label deterministic.
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let severity = ProcessInfo.processInfo.environment["STATS_CAPTURE_SEVERITY"] ?? "normal"
        let temperature: Double = severity == "critical" ? 101 : (severity == "attention" ? 95 : 53.8)
        return [
            TelemetrySample(metric: .cpu, value: 0.42, displayValue: "42%", detail: "System 18% · User 24%", timestamp: timestamp),
            TelemetrySample(metric: .memory, value: 0.58, displayValue: "58%", detail: "9.3 GB / 16 GB", timestamp: timestamp),
            TelemetrySample(metric: .disk, value: 0.56, displayValue: "56%", detail: "280 GB / 500 GB", timestamp: timestamp),
            TelemetrySample(metric: .network, value: 3_145_728, secondaryValue: 262_144, displayValue: "↓ 3 MB/s", detail: "↑ 256 KB/s", timestamp: timestamp),
            TelemetrySample(metric: .temperature, value: temperature, displayValue: "\(temperature)°C", detail: "GPU diode", timestamp: timestamp),
            TelemetrySample(metric: .battery, value: 0.73, secondaryValue: 0, power: -17.1, displayValue: "73%", detail: "On battery", timestamp: timestamp)
        ]
    }

    private static func decodeSamples() -> [(object: Any, userInfo: [AnyHashable: Any]?)]? {
        do {
            guard var dict = try JSONSerialization.jsonObject(with: Data(self.fixtureJSON.utf8)) as? [String: Any] else {
                return nil
            }
            let severity = ProcessInfo.processInfo.environment["STATS_CAPTURE_SEVERITY"] ?? "normal"
            guard ["normal", "attention", "critical"].contains(severity) else {
                NSLog("[CaptureFixture] invalid severity: %@", severity)
                return nil
            }
            if severity != "normal" {
                let temperature: Double = severity == "critical" ? 101 : 95
                dict["cpuTemp"] = temperature
                if var sensors = dict["sensors"] as? [String: Any],
                   var entries = sensors["sensors"] as? [[String: Any]] {
                    for index in entries.indices {
                        if var payload = entries[index]["payload"] as? [String: Any], payload["key"] as? String == "TG0D" {
                            payload["value"] = temperature
                            entries[index]["payload"] = payload
                        }
                    }
                    sensors["sensors"] = entries
                    dict["sensors"] = sensors
                }
            }
            if ProcessInfo.processInfo.environment["STATS_CAPTURE_SURFACE"] == "sensors",
               var sensors = dict["sensors"] as? [String: Any],
               var entries = sensors["sensors"] as? [[String: Any]],
               let template = entries.first?["payload"] as? [String: Any] {
                // More than five temperatures exposes the original All sensors
                // affordance; these are data fixtures, not replacement rows.
                for index in 1...9 {
                    var payload = template
                    payload["key"] = String(format: "CP%02d", index)
                    payload["name"] = "Fixture temperature \(index)"
                    payload["value"] = Double(30 + index)
                    payload["group"] = "Sensors"
                    entries.append(["base": 0, "payload": payload])
                }
                sensors["sensors"] = entries
                dict["sensors"] = sensors
            }
            if ProcessInfo.processInfo.environment["STATS_CAPTURE_SURFACE"] == "settings" {
                let destination = ProcessInfo.processInfo.environment["STATS_SETTINGS_DESTINATION"]
                if destination == "CPU", var load = dict["cpuLoad"] as? [String: Any],
                   let count = SystemKit.shared.device.info.cpu?.cores?.count, count > 0 {
                    // Original preview rows use the host's core metadata.
                    load["usagePerCore"] = Array(repeating: 0.42, count: count)
                    load["usageECores"] = 0.42
                    load["usagePCores"] = 0.42
                    dict["cpuLoad"] = load
                }
                if destination == "RAM", var memory = dict["ram"] as? [String: Any],
                   let total = (memory["total"] as? NSNumber)?.doubleValue, total > 0 {
                    // Match the original preview's physical-memory total while
                    // preserving synthetic usage proportions and swap data.
                    let scale = Double(ProcessInfo.processInfo.physicalMemory) / total
                    for key in ["total", "used", "free", "active", "inactive", "wired", "compressed", "app", "cache"] {
                        if let value = (memory[key] as? NSNumber)?.doubleValue {
                            memory[key] = value * scale
                        }
                    }
                    dict["ram"] = memory
                }
            }
            func decode<T: Decodable>(_ key: String, as type: T.Type) throws -> T {
                let data = try JSONSerialization.data(withJSONObject: dict[key] as Any)
                return try JSONDecoder().decode(T.self, from: data)
            }
            let cpuTemp = (dict["cpuTemp"] as? NSNumber)?.doubleValue ?? 0
            return [
                (try decode("cpuLoad", as: CPU_Load.self), nil),
                (try decode("cpuFreq", as: CPU_Frequency.self), nil),
                (cpuTemp, nil),
                (try decode("cpuAvg", as: CPU_AverageLoad.self), nil),
                (try decode("cpuTop", as: [TopProcess].self), ["module": "CPU"]),
                (try decode("ramTop", as: [TopProcess].self), ["module": "RAM"]),
                (try decode("gpu", as: GPU_Info.self), nil),
                (try decode("ram", as: RAM_Usage.self), nil),
                (try decode("disks", as: Disks.self), nil),
                (try decode("net", as: Network_Usage.self), nil),
                (try decode("sensors", as: Sensors_List.self), nil),
                (try decode("battery", as: Battery_Usage.self), nil)
            ]
        } catch {
            NSLog("[CaptureFixture] decode error: %@", "\(error)")
            return nil
        }
    }

    /// Every non-optional stored property of the sample types is present:
    /// Swift's synthesized Codable ignores default values, so keys like
    /// `state`, `platforms`, `unit` or `activity` are required even though
    /// the sources declare defaults for them.
    private static let fixtureJSON = #"""
{
  "cpuLoad": {
    "totalUsage": 0.42,
    "usagePerCore": [0.38, 0.44, 0.51, 0.29, 0.47, 0.62, 0.35, 0.41, 0.33, 0.40],
    "usageECores": 0.35,
    "usagePCores": 0.51,
    "systemLoad": 0.18,
    "userLoad": 0.24,
    "idleLoad": 0.58
  },
  "cpuFreq": {
    "value": 3204.0,
    "eCore": 2448.0,
    "pCore": 3648.0
  },
  "cpuTemp": 52.4,
  "cpuAvg": {
    "load1": 2.34,
    "load5": 2.87,
    "load15": 3.12
  },
  "cpuTop": [
    {"pid": 412, "name": "Safari", "usage": 18.4},
    {"pid": 977, "name": "WindowServer", "usage": 12.1},
    {"pid": 1203, "name": "Stats", "usage": 8.7},
    {"pid": 233, "name": "mdworker_shared", "usage": 6.2}
  ],
  "ramTop": [
    {"pid": 845, "name": "Xcode", "usage": 2469606195},
    {"pid": 412, "name": "Safari", "usage": 1825361100},
    {"pid": 977, "name": "WindowServer", "usage": 939524096},
    {"pid": 1203, "name": "Stats", "usage": 402653184}
  ],
  "gpu": {
    "id": "0",
    "type": "i",
    "IOClass": "IOAccelerator",
    "vendor": "Apple",
    "model": "Apple M4 Pro",
    "cores": 20,
    "state": true,
    "coreClock": 1400,
    "temperature": 52.4,
    "utilization": 0.31,
    "renderUtilization": 0.28,
    "tilerUtilization": 0.35,
    "aneUtilization": 0.04,
    "fps": 60.0
  },
  "ram": {
    "total": 17179869184,
    "used": 9964324126,
    "free": 7215545058,
    "active": 6509559808,
    "inactive": 2415919104,
    "wired": 2281701376,
    "compressed": 1316073984,
    "app": 6366548766,
    "cache": 3187671040,
    "swap": {"total": 2147483648, "used": 536870912, "free": 1610612736},
    "pressure": {"level": 0, "value": "normal"},
    "swapins": 123456,
    "swapouts": 2345
  },
  "disks": {
    "array": [
      {
        "parent": 0,
        "uuid": "FIXTURE-ROOT",
        "mediaName": "Macintosh HD",
        "BSDName": "disk3s1",
        "root": true,
        "removable": false,
        "model": "APPLE SSD AP0512Z",
        "connectionType": "Apple Fabric",
        "fileSystem": "apfs",
        "writable": true,
        "encrypted": true,
        "size": 500068036608,
        "free": 220200534016,
        "activity": {"read": 12582912, "write": 4194304, "readBytes": 3221225472, "writeBytes": 1073741824}
      },
      {
        "parent": 0,
        "uuid": "FIXTURE-DATA",
        "mediaName": "Data",
        "BSDName": "disk3s5",
        "root": false,
        "removable": false,
        "model": "APPLE SSD AP0512Z",
        "connectionType": "Apple Fabric",
        "fileSystem": "apfs",
        "writable": true,
        "encrypted": true,
        "size": 500068036608,
        "free": 220200534016,
        "activity": {"read": 2097152, "write": 524288, "readBytes": 536870912, "writeBytes": 134217728}
      }
    ]
  },
  "net": {
    "bandwidth": {"upload": 262144, "download": 3145728},
    "total": {"upload": 128849018880, "download": 987842478080},
    "laddr": {},
    "raddr": {},
    "dns": [],
    "interface": {"status": true, "displayName": "Wi-Fi", "BSDName": "en0", "address": "192.168.1.42", "transmitRate": 866.0},
    "connectionType": "wifi",
    "status": true,
    "wifiDetails": {}
  },
  "sensors": {
    "sensors": [
      {
        "base": 0,
        "payload": {
          "key": "TC0P",
          "name": "CPU proximity",
          "value": 51.5,
          "group": "CPU",
          "type": "Temperature",
          "platforms": ["m4", "m4Pro", "m4Max"],
          "isComputed": false,
          "average": false
        }
      },
      {
        "base": 0,
        "payload": {
          "key": "TG0D",
          "name": "GPU diode",
          "value": 53.8,
          "group": "GPU",
          "type": "Temperature",
          "platforms": ["m4", "m4Pro", "m4Max"],
          "isComputed": false,
          "average": false
        }
      },
      {
        "base": 0,
        "payload": {
          "key": "TA0P",
          "name": "Ambient",
          "value": 32.4,
          "group": "Sensors",
          "type": "Temperature",
          "platforms": ["m4", "m4Pro", "m4Max"],
          "isComputed": false,
          "average": false
        }
      },
      {
        "base": 1,
        "payload": {
          "id": 0,
          "key": "F0Ac",
          "name": "Main fan",
          "minSpeed": 1200.0,
          "maxSpeed": 5500.0,
          "value": 2400.0,
          "mode": 0,
          "group": "Sensors",
          "type": "Fans",
          "platforms": ["m4", "m4Pro", "m4Max"],
          "isIntelOnly": false,
          "isComputed": false,
          "average": false,
          "unit": "RPM",
          "miniUnit": ""
        }
      }
    ]
  },
  "battery": {
    "powerSource": "Battery Power",
    "isCharged": false,
    "isCharging": false,
    "isBatteryPowered": true,
    "optimizedChargingEngaged": false,
    "level": 0.73,
    "cycles": 214,
    "health": 96,
    "designedCapacity": 6200,
    "maxCapacity": 5952,
    "fullChargeCapacity": 5890,
    "currentCapacity": 4300,
    "current": -1450,
    "voltage": 11.8,
    "temperature": 31.2,
    "batteryPower": -17.1,
    "ACwatts": 0,
    "chargingCurrent": 0,
    "chargingVoltage": 0,
    "adapterPower": 0.0,
    "adapterVoltage": 0.0,
    "timeToEmpty": 312,
    "timeToCharge": 0
  }
}
"""#
}
