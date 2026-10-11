//
//  UnifiedPopup.swift
//  Stats
//
//  Unified all-modules popup panel, design "E - Heroes + Grammar"
//  (stats-unified-redesign.html). One scrollable glass panel: brand
//  header with a verdict chip, three hero cards (CPU, GPU, RAM) that
//  expand in place one at a time, four grammar rows (Disk, Network,
//  Sensors, Battery), and a shared footer. Sections subscribe to the
//  modules' existing reader data via .unifiedPanelSample; the classic
//  per-module popups are untouched.
//
//  Harness entry points: STATS_POPUP_MODULE=All opens the panel;
//  STATS_POPUP_SCROLL_TO accepts "bottom" or a point offset for
//  capture QA.
//

import Cocoa
import Kit
import Sensors
import Battery
import IOKit.ps

func withoutImplicitAnimation(_ block: () -> Void) {
    NSAnimationContext.runAnimationGroup { context in
        context.allowsImplicitAnimation = false
        context.duration = 0
        block()
    }
}

/// NSStatusBarButton's native multiline title is vertically offset beyond
/// its bounds. A template image keeps both rows inside the existing button,
/// including native highlighting, appearance adaptation and mouse handling.
private func applyMenuReadoutTitle(_ title: String, layout: MenuReadoutLayout, to item: NSStatusItem) {
    guard let button = item.button else { return }
    let rows = title.components(separatedBy: "\n")
    button.setAccessibilityLabel(title.replacingOccurrences(of: "\n", with: ", "))
    if layout == .stacked && rows.count == 2 {
        let rowHeight: CGFloat = 11
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        let strings = rows.map { NSAttributedString(string: $0, attributes: attributes) }
        let widths = strings.map { ceil($0.size().width) }
        let size = NSSize(width: widths.max() ?? 0, height: rowHeight * 2)
        let image = NSImage(size: size, flipped: false) { bounds in
            for (index, string) in strings.enumerated() {
                string.draw(in: NSRect(
                    x: (bounds.width - widths[index]) / 2,
                    y: rowHeight * CGFloat(1 - index),
                    width: widths[index],
                    height: rowHeight
                ))
            }
            return true
        }
        image.isTemplate = true
        button.attributedTitle = NSAttributedString()
        button.imageScaling = .scaleNone
        button.image = image
    } else {
        button.image = nil
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        ])
    }
    item.length = NSStatusItem.variableLength
}

final class UnifiedPopupController {
    static let shared = UnifiedPopupController()
    
    static let moduleOrder = ["CPU", "GPU", "RAM", "Disk", "Network", "Sensors", "Battery"]
    
    private let panel: UnifiedPopupPanel
    private var statusItem: NSStatusItem? = nil
    private let menuPower = MenuPowerReadout(probe: LiveMenuPowerProbe())
    private var glyphTimer: Timer?
    private var glyphState: String = ""
    /// Last layout+title rendered, so the 1s tick only rebuilds the title
    /// or stacked image when its content or layout actually changes.
    private var menuPowerState: String = ""
    /// Whether the readout text currently owns the status item. While
    /// true, the attention glyph is suppressed (menu bar shows the
    /// composed title only); when the text goes away, the glyph returns
    /// so the item stays visible.
    private var textShown = false
    /// Launch-only rendering exercise; never writes shared preferences.
    private static let qaMenuReadoutEnabled = ProcessInfo.processInfo.environment["STATS_QA_MENU_READOUT"] == "1"
    private var qaMenuReadoutTick = 0
    private var qaMenuReadoutPhase = -1
    
    /// QA fan-cycle state (STATS_QA_FAN_CYCLE=1): latest real specs and
    /// speed of fan 0 from the sensors reader, captured off
    /// .unifiedPanelSample so the harness can pick a mid-range RPM
    /// target and verify the read-back without touching the UI.
    private var qaFanMin: Double = 0
    private var qaFanMax: Double = 0
    private var qaFanSpeed: Double = 0
    private var qaFanSeen: Bool = false
    
    @objc private func qaFanSample(_ notification: Notification) {
        guard let list = notification.object as? Sensors_List,
              let fan = list.sensors.compactMap({ $0 as? Fan }).first(where: { $0.id == 0 })
        else { return }
        self.qaFanMin = fan.minSpeed
        self.qaFanMax = fan.maxSpeed
        self.qaFanSpeed = fan.value
        self.qaFanSeen = true
    }
    
    private var qaReadBackLogged = false
    private var qaReadBackFloor: Double = 0
    /// The panel-toggle probe runs once per launch even though every
    /// show() re-arms the knob block.
    private static var qaToggleArmed = false
    /// Same for the synthetic dismiss-guard exercise.
    private static var qaDismissArmed = false
    /// STATS_QA_LAYOUT=1: log the panel content height once per
    /// second so smoke can assert layout stability (no section jumping).
    private static let qaLayoutEnabled = ProcessInfo.processInfo.environment["STATS_QA_LAYOUT"] == "1"
    /// STATS_QA_EXPAND=1: drive a Sensors expand at +8s and sample the
    /// heights across the next 1.2s (two-phase expand detector).
    private static var qaExpandArmed = false
    
    /// Poll for the spin-up read-back after the RPM target; logs once —
    /// "(meets target)" when the speed reaches max(baseline, target/2),
    /// "(below target)" at the deadline otherwise. The floor anchors the
    /// check to the commanded value so auto fan control cannot satisfy
    /// it by drifting.
    private func qaReadBackPoll(deadline: Date) {
        guard !self.qaReadBackLogged else { return }
        if self.qaFanSpeed > 0 && self.qaFanSpeed >= self.qaReadBackFloor {
            self.qaReadBackLogged = true
            NSLog("[QA] fan cycle: read-back speed %d RPM (meets target, floor %d)", Int(self.qaFanSpeed.rounded()), Int(self.qaReadBackFloor.rounded()))
            return
        }
        guard Date() < deadline else {
            self.qaReadBackLogged = true
            NSLog("[QA] fan cycle: read-back speed %d RPM (below target, floor %d)", Int(self.qaFanSpeed.rounded()), Int(self.qaReadBackFloor.rounded()))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.qaReadBackPoll(deadline: deadline)
        }
    }
    
    private init() {
        self.panel = UnifiedPopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: UnifiedPopupPanel.panelWidth, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.modulePopupVisibilityChanged(_:)),
            name: .popupVisibilityChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.routeUnifiedPopup(_:)),
            name: .toggleUnifiedPopup,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.appActiveChanged(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.appActiveChanged(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        self.installOutsideClickDismissal()
        if ProcessInfo.processInfo.environment["STATS_QA_FAN_CYCLE"] == "1" {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.qaFanSample(_:)),
                name: .unifiedPanelSample,
                object: nil
            )
        }
        if ProcessInfo.processInfo.environment["STATS_QA_SENSOR_TICK"] == "1" {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.qaSensorSample(_:)),
                name: .unifiedPanelSample,
                object: nil
            )
        }
        if ProcessInfo.processInfo.environment["STATS_QA_DIAGNOSTICS"] == "1" {
            NSLog("[QA] diagnostics:\n%@", PowerDiagnostics.snapshot())
        }
    }
    
    /// QA (STATS_QA_SENSOR_TICK=1): log every Sensors_List sample that
    /// reaches the panel, with the hottest temperature, so a frozen
    /// display can be told apart from a frozen reader.
    @objc private func qaSensorSample(_ notification: Notification) {
        guard let list = notification.object as? Sensors_List else { return }
        let temps = list.sensors.filter({ $0.type == .temperature && $0.value.isFinite })
        guard let hottest = temps.max(by: { $0.value < $1.value }) else { return }
        NSLog("[QA] sensor sample: hottest=%@ %.1f count=%d", hottest.key, hottest.value, temps.count)
    }
    
    /// Deliberate outside-click dismissal, replacing what
    /// hidesOnDeactivate used to provide before it had to be disabled:
    /// any click outside the panel and outside our own status-item
    /// button closes it. A global monitor sees clicks delivered to other
    /// apps; a local one sees clicks inside our own windows, keeping
    /// panel clicks (Escape/scroll) and status-item clicks (the toggle)
    /// for their normal handlers. Both no-op unless the panel is
    /// effectively visible, and neither fires on the transient
    /// deactivate bounce that accompanies the opening click.
    private var outsideClickMonitors: [Any] = []
    
    private func installOutsideClickDismissal() {
        // The isolated producer must not react to clicks in the user's desktop.
        guard ProcessInfo.processInfo.environment["STATS_CAPTURE_FIXTURE"] != "1" else { return }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissForOutsideClick(event: nil)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissForOutsideClick(event: event)
            return event
        }
        if let global { self.outsideClickMonitors.append(global) }
        if let local { self.outsideClickMonitors.append(local) }
    }
    
    /// Timestamp (seconds since system startup, NSEvent's clock) of the
    /// click that opened the panel. The dismissal monitors ignore any
    /// event at or before this plus an epsilon: AppKit re-dispatches
    /// synthesized copies of the opening status-item click while the
    /// status-bar tracking resolves, and those phantoms must not close
    /// the panel they just opened.
    private var panelOpenTimestamp: TimeInterval = 0
    private let panelOpenGuardEpsilon: TimeInterval = 0.05
    
    private func stampPanelOpenTimestamp() {
        if let timestamp = NSApp.currentEvent?.timestamp {
            self.panelOpenTimestamp = timestamp
        }
    }
    
    private func eventScreenLocation(_ event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        }
        return NSEvent.mouseLocation
    }
    
    private func isInStatusItemButton(_ point: NSPoint) -> Bool {
        guard let frame = self.statusItem?.button?.window?.frame else { return false }
        return frame.contains(point)
    }
    
    private func dismissForOutsideClick(event: NSEvent?) {
        guard self.isEffectivelyVisible else { return }
        if let event {
            // Clicks inside the panel never dismiss.
            if event.window === self.panel { return }
            // The status-item button lives in the StatusBarServer process,
            // so phantom re-dispatches of the opening click pass window
            // identity checks; screen location is the reliable guard.
            if self.isInStatusItemButton(self.eventScreenLocation(event)) { return }
            // Synthesized events belonging to the opening click itself.
            if event.timestamp <= self.panelOpenTimestamp + self.panelOpenGuardEpsilon { return }
        } else {
            // global monitor: no event object, use the live mouse location
            if self.isInStatusItemButton(NSEvent.mouseLocation) { return }
        }
        NSLog("[UnifiedPanelTrace] outside-click dismissal firing")
        self.hide()
    }
    
    var isVisible: Bool {
        self.panel.isVisible
    }
    
    /// True only when the user can actually see the panel: ordered in,
    /// not miniaturized, and on the active Space. NSWindow.isVisible
    /// alone stays true for windows stranded on another Space (or
    /// ordered in while occluded), which made the toggle eat every other
    /// click — the classic "sometimes nothing happens" wedge.
    /// Source of truth for "the panel is presented", set by show() and
    /// cleared by hide(). AppKit's isOnActiveSpace returns false
    /// transiently while a .moveToActiveSpace window is mid-resize, and
    /// the toggle decision based purely on window state could conclude
    /// "hidden" right after show() and wedge the panel. Once presented,
    /// AppKit's isVisible is the reliable signal (it does not flake);
    /// before the first show() of the session the full window-state
    /// check is the fallback.
    private var panelPresented = false
    
    private var isEffectivelyVisible: Bool {
        if self.panelPresented {
            return self.panel.isVisible && !self.panel.isMiniaturized
        }
        guard self.panel.isVisible, !self.panel.isMiniaturized else { return false }
        return self.panel.isOnActiveSpace
    }
    
    /// The unified panel renders a card for every module, so every panel
    /// module's readers must run even when the user's menu-bar config has
    /// the module off (otherwise e.g. the RAM card shows no data). Menu
    /// bar widgets stay suppressed — UnifiedPopupRouting.moduleWidgetsAllowed
    /// gates them. In-memory only: no Store writes, the user's widget
    /// configuration is untouched. Call once at launch.
    func ensurePanelModulesRunning() {
        modules.forEach { module in
            guard UnifiedPopupController.moduleOrder.contains(module.config.name),
                  module.available, !module.enabled else { return }
            module.enabled = true
            module.mount()
            NSLog("[UnifiedPopup] unified mode: running %@ module for panel data (widget stays hidden)", module.config.name)
        }
    }
    
    /// App-level menu bar item. Toggleable via the unified_widget defaults
    /// key (default: on). Coexists with the per-module widgets.
    func setupStatusItem() {
        guard Store.shared.bool(key: UnifiedPopupRouting.storeKey, defaultValue: true) else { return }
        guard self.statusItem == nil else { return }
        
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        let image = iconFromSymbol(name: "chart.bar.fill", scale: .medium)
        image.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(self.togglePanel)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.toolTip = localizedString("Open unified popup")
        self.statusItem = item
        if ProcessInfo.processInfo.environment["STATS_CAPTURE_FIXTURE"] == "1" {
            // Original button/composer, without live polling, wake reconnect
            // or helper activation. Capture data is supplied below.
            button.window?.identifier = NSUserInterfaceItemIdentifier(rawValue: "StatsCaptureStatusItem")
            button.setAccessibilityIdentifier("StatsCaptureStatusItem")
            self.updateGlyph()
            self.updateMenuReadout()
            NSLog("[CaptureFixture] status root=%@ window=%@ number=%ld frame=%@",
                  button.window?.contentView.map { String(describing: type(of: $0)) } ?? "unavailable",
                  button.window?.identifier?.rawValue ?? "unavailable",
                  button.window?.windowNumber ?? 0, NSStringFromRect(button.window?.frame ?? .zero))
            if ProcessInfo.processInfo.environment["STATS_CAPTURE_SURFACE"] == "context-menu" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showStatusMenu() }
            }
            return
        }
        // Post-sleep refresh of the menu readout: SMC.shared opens its
        // AppleSMC connection once at launch and sleep/wake can leave it
        // stale (reads against the old port, watts frozen on the
        // pre-sleep value), so reopen it on wake and force the glyph and
        // readout to re-evaluate immediately instead of waiting for the
        // next value change. Workspace notifications arrive on the main
        // thread; setupStatusItem's nil-guard makes this once per launch.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        if self.glyphTimer == nil {
            self.glyphTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateGlyph()
                self?.updateMenuReadout()
                if SMCHelper.shared.reachabilityRefreshDue(maxAge: 5) {
                    SMCHelper.shared.refreshReachability()
                }
                if self?.panel.isVisible == true {
                    withoutImplicitAnimation {
                        self?.panel.refreshContent()
                        self?.panel.syncSize()
                    }
                    if Self.qaLayoutEnabled, let panel = self?.panel {
                        NSLog("[QA] layout tick: content=%.1f", panel.contentHeight)
                    }
                }
                UnifiedPerf.tick()
            }
        }
        self.updateGlyph()
        self.updateMenuReadout()
        // Unified mode hides the module widgets, so nothing else may touch
        // the helper; establish the XPC connection here (idempotent, no-op
        // unless the daemon is registered and loaded).
        SMCHelper.shared.checkForUpdate()
        SMCHelper.shared.healIfNeeded()
        NSLog("[UnifiedPopup] status item installed (unified_widget=on) helper=%d",
              SMCHelper.shared.isActive() ? 1 : 0)
    }
    
    /// Wake handler (registered with the status item): reopen the SMC
    /// connection and reset the cached menu-bar states so updateGlyph()
    /// and updateMenuReadout() repaint even when the attention state and
    /// the composed title did not change. Runs on the main thread.
    @objc private func systemDidWake(_ notification: Notification) {
        Kit.SMC.shared.reconnect()
        self.menuPowerState = ""
        self.glyphState = ""
        self.updateGlyph()
        self.updateMenuReadout()
    }
    
    /// Adaptive glyph + tint, evaluated on a ~1s cadence from the shared
    /// AttentionEvaluator. Status pairs the glyph with a tint: systemOrange
    /// for attention, systemRed for critical; accent blue stays reserved
    /// for interaction. Attention tints are baked into the image because
    /// NSStatusBarButton does not reliably apply contentTintColor to swapped
    /// symbol images. The quiet glyph is a TRUE template image - untouched
    /// symbol, no baked color, no content tint - so the menu bar renders it
    /// adaptively (white on a dark bar, dark on a light bar), matching the
    /// other menu bar items.
    private func updateGlyph() {
        guard let button = self.statusItem?.button else { return }
        let attention = AttentionEvaluator.shared.primary
        let key = attention.map { "\($0.kind.rawValue)-\($0.level.rawValue)" } ?? "default"
        guard key != self.glyphState else { return }
        self.glyphState = key
        guard !self.textShown else { return }
        
        if let attention {
            let image: NSImage
            switch attention.kind {
            case .fan:
                image = self.symbolImage("fanblades.fill", fallback: "wind")
            case .temperature:
                image = self.symbolImage("thermometer.medium", fallback: "thermometer")
            case .memory:
                image = self.symbolImage("memorychip", fallback: "square.stack.3d.up.fill")
            case .gpu:
                image = self.symbolImage("gauge.high", fallback: "gauge")
            case .battery:
                image = self.symbolImage("battery.100bolt", fallback: "bolt.fill")
            case .cpu:
                image = iconFromSymbol(name: "chart.bar.fill", scale: .medium)
            }
            button.image = self.tinted(image, with: attention.level == .critical ? .systemRed : .systemOrange)
        } else {
            let image = iconFromSymbol(name: "chart.bar.fill", scale: .medium)
            image.isTemplate = true
            button.image = image
        }
        button.contentTintColor = nil
    }
    
    /// Primary SFSymbol with a macOS 12-safe fallback for symbols newer
    /// than the deployment target (checked at runtime, not compile time).
    private func symbolImage(_ name: String, fallback: String) -> NSImage {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return iconFromSymbol(name: fallback, scale: .medium)
        }
        return symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(textStyle: .body, scale: .medium)) ?? symbol
    }
    
    /// Recolor a template/symbol image's shape (source-atop fill).
    private func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let rect = NSRect(origin: .zero, size: image.size)
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        color.set()
        image.draw(in: rect)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }
    
    @objc private func togglePanel() {
        NSLog("[UnifiedPanelTrace] togglePanel event=%d", NSApp.currentEvent?.type.rawValue ?? -1)
        self.stampPanelOpenTimestamp()
        if NSApp.currentEvent?.type == .rightMouseDown {
            self.showStatusMenu()
            return
        }
        self.toggleFromItem()
    }
    
    private func toggleFromItem() {
        self.stampPanelOpenTimestamp()
        let visible = self.isEffectivelyVisible
        NSLog("[UnifiedPanelTrace] toggleFromItem effectiveVisible=%d", visible ? 1 : 0)
        if visible {
            self.hide()
            return
        }
        
        // Only one popup surface at a time.
        modules.forEach { $0.closePopupIfVisible() }
        
        guard let window = self.statusItem?.button?.window else { return }
        self.show(origin: window.frame.origin, center: window.frame.width/2)
    }
    
    /// Right-click affordance: with a single menu bar item and no app menu,
    /// this is the other way to reach Settings or quit.
    private func showStatusMenu() {
        guard let button = self.statusItem?.button else { return }
        let menu = NSMenu()
        
        let open = NSMenuItem(title: localizedString("Open Stats"), action: #selector(self.menuOpen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "\(localizedString("Settings"))…", action: #selector(self.menuSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: localizedString("Quit Stats"), action: #selector(self.menuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        
        let capturing = ProcessInfo.processInfo.environment["STATS_CAPTURE_FIXTURE"] == "1"
        if capturing { NSApp.activate(ignoringOtherApps: true) }
        let shown = menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.maxY + 2), in: button)
        if capturing { NSLog("[CaptureFixture] context menu shown=%d", shown ? 1 : 0) }
    }
    
    @objc private func menuOpen() {
        self.toggleFromItem()
    }
    
    @objc private func menuSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Settings"])
    }
    
    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
    
    /// Module widget click routed to the unified panel: opens it under the
    /// clicked widget, scrolled to that module's section. When any attention
    /// is active, the first attention section overrides the anchor. If the
    /// panel is already open, just re-anchors the scroll; manual scrolling
    /// always wins afterwards.
    @objc private func routeUnifiedPopup(_ notification: Notification) {
        guard UnifiedPopupRouting.isEnabled,
              let origin = notification.userInfo?["origin"] as? CGPoint,
              let center = notification.userInfo?["center"] as? CGFloat else { return }
        let anchor = notification.userInfo?["module"] as? String
        let target = AttentionEvaluator.shared.primary?.module ?? anchor
        
        if self.isEffectivelyVisible {
            if let target {
                self.panel.scrollToSection(target)
            }
            return
        }
        
        modules.forEach { $0.closePopupIfVisible() }
        self.show(origin: origin, center: center, scrollTo: target)
    }
    
    @objc private func modulePopupVisibilityChanged(_ notification: Notification) {
        let state = notification.userInfo?["state"] as? Bool ?? false
        NSLog("[UnifiedPanelTrace] modulePopupVisibilityChanged state=%d visible=%d", state ? 1 : 0, self.panel.isVisible ? 1 : 0)
        guard state else { return }
        self.hide()
    }
    
    /// Activation churn around a menu-bar click is the prime suspect in
    /// the flash-close: pair these lines with the orderOut stack trace
    /// and the key/main transitions to see exactly what fires between
    /// show() and the disappearance.
    @objc private func appActiveChanged(_ notification: Notification) {
        let became = notification.name == NSApplication.didBecomeActiveNotification
        NSLog("[UnifiedPanelTrace] app %@ visible=%d key=%d ts=%.3f",
              became ? "didBecomeActive" : "didResignActive",
              self.panel.isVisible ? 1 : 0,
              self.panel.isKeyWindow ? 1 : 0,
              Date().timeIntervalSince1970)
    }
    
    func hide() {
        NSLog("[UnifiedPanelTrace] hide() visible=%d", self.panel.isVisible ? 1 : 0)
        guard self.panel.isVisible else { return }
        self.panelPresented = false
        SensorsAllPopover.closeIfShown()
        self.panel.animateExit { [weak self] in
            self?.panel.orderOut(nil)
        }
    }
    
    func show(origin: NSPoint, center: CGFloat = 0, scrollTo: String? = nil) {
        let showStart = CFAbsoluteTimeGetCurrent()
        // (Re)establish the SMC helper connection when the panel opens:
        // covers the app having launched before the helper was
        // registered/approved. Kept off the first-paint path — the panel
        // renders now, the helper state catches up a beat later.
        if ProcessInfo.processInfo.environment["STATS_CAPTURE_FIXTURE"] != "1" {
            DispatchQueue.main.async {
                SMCHelper.shared.checkForUpdate()
                SMCHelper.shared.refreshReachability()
                NSLog("[UnifiedPopup] helper active=%d installed=%d signed=%d",
                      SMCHelper.shared.isActive() ? 1 : 0,
                      SMCHelper.shared.isInstalled ? 1 : 0,
                      SMCHelper.shared.isProperlySigned ? 1 : 0)
            }
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        self.panel.refreshContent()
        
        // document + pinned footer
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let height = max(348, min(self.panel.contentHeight + 28, screenHeight * 0.7))
        let width = UnifiedPopupPanel.panelWidth
        let anchorX = origin.x + center
        var x = anchorX - width/2
        var clamped = false
        let y = origin.y - height - 3
        
        let buttonPoint = NSPoint(x: origin.x + center, y: origin.y)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonPoint) }) ?? NSScreen.main {
            if x + width > screen.frame.maxX {
                x = screen.frame.maxX - width - 3
                clamped = true
            }
            if x < screen.frame.minX {
                x = screen.frame.minX + 3
                clamped = true
            }
        }
        
        // size the content area directly: the frame's content rect carries
        // hidden insets on modern macOS, so setFrame-based math undercounts
        self.panel.setContentSize(NSSize(width: width, height: height))
        var frame = self.panel.frame
        frame.origin.x = x
        frame.origin.y = y - (frame.height - height)
        self.panel.setFrameOrigin(frame.origin)
        self.panel.setContentSize(NSSize(width: width, height: height))
        self.panel.setPendingContentHeight(height)
        self.panel.refreshContent()
        if let expand = ProcessInfo.processInfo.environment["STATS_POPUP_EXPAND"] {
            self.panel.expandSection(expand)
        }
        if ProcessInfo.processInfo.environment["STATS_QA_FAN_CYCLE"] == "1" {
            // Smoke-test path: exercise the real fan-command round trip
            // (helper -> XPC reply block) that crashed on thread affinity,
            // then the manual RPM path the slider uses. Apple-silicon fans
            // idle at 0 RPM, so the read-back polls for the spin-up
            // against a floor of max(baseline, target/2) — auto-fan drift
            // can never satisfy it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                // Real reachability probe: the version reply is a genuine
                // XPC round trip (no reply = helper really is broken).
                SMCHelper.shared.helperVersion { version in
                    if let version {
                        NSLog("[QA] helper version reply: OK (%@)", version)
                    } else {
                        NSLog("[QA] helper version reply: FAILED")
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NSLog("[QA] fan cycle: manual (forced)")
                SMCHelper.shared.setFanMode(0, mode: 1) { result in
                    NSLog("[QA] fan cycle: mode reply (result=%@)", result ?? "empty")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                // Manual RPM target through the same SMCHelper.setFanSpeed
                // path the slider uses, mid-range within the fan's real
                // limits (clamped to min+2000 .. max).
                guard self.qaFanSeen, self.qaFanMax > 1 else {
                    NSLog("[QA] fan cycle: rpm target skipped (no fan specs yet)")
                    return
                }
                let target = Int(min(self.qaFanMin + 2000, self.qaFanMax).rounded())
                let baseline = self.qaFanSpeed
                NSLog("[QA] fan cycle: rpm target set (%d RPM, baseline %d RPM)", target, Int(baseline.rounded()))
                SMCHelper.shared.setFanSpeed(0, speed: target) { result in
                    NSLog("[QA] fan cycle: helper accepted rpm target (result=%@)", result ?? "empty")
                }
                self.qaReadBackFloor = max(baseline, Double(target) * 0.5)
                self.qaReadBackLogged = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.qaReadBackPoll(deadline: Date().addingTimeInterval(12))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                NSLog("[QA] fan cycle: automatic")
                SMCHelper.shared.setFanMode(0, mode: 0)
            }
        }
        if ProcessInfo.processInfo.environment["STATS_QA_ALERT"] == "1" {
            // Smoke-test path: force a deterministic attention edge so the
            // alerter composes a notification regardless of machine state.
            // Quiet sample first so the metric leaves the set even when the
            // machine was already hot at launch, then a crossing sample.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                NotificationCenter.default.post(name: .telemetrySample, object: TelemetrySample(
                    metric: .memory, value: 0.5, displayValue: "50%", detail: "QA"
                ))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                NotificationCenter.default.post(name: .telemetrySample, object: TelemetrySample(
                    metric: .memory, value: 0.95, displayValue: "95%", detail: "QA"
                ))
            }
        }
        if ProcessInfo.processInfo.environment["STATS_QA_PANEL_TOGGLE"] == "1" && !Self.qaToggleArmed {
            Self.qaToggleArmed = true
            // Smoke-test path: drive the toggle decision the way a real
            // status-item click does (open -> closed -> open) and log the
            // state transitions, so a wedge — e.g. isVisible stuck true
            // while the panel is stranded or occluded — fails loudly
            // instead of looking like a click that "does nothing".
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self else { return }
                // a real click may have dismissed the panel — restore a
                // known-visible state before probing
                if !self.isEffectivelyVisible, let button = self.statusItem?.button?.window {
                    self.show(origin: button.frame.origin, center: button.frame.width / 2)
                }
                NSLog("[QA] panel toggle: open effective=%d visible=%d", self.isEffectivelyVisible ? 1 : 0, self.panel.isVisible ? 1 : 0)
                self.toggleFromItem()
                NSLog("[QA] panel toggle: closed effective=%d visible=%d", self.isEffectivelyVisible ? 1 : 0, self.panel.isVisible ? 1 : 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self else { return }
                    self.toggleFromItem()
                    NSLog("[QA] panel toggle: reopen effective=%d visible=%d", self.isEffectivelyVisible ? 1 : 0, self.panel.isVisible ? 1 : 0)
                    // The flash regression hid the panel asynchronously,
                    // right after the open resolved; sample again once
                    // the bounce would have landed, and once more after
                    // 5s for the "stays open" guarantee.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        guard let self else { return }
                        NSLog("[QA] panel toggle: settled effective=%d visible=%d", self.isEffectivelyVisible ? 1 : 0, self.panel.isVisible ? 1 : 0)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                        guard let self else { return }
                        NSLog("[QA] panel toggle: stays effective=%d visible=%d", self.isEffectivelyVisible ? 1 : 0, self.panel.isVisible ? 1 : 0)
                    }
                }
            }
        }
        if ProcessInfo.processInfo.environment["STATS_QA_DISMISS"] == "1" && !Self.qaDismissArmed {
            Self.qaDismissArmed = true
            // Synthetic-event exercise of the outside-click dismissal
            // guards. Events are built in the status-item button window's
            // coordinate space (window identity is NOT consulted for the
            // button — only screen location is), so the inside event must
            // be ignored by the location guard and the outside event must
            // dismiss.
            // Kept 3s clear of the toggle probe's "settled" sample (+13s):
            // the samples used to be 1s apart, and a stalled runloop let
            // this block's outside-dismiss run before the settled log,
            // false-failing the flash assertion.
            DispatchQueue.main.asyncAfter(deadline: .now() + 16) { [weak self] in
                guard let self, let buttonWindow = self.statusItem?.button?.window else { return }
                // Guarantee a visible panel first (a real click during the
                // run may have dismissed it), then exercise both guards
                // synchronously in the same runloop turn so no external
                // event can interleave.
                if !self.isEffectivelyVisible {
                    self.show(origin: buttonWindow.frame.origin, center: buttonWindow.frame.width / 2)
                }
                let frame = buttonWindow.frame
                let future = ProcessInfo.processInfo.systemUptime + 1
                let makeEvent = { (screenPoint: NSPoint) -> NSEvent? in
                    NSEvent.mouseEvent(
                        with: .leftMouseDown,
                        location: buttonWindow.convertPoint(fromScreen: screenPoint),
                        modifierFlags: [],
                        timestamp: future,
                        windowNumber: buttonWindow.windowNumber,
                        context: nil,
                        eventNumber: 0,
                        clickCount: 1,
                        pressure: 1
                    )
                }
                if let inside = makeEvent(NSPoint(x: frame.midX, y: frame.midY)) {
                    self.dismissForOutsideClick(event: inside)
                    NSLog("[QA] dismiss: inside-button event -> visible=%d (expect 1)", self.panel.isVisible ? 1 : 0)
                }
                if let outside = makeEvent(NSPoint(x: frame.maxX + 400, y: frame.midY)) {
                    self.dismissForOutsideClick(event: outside)
                    NSLog("[QA] dismiss: outside event -> visible=%d (expect 0)", self.panel.isVisible ? 1 : 0)
                }
            }
        }
        if let expandValue = ProcessInfo.processInfo.environment["STATS_QA_EXPAND"], expandValue != "0", !Self.qaExpandArmed {
            Self.qaExpandArmed = true
            // Single mode (value = module name, "1" = Sensors): the
            // original probe with before/immediate/+0.3s/+1.2s samples.
            // All mode: expand every expandable section in sequence
            // (+7/+11/+15/+19s), one line per section with the panel
            // height immediately and after 1.2s — a two-phase expand
            // shows up as a height change.
            let modules: [String] = expandValue == "All" ? ["CPU", "GPU", "RAM", "Sensors", "Battery", "Disk", "Network", "Thermal"] : [expandValue == "1" ? "Sensors" : expandValue]
            if modules.count == 1 {
                let module = modules[0]
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
                    guard let self else { return }
                    if module == "SensorsAll" {
                        // QA value: expand the section and open the
                        // all-sensors popover (same path as the row tap).
                        self.panel.expandSection("Sensors")
                        self.panel.openAllSensorsForQA()
                        NSLog("[QA] expand: all-sensors popover opened")
                    } else {
                        self.panel.expandSection(module)
                    }
                    NSLog("[QA] expand: before content=%.0f panel=%.0f", self.panel.contentHeight, self.panel.frame.height)
                    self.panel.expandSection(module)
                    NSLog("[QA] expand: immediate content=%.0f panel=%.0f", self.panel.contentHeight, self.panel.frame.height)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self else { return }
                        NSLog("[QA] expand: +0.3s content=%.0f panel=%.0f", self.panel.contentHeight, self.panel.frame.height)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        guard let self else { return }
                        NSLog("[QA] expand: +1.2s content=%.0f panel=%.0f", self.panel.contentHeight, self.panel.frame.height)
                    }
                }
            } else {
                for (index, module) in modules.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 7 + Double(index) * 4) { [weak self] in
                        guard let self else { return }
                        if !self.isEffectivelyVisible, let button = self.statusItem?.button?.window {
                            self.show(origin: button.frame.origin, center: button.frame.width / 2)
                        }
                        let t = CFAbsoluteTimeGetCurrent()
                        self.panel.expandSection(module)
                        let expandMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
                        let startHeight = self.panel.frame.height
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                            guard let self else { return }
                            // state=0 marks a sample taken after external
                            // interference (a live user click) — the smoke
                            // uses the last state=1 pair per module.
                            NSLog("[QA] expand-seq: %@ latency=%.1fms panel %.0f->%.0f state=%d",
                                  module, expandMs, startHeight, self.panel.frame.height,
                                  self.panel.expandedSectionForQA == module ? 1 : 0)
                        }
                    }
                }
                // Collapse round trip: hold a manual-fan attention (the
                // sticky auto-expand is active) and tap the Sensors header
                // — the user collapse must win and stay collapsed. The
                // timing derives from the expand list so the two drivers
                // can never land on the same tick.
                let collapseAt = 7.0 + Double(modules.count) * 4.0 + 1.5
                DispatchQueue.main.asyncAfter(deadline: .now() + collapseAt - 0.3) {
                    NotificationCenter.default.post(name: .telemetrySample, object: TelemetrySample(
                        metric: .fan, value: 0.5, secondaryValue: 1, displayValue: "1,650 RPM", detail: "QA"
                    ))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + collapseAt) { [weak self] in
                    guard let self else { return }
                    if !self.isEffectivelyVisible, let button = self.statusItem?.button?.window {
                        self.show(origin: button.frame.origin, center: button.frame.width / 2)
                    }
                    self.panel.expandSection("Sensors")
                    let t = CFAbsoluteTimeGetCurrent()
                    let before = self.panel.frame.height
                    self.panel.simulateHeaderTap("Sensors")
                    let collapseMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        guard let self else { return }
                        NSLog("[QA] expand-seq: collapse Sensors latency=%.1fms panel %.0f->%.0f stayed=%d",
                              collapseMs, before, self.panel.frame.height,
                              self.panel.expandedSectionForQA == nil ? 1 : 0)
                    }
                }
                // A→B→collapse-B restore probe: with the fan sticky active,
                // expand A (Sensors), switch to B (CPU), collapse B — the
                // bug re-opened A because the sticky saw "nothing expanded"
                // and the suppression flag was never set by the switch.
                DispatchQueue.main.asyncAfter(deadline: .now() + collapseAt + 1.0) { [weak self] in
                    guard let self else { return }
                    self.panel.expandSection("Sensors")
                    self.panel.expandSection("CPU")
                    self.panel.simulateHeaderTap("CPU")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        guard let self else { return }
                        NSLog("[QA] expand-seq: restore-probe %@", self.panel.collapsedStatesForQA)
                    }
                }
                // Hero collapse round trip: the heroes share the same
                // toggle state — a header tap on an expanded hero must
                // collapse it symmetrically.
                DispatchQueue.main.asyncAfter(deadline: .now() + collapseAt + 4) { [weak self] in
                    guard let self else { return }
                    if !self.isEffectivelyVisible, let button = self.statusItem?.button?.window {
                        self.show(origin: button.frame.origin, center: button.frame.width / 2)
                    }
                    self.panel.expandSection("CPU")
                    let t = CFAbsoluteTimeGetCurrent()
                    let before = self.panel.frame.height
                    self.panel.simulateHeaderTap("CPU")
                    let collapseMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        guard let self else { return }
                        NSLog("[QA] expand-seq: collapse CPU latency=%.1fms panel %.0f->%.0f stayed=%d",
                              collapseMs, before, self.panel.frame.height,
                              self.panel.expandedSectionForQA == nil ? 1 : 0)
                    }
                }
            }
        }
        if let scrollTo, let offset = self.panel.sectionOffset(for: scrollTo) {
            self.panel.scrollToOffset(offset)
        } else {
            self.panel.scrollToTop()
        }
        // Take focus and make the panel key. Activating tears down any
        // other app's open menu/dropdown (an accessory-policy app becoming
        // active ends the previous app's menu tracking) and brings our
        // window above its transient UI; makeKeyAndOrderFront additionally
        // puts the panel in the responder chain so Escape closes it.
        let tPresent = CFAbsoluteTimeGetCurrent()
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        self.panel.makeKeyAndOrderFront(nil)
        self.panelPresented = true
        self.panel.setAnchorTop(self.panel.frame.maxY)
        self.panel.playEntrance()
        let contentMs = (tPresent - t0) * 1000
        let presentMs = (CFAbsoluteTimeGetCurrent() - tPresent) * 1000
        let totalMs = (CFAbsoluteTimeGetCurrent() - showStart) * 1000
        let panelCenterX = self.panel.frame.midX
        NSLog("[UnifiedPanelTrace] show done visible=%d key=%d active=%d level=%d",
              self.panel.isVisible ? 1 : 0,
              self.panel.isKeyWindow ? 1 : 0,
              NSApp.isActive ? 1 : 0,
              self.panel.level.rawValue)
        NSLog("[UnifiedPerf] show latency total=%.1fms content=%.1fms present=%.1fms anchor delta=%.1fpt clamped=%d",
              totalMs, contentMs, presentMs, panelCenterX - anchorX, clamped ? 1 : 0)
        if let scrollToEnv = ProcessInfo.processInfo.environment["STATS_POPUP_SCROLL_TO"] {
            if scrollToEnv == "bottom" {
                self.panel.scrollToBottom()
            } else if let offset = Double(scrollToEnv) {
                self.panel.scrollToOffset(offset)
            }
        }
        if ProcessInfo.processInfo.environment["STATS_CAPTURE_FIXTURE"] == "1",
           ProcessInfo.processInfo.environment["STATS_CAPTURE_SURFACE"] == "sensors" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                self?.panel.scrollToSection("Sensors")
                self?.panel.openAllSensorsForQA()
            }
        }
        if ProcessInfo.processInfo.environment["STATS_POPUP_DEBUG_PAINT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.panel.debugFrames()
            }
        }
        if ProcessInfo.processInfo.environment["STATS_POPUP_CAPTURE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.panel.writeSelfCapture()
            }
        }
        NSLog("[UnifiedPopup] shown: content %.0fpt, panel %.0fpt frame=%@", self.panel.contentHeight, height, NSStringFromRect(self.panel.frame))
    }
}

private extension UnifiedPopupController {
    /// Live readout next to the unified status item, evaluated on the same
    /// ~1s cadence as updateGlyph. The element set (MenuReadoutElements —
    /// watts / battery / temperature / time, read-through from the MEN-1 preset key and,
    /// below that, the legacy watts boolean) picks the segments, the layout
    /// (MenuReadoutLayoutSelection — horizontal / stacked) picks the join,
    /// and MenuReadoutComposer composes the title. The readout is the menu
    /// bar's entire content — either a native title or a stacked template
    /// image. The attention glyph stays suppressed while readouts show
    /// and is restored when they disappear, so an off item
    /// never becomes invisible. STATS_QA_MENU_WATTS=1 forces the
    /// watts-only set and logs the composed title every tick for the
    /// smoke test. Watts are read fresh from the SMC each tick, by
    /// power state (see MenuPowerReadout): battery drain (PPBR) on
    /// battery; total system draw (PDTR) on AC when not charging; SoC
    /// power (si10) on AC while charging, because the adapter sits at
    /// its delivery limit then and PDTR pins at a constant. Battery
    /// values come from Battery.lastKnownUsage — the same sample the
    /// unified panel's Battery row renders (see UnifiedPanelContent);
    /// temperature comes from Sensors.lastKnownList via
    /// hottestTemperatureText — the same hottest value the panel's
    /// Sensors row renders.
    private func updateMenuReadout() {
        guard let item = self.statusItem, let button = item.button else { return }
        let environment = ProcessInfo.processInfo.environment
        let captureFixture = environment["STATS_CAPTURE_FIXTURE"] == "1"
        let forced = !captureFixture && environment["STATS_QA_MENU_WATTS"] == "1"
        var elements: [MenuReadoutElement] = forced ? [.watts] : MenuReadoutElements.current()
        var layout = MenuReadoutLayoutSelection.current()
        if captureFixture {
            let rawElements = environment["STATS_CAPTURE_MENU_ELEMENTS"] ?? "off"
            let requested = rawElements == "off" ? [] : rawElements.split(separator: ",").map(String.init)
            guard requested.allSatisfy({ MenuReadoutElement(rawValue: $0) != nil }),
                  let requestedLayout = MenuReadoutLayout(rawValue: environment["STATS_CAPTURE_MENU_LAYOUT"] ?? "horizontal") else {
                NSLog("[CaptureFixture] invalid menu elements or layout")
                exit(1)
            }
            elements = requested.compactMap(MenuReadoutElement.init(rawValue:))
            layout = requestedLayout
        }

        let draw = captureFixture ? 17.1 : self.menuPower.watts()

        if forced {
            NSLog("[QA] menu watts: %@", draw.map { UnifiedInfoFormatters.menuWatts($0) } ?? "n/a")
            let rawPPBR = Kit.SMC.shared.getValue("PPBR")
            let rawPDTR = Kit.SMC.shared.getValue("PDTR")
            let rawSI10 = Kit.SMC.shared.getValue("si10")
            NSLog("[QA] watts raw: PPBR=%@ PDTR=%@ SI10=%@",
                  rawPPBR.map { String($0) } ?? "n/a",
                  rawPDTR.map { String($0) } ?? "n/a",
                  rawSI10.map { String($0) } ?? "n/a")
        }

        let usage = captureFixture ? nil : (modules.first(where: { $0 is Battery }) as? Battery)?.lastKnownUsage
        let sensorsList = captureFixture ? nil : (modules.first(where: { $0 is Sensors }) as? Sensors)?.lastKnownList
        var input = MenuReadoutComposer.Input(
            watts: draw,
            batteryLevel: usage?.level,
            temperatureText: Self.hottestTemperatureText(sensorsList?.sensors ?? []),
            timeToEmptyMinutes: usage?.timeToEmpty,
            isBatteryPowered: usage?.isBatteryPowered ?? false
        )
        if captureFixture {
            input = MenuReadoutComposer.Input(
                watts: 17.1, batteryLevel: 0.73, temperatureText: "53.8°C",
                timeToEmptyMinutes: 312, isBatteryPowered: true
            )
        }
        if Self.qaMenuReadoutEnabled {
            let phase = min(self.qaMenuReadoutTick / 4, 9)
            self.qaMenuReadoutTick += 1
            layout = (phase % 5 == 1 || phase % 5 == 2) ? .stacked : .horizontal
            switch phase % 5 {
            case 0: elements = [.watts, .battery, .temperature]
            case 1: elements = [.watts, .temperature]
            case 2: elements = [.temperature]
            case 3: elements = [.watts, .temperature]
            default: elements = []
            }
            input = MenuReadoutComposer.Input(
                watts: 49, batteryLevel: 1, temperatureText: "86°C",
                timeToEmptyMinutes: nil, isBatteryPowered: false
            )
            button.appearance = NSAppearance(named: phase < 5 ? .aqua : .darkAqua)
            if phase != self.qaMenuReadoutPhase {
                self.qaMenuReadoutPhase = phase
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.captureMenuReadout(phase: phase, layout: layout)
                }
            }
        }
        // Stored/legacy selections can exceed the current layout's UI cap.
        let cap = layout == .stacked ? 2 : 3
        if elements.count > cap { elements = Array(elements.prefix(cap)) }
        let next = MenuReadoutComposer.title(
            segments: MenuReadoutComposer.segments(elements: elements, input: input),
            layout: layout
        )
        if !next.isEmpty {
            PowerDiagnostics.record(watts: next)
        }
        if next.isEmpty {
            button.attributedTitle = NSAttributedString()
            button.setAccessibilityLabel(localizedString("Open unified popup"))
            if item.length != NSStatusItem.squareLength {
                item.length = NSStatusItem.squareLength
            }
            if self.textShown {
                self.textShown = false
                // glyphState is keyed on the attention state, which never
                // changed while the glyph was suppressed — clear it so
                // updateGlyph repaints the glyph now.
                self.glyphState = ""
                self.updateGlyph()
            }
            self.menuPowerState = ""
            return
        }
        self.textShown = true
        let nextKey = "\(layout.rawValue)\u{1F}\(next)"
        guard nextKey != self.menuPowerState else { return }
        self.menuPowerState = nextKey
        applyMenuReadoutTitle(next, layout: layout, to: item)
    }

    /// Hottest popup-visible temperature, formatted exactly as the
    /// unified panel's Sensors row renders it — Stats/UnifiedPanelSamples
    /// .swift:147-153 is the reference copy of this filter. Kept beside
    /// the tick so the menu readout and the panel cannot drift; when
    /// UnifiedPanelSamples is next touched it should call this instead
    /// of repeating the filter inline.
    private static func hottestTemperatureText(_ sensors: [Sensor_p]) -> String? {
        sensors
            .filter({ $0.type == .temperature && $0.popupState && $0.value.isFinite })
            .max(by: { $0.value < $1.value })?
            .formattedValue
    }

    /// Captures the installed button, not a reconstruction of its title.
    /// With STATS_QA_MENU_CAPTURE_DIR set, phase-0...phase-9.png cover
    /// horizontal three/two, stacked two/one and glyph in light/dark.
    private func captureMenuReadout(phase: Int, layout: MenuReadoutLayout) {
        guard let button = self.statusItem?.button else { return }
        button.layoutSubtreeIfNeeded()
        button.needsDisplay = true
        button.displayIfNeeded()
        let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? .zero
        let title = button.accessibilityLabel() ?? ""
        let rows = layout == .stacked && phase % 5 == 1 ? 2 : (phase % 5 == 4 ? 0 : 1)
        NSLog("[QA] menu readout phase=%d layout=%@ title=%@ frame=%@ image=%@ rows=%d glyph=%d action=%@ window=%d",
              phase, layout.rawValue, title, NSStringFromRect(button.frame),
              NSStringFromRect(imageRect), rows, self.textShown ? 0 : 1,
              button.action.map(NSStringFromSelector) ?? "nil", button.window?.windowNumber ?? -1)
        if rows == 2 {
            let top = NSRect(x: imageRect.minX, y: imageRect.midY, width: imageRect.width, height: imageRect.height / 2)
            let bottom = NSRect(x: imageRect.minX, y: imageRect.minY, width: imageRect.width, height: imageRect.height / 2)
            NSLog("[QA] menu readout row geometry top=%@ bottom=%@ fits=%d",
                  NSStringFromRect(top), NSStringFromRect(bottom),
                  button.bounds.contains(imageRect) && imageRect.height >= 22 ? 1 : 0)
        }
        defer { if phase == 9 { NSLog("[QA] menu readout complete") } }
        guard let directory = ProcessInfo.processInfo.environment["STATS_QA_MENU_CAPTURE_DIR"] else { return }
        do {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            guard let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { return }
            button.cacheDisplay(in: button.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
            try data.write(to: url.appendingPathComponent("phase-\(phase).png"))
            NSLog("[QA] menu readout captured phase=%d pixels=%dx%d", phase, bitmap.pixelsWide, bitmap.pixelsHigh)
        } catch {
            NSLog("[QA] menu readout capture failed: %@", error.localizedDescription)
        }
    }

}
