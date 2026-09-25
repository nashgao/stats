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
import IOKit.ps

private func withoutImplicitAnimation(_ block: () -> Void) {
    NSAnimationContext.runAnimationGroup { context in
        context.allowsImplicitAnimation = false
        context.duration = 0
        block()
    }
}

final class UnifiedPopupController {
    static let shared = UnifiedPopupController()
    
    static let moduleOrder = ["CPU", "GPU", "RAM", "Disk", "Network", "Sensors", "Battery"]
    
    private let panel: UnifiedPopupPanel
    private var statusItem: NSStatusItem? = nil
    private var glyphTimer: Timer?
    private var glyphState: String = ""
    /// Last formatted value written to the status item title, so the
    /// 1s tick only rebuilds the attributed string when the number
    /// actually changed.
    private var menuPowerState: String = ""
    /// Whether the watts readout currently owns the status item. While
    /// true, the attention glyph is suppressed (menu bar shows watts
    /// only); when watts turn off, the glyph returns so the item stays
    /// visible.
    private var wattsShown = false
    
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
        // Post-sleep refresh of the menu readout: SMC.shared opens its
        // AppleSMC connection once at launch and sleep/wake can leave it
        // stale (reads against the old port, watts frozen on the
        // pre-sleep value), so reopen it on wake and force the glyph and
        // watts to re-evaluate immediately instead of waiting for the
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
                self?.updateMenuPower()
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
        self.updateMenuPower()
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
    /// and updateMenuPower() repaint even when the attention state and
    /// the watts number did not change. Runs on the main thread.
    @objc private func systemDidWake(_ notification: Notification) {
        Kit.SMC.shared.reconnect()
        self.menuPowerState = ""
        self.glyphState = ""
        self.updateGlyph()
        self.updateMenuPower()
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
    
    /// Live watts readout next to the unified status item, evaluated on the
    /// same ~1s cadence as updateGlyph. Opt-in via unified_widget_power; it
    /// is the menu bar's entire content — the attention glyph is suppressed
    /// while watts show (button.image cleared below, after updateGlyph's
    /// pass in the same tick) and restored when watts turn off, so a
    /// watts-off item never becomes invisible. Battery level + time live
    /// in the unified panel's Battery row, not here. STATS_QA_MENU_WATTS=1
    /// forces the segment on and logs the composed title every tick for the
    /// smoke test. Values are read fresh from the SMC each tick, by
    /// power state (see currentPowerDraw): battery drain (PPBR) on
    /// battery; total system draw (PDTR) on AC when not charging; SoC
    /// power (si10) on AC while charging, because the adapter sits at
    /// its delivery limit then and PDTR pins at a constant. Shown as a
    /// magnitude: the sign was cryptic without the panel's battery
    /// label.
    private func updateMenuPower() {
        guard let item = self.statusItem, let button = item.button else { return }
        let forced = ProcessInfo.processInfo.environment["STATS_QA_MENU_WATTS"] == "1"
        let wattsEnabled = forced || Store.shared.bool(key: "unified_widget_power", defaultValue: false)
        
        let draw = self.currentPowerDraw()
        let watts = wattsEnabled ? draw.map({ UnifiedInfoFormatters.menuWatts($0) }) : nil
        
        if forced {
            NSLog("[QA] menu watts: %@", watts ?? "n/a")
            let rawPPBR = Kit.SMC.shared.getValue("PPBR")
            let rawPDTR = Kit.SMC.shared.getValue("PDTR")
            let rawSI10 = Kit.SMC.shared.getValue("si10")
            NSLog("[QA] watts raw: PPBR=%@ PDTR=%@ SI10=%@",
                  rawPPBR.map { String($0) } ?? "n/a",
                  rawPDTR.map { String($0) } ?? "n/a",
                  rawSI10.map { String($0) } ?? "n/a")
        }
        
        let next = watts ?? ""
        if next.isEmpty {
            button.attributedTitle = NSAttributedString()
            if item.length != NSStatusItem.squareLength {
                item.length = NSStatusItem.squareLength
            }
            if self.wattsShown {
                self.wattsShown = false
                // glyphState is keyed on the attention state, which never
                // changed while the glyph was suppressed — clear it so
                // updateGlyph repaints the glyph now.
                self.glyphState = ""
                self.updateGlyph()
            }
            self.menuPowerState = ""
            return
        }
        // Watts own the item: keep the glyph suppressed even on ticks
        // where the number did not change (updateGlyph may just have
        // repainted it for an attention change — see the timer order).
        self.wattsShown = true
        button.image = nil
        guard next != self.menuPowerState else { return }
        self.menuPowerState = next
        button.attributedTitle = NSAttributedString(string: next, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        ])
        if item.length != NSStatusItem.variableLength {
            item.length = NSStatusItem.variableLength
        }
    }
    
    /// Current system draw in watts, as a magnitude (the menu bar shows
    /// no sign): battery flow when draining; on AC the system's own
    /// draw, never the raw adapter delivery; nil only when no SMC power
    /// keys respond.
    private func currentPowerDraw() -> Double? {
        let batteryPower = Kit.SMC.shared.getValue("PPBR")
        let adapterPower = Kit.SMC.shared.getValue("PDTR")
        if self.onBatteryPower() {
            return batteryPower.map(abs)
        }
        if let adapterPower, adapterPower > 0 {
            // While charging, the adapter sits at its delivery limit and
            // the charge current absorbs every load change, so PDTR pins
            // at a constant (the "stuck at 84 W" reports). The only live
            // usage signal then is the SoC power sensor (si10, ~15 W
            // below PDTR since it excludes display/drives/etc). When not
            // charging, PDTR IS the total system draw and moves every
            // tick (verified: step response within 1 s).
            if self.chargingOnAC(), let soc = Kit.SMC.shared.getValue("si10"), soc > 0 {
                return soc
            }
            return adapterPower
        }
        return batteryPower.map(abs)
    }

    /// Internal battery on AC with charging active (not the "not
    /// charging" / optimized-charging hold states, where PDTR is live).
    /// STATS_QA_WATTS_CHARGING=1 forces true so the smoke test can
    /// exercise the si10 branch without waiting for a real charge
    /// session; the `[QA] watts raw:` log keeps the true state visible.
    private func chargingOnAC() -> Bool {
        if ProcessInfo.processInfo.environment["STATS_QA_WATTS_CHARGING"] == "1" {
            return true
        }
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps).takeUnretainedValue() as? [String: Any],
               desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
               desc[kIOPSPowerSourceStateKey] as? String == "AC Power",
               desc[kIOPSIsChargingKey] as? Bool == true {
                return true
            }
        }
        return false
    }
    
    private func onBatteryPower() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        // Any entry on battery wins — the last-entry-wins loop reported
        // "AC Power" whenever a UPS or second source trailed the list.
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps).takeUnretainedValue() as? [String: Any] {
                if (desc[kIOPSPowerSourceStateKey] as? String ?? "AC Power") == "Battery Power" {
                    return true
                }
            }
        }
        return false
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
        
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.maxY + 2), in: button)
    }
    
    @objc private func menuOpen() {
        self.toggleFromItem()
    }
    
    @objc private func menuSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Dashboard"])
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
        SensorsAllPopover.shared.close()
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
        DispatchQueue.main.async {
            SMCHelper.shared.checkForUpdate()
            SMCHelper.shared.refreshReachability()
            NSLog("[UnifiedPopup] helper active=%d installed=%d signed=%d",
                  SMCHelper.shared.isActive() ? 1 : 0,
                  SMCHelper.shared.isInstalled ? 1 : 0,
                  SMCHelper.shared.isProperlySigned ? 1 : 0)
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

/// Standard system popover material with the mock's 16pt radius and
/// 1pt panel border (white 14% dark / black 7% light).
///
/// Top-origin coordinates for its chrome (scroll container, footer):
/// the panel is anchored at the menu bar and grows DOWNWARD, so the
/// band layout is expressed from the top.
private final class UnifiedPanelMaterialView: NSVisualEffectView {
    override var isFlipped: Bool { true }
    
    override func updateLayer() {
        super.updateLayer() // NSVisualEffectView draws the material here
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.borderColor = UnifiedTokens.panelBorder.cgColor
        }
    }
}

/// Manual clip container in place of NSScrollView: the panel window hugs
/// the menu bar and AppKit applies a variable safe-area content inset to
/// scroll views there, which no reset reliably defeats. Full control over
/// the offset also makes harness scroll knobs exact.
private final class UnifiedPopupScrollContainer: NSView {
    private weak var document: NSView?
    var offset: CGFloat = 0
    
    override var isFlipped: Bool { true }
    
    func host(_ document: NSView) {
        self.document = document
        self.addSubview(document)
    }
    
    var maxOffset: CGFloat {
        max((self.document?.frame.height ?? 0) - self.bounds.height, 0)
    }
    
    func scrollTo(_ value: CGFloat) {
        self.offset = min(max(value, 0), self.maxOffset)
        self.layoutContent()
    }
    
    func layoutContent() {
        guard let document = self.document else { return }
        document.frame = NSRect(x: 0, y: -self.offset, width: self.bounds.width, height: document.frame.height)
    }
    
    override func scrollWheel(with event: NSEvent) {
        self.scrollTo(self.offset + event.scrollingDeltaY)
    }
}

private final class UnifiedPopupPanel: NSPanel, NSWindowDelegate {
    static let panelWidth: CGFloat = 380
    
    private let effectView = UnifiedPanelMaterialView()
    private let scrollContainer = UnifiedPopupScrollContainer()
    private let content = UnifiedPanelContent(width: panelWidth)
    private let footerBar = NSView()
    
    var contentHeight: CGFloat {
        self.content.frame.height
    }
    
    override var canBecomeKey: Bool { true }
    
    /// Every path that makes the panel vanish ends here. The compact
    /// caller stack (first non-system frames) names which one — the
    /// [UnifiedPanelTrace] lines around it (toggle decision, key/main and
    /// active transitions) pin down the real status-item click flow.
    override func orderOut(_ sender: Any?) {
        let appFrames = Thread.callStackSymbols
            .filter { frame in
                !frame.contains("AppKit") && !frame.contains("Foundation") &&
                !frame.contains("CoreFoundation") && !frame.contains("libswiftCore") &&
                !frame.contains("libsystem") && !frame.contains("HIToolbox") &&
                !frame.contains("SwiftUI") && !frame.contains("UIKitMacHelper")
            }
            .prefix(6)
        NSLog("[UnifiedPanelTrace] panel orderOut (was visible=%d) callers: %@",
              self.isVisible ? 1 : 0,
              appFrames.joined(separator: " <- "))
        super.orderOut(sender)
    }
    
    // MARK: - NSWindowDelegate (traced)
    
    func windowDidBecomeKey(_ notification: Notification) {
        NSLog("[UnifiedPanelTrace] panel didBecomeKey visible=%d", self.isVisible ? 1 : 0)
    }
    
    func windowDidResignKey(_ notification: Notification) {
        NSLog("[UnifiedPanelTrace] panel didResignKey visible=%d", self.isVisible ? 1 : 0)
    }
    
    func windowDidBecomeMain(_ notification: Notification) {
        NSLog("[UnifiedPanelTrace] panel didBecomeMain visible=%d", self.isVisible ? 1 : 0)
    }
    
    func windowDidResignMain(_ notification: Notification) {
        NSLog("[UnifiedPanelTrace] panel didResignMain visible=%d", self.isVisible ? 1 : 0)
    }
    
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        
        // Status-item popups live at NSStatusWindowLevel, not .normal:
        // the opening click activates Stats and the system bounces a
        // deactivate back (traced), and the moment Stats deactivates,
        // other apps' regular windows restack ABOVE a .normal-level
        // panel and bury it — the open-then-vanish flash. At .statusBar
        // the panel floats above app windows even while Stats is
        // inactive (same as the Wi-Fi/Battery popups). Activation on
        // open stays: it is what dismisses another app's open dropdown.
        self.level = .statusBar
        self.collectionBehavior = .moveToActiveSpace
        self.backgroundColor = .clear
        // NSPanel's default is true; with activation-on-open (show())
        // the menu-bar click flow bounces a deactivate right after the
        // opening click, and AppKit would order this panel out on it —
        // the open-then-instantly-vanish flash. Outside clicks close the
        // panel through explicit monitors in UnifiedPopupController
        // instead, which are immune to that transient bounce.
        self.hidesOnDeactivate = false
        // opaque + behindWindow material (the classic popup recipe): a
        // non-opaque panel inherits the desktop safe area and the scroll
        // view gets a variable top content inset that hides the header
        self.isOpaque = true
        self.hasShadow = true
        self.delegate = self
        
        let chrome = UnifiedPopupContentView(frame: NSRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height))
        if ProcessInfo.processInfo.environment["STATS_POPUP_DEBUG_PAINT"] == "1" {
            chrome.wantsLayer = true
            chrome.layer?.backgroundColor = NSColor.systemPurple.cgColor
        }
        chrome.onEscape = { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
        }
        self.contentView = chrome
        
        self.effectView.material = .popover
        self.effectView.blendingMode = .behindWindow
        self.effectView.state = .active
        self.effectView.wantsLayer = true
        self.effectView.layer?.cornerRadius = UnifiedTokens.panelRadius
        self.effectView.layer?.borderWidth = 1
        self.effectView.layer?.masksToBounds = true
        self.effectView.frame = content.bounds
        self.effectView.autoresizingMask = [.width, .height]
        
        self.scrollContainer.wantsLayer = true
        self.scrollContainer.layer?.masksToBounds = true
        self.scrollContainer.frame = NSRect(x: 0, y: 0, width: contentRect.width, height: max(contentRect.height - 28, 60))
        self.scrollContainer.autoresizingMask = []
        self.scrollContainer.host(self.content)
        self.effectView.addSubview(self.scrollContainer)
        
        self.footerBar.frame = NSRect(x: 0, y: 0, width: contentRect.width, height: 28)
        self.footerBar.autoresizingMask = [.width]
        
        let separator = NSView(frame: NSRect(x: 12, y: 27, width: contentRect.width - 24, height: 1))
        separator.autoresizingMask = [.width]
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        self.footerBar.addSubview(separator)
        
        let activity = NSButton()
        activity.isBordered = false
        activity.attributedTitle = NSAttributedString(string: localizedString("Open Activity Monitor"), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor
        ])
        activity.target = self
        activity.action = #selector(self.openActivityMonitor)
        activity.sizeToFit()
        activity.frame = NSRect(x: 12, y: 3, width: activity.frame.width, height: 20)
        self.footerBar.addSubview(activity)
        
        let settings = NSButton()
        settings.isBordered = false
        settings.attributedTitle = NSAttributedString(string: localizedString("Settings"), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor
        ])
        settings.target = self
        settings.action = #selector(self.openSettings)
        settings.sizeToFit()
        
        // Quit is the destructive action and sits rightmost, red per macOS
        // convention; it terminates the app gracefully.
        let quit = NSButton()
        quit.isBordered = false
        quit.attributedTitle = NSAttributedString(string: localizedString("Quit Stats"), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.systemRed
        ])
        quit.target = self
        quit.action = #selector(self.quitApp)
        quit.sizeToFit()
        quit.frame = NSRect(x: contentRect.width - 12 - quit.frame.width, y: 3, width: quit.frame.width, height: 20)
        quit.autoresizingMask = [.minXMargin]
        self.footerBar.addSubview(quit)
        
        settings.frame = NSRect(x: quit.frame.origin.x - 8 - settings.frame.width, y: 3, width: settings.frame.width, height: 20)
        settings.autoresizingMask = [.minXMargin]
        self.footerBar.addSubview(settings)
        
        self.effectView.addSubview(self.footerBar)
        
        chrome.addSubview(self.effectView)
        
        // Content-layout changes (section expand, fan rebuild)
        // must resize the window immediately — previously this hook was
        // never assigned, so an expand rendered partially for up to a
        // second until the glyph timer happened to run syncSize.
        self.content.onLayoutChange = { [weak self] in
            guard let self, self.isVisible else { return }
            withoutImplicitAnimation {
                self.refreshContent()
                self.syncSize()
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Total content size the panel needs: document + footer.
    var requiredContentSize: NSSize {
        NSSize(width: Self.panelWidth, height: self.content.frame.height + 28)
    }
    
    /// Resize the window so the document and footer fit without
    /// scrolling; the top edge stays put.
    func syncSize() {
        let needed = self.requiredContentSize
        let current = self.contentView?.frame.size ?? .zero
        let heightDelta = abs(needed.height - current.height)
        self.pendingContentHeight = needed.height
        guard needed.width != current.width || heightDelta >= 1.5 else {
            self.layoutChrome()
            return
        }
        if UnifiedMotion.enabled, self.anchorTopY != nil {
            // The spring drives the WINDOW FRAME ONLY, self-timed, with
            // every frame anchored to anchorTopY (the menu-bar anchor).
            // AppKit's own frame animation does not keep the visual top
            // fixed mid-flight on this window class, which broke the
            // panel invariant (content above the expansion point must
            // keep identical screen coordinates at every frame).
            self.frameAnimationFrom = current.height
            self.frameAnimationTo = needed.height
            self.frameAnimationStart = Date()
            if self.frameAnimator == nil {
                self.frameAnimator = Timer.scheduledTimer(withTimeInterval: 1.0 / 90, repeats: true) { [weak self] _ in
                    self?.stepFrameAnimation()
                }
            }
            self.layoutChrome()
            return
        }
        if UnifiedPerf.enabled {
            UnifiedPerf.frameSet("syncResize")
            NSLog("[UnifiedPerf] syncResize %.1f -> %.1f", current.height, needed.height)
        }
        let top = self.anchorTopY ?? self.frame.maxY
        self.setContentSize(needed)
        var frame = self.frame
        frame.origin.y = top - frame.height
        self.setFrameOrigin(frame.origin)
        // Re-pin against the FINAL height in the same pass — pinning
        // against the pre-resize height leaves the chrome mis-placed for
        // one visible frame (the "appears in the wrong spot, then jumps"
        // defect).
        self.layoutChrome()
    }
    
    /// Self-driven window-frame spring: each tick re-frames the window
    /// anchored to the menu-bar top, so the visual top NEVER moves while
    /// the bottom eases out with a slight overshoot.
    private var frameAnimator: Timer?
    private var frameAnimationStart: Date?
    private var frameAnimationFrom: CGFloat = 0
    private var frameAnimationTo: CGFloat = 0
    
    private func stepFrameAnimation() {
        guard let start = self.frameAnimationStart else { return }
        let progress = min(Date().timeIntervalSince(start) / 0.28, 1)
        let eased = Self.easeOutBack(progress)
        let height = self.frameAnimationFrom + (self.frameAnimationTo - self.frameAnimationFrom) * eased
        let top = self.anchorTopY ?? self.frame.maxY
        var frame = self.frame
        frame.origin.y = top - height
        frame.size.height = height
        self.setFrame(frame, display: true)
        if progress >= 1 {
            self.frameAnimator?.invalidate()
            self.frameAnimator = nil
            var finalFrame = self.frame
            finalFrame.origin.y = top - self.frameAnimationTo
            finalFrame.size.height = self.frameAnimationTo
            self.setFrame(finalFrame, display: true)
        }
    }
    
    /// Ease-out-back (~280ms, slight overshoot) — the AppKit spring feel.
    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.25
        let c3 = c1 + 1
        let t = x - 1
        return 1 + c3 * t * t * t + c1 * t * t
    }
    
    /// Entrance: contentView layer transform scale 0.92→1.0 (anchored at
    /// the top-center, i.e. the menu bar icon) + alpha 0→1, ~200ms
    /// ease-out. Applied AFTER makeKeyAndOrderFront; skipped entirely
    /// when any QA/capture knob is active.
    func playEntrance() {
        guard UnifiedMotion.enabled, let view = self.contentView, let layer = view.layer else { return }
        view.wantsLayer = true
        var frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        layer.position = CGPoint(x: frame.midX, y: frame.maxY)
        layer.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
        })
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DMakeScale(0.92, 0.92, 1)
        animation.toValue = CATransform3DIdentity
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "entrance")
        layer.transform = CATransform3DIdentity
    }
    
    /// Exit: reverse of the entrance, snappier (~140ms); orderOut runs in
    /// the completion. Skipped when motion is gated (instant orderOut).
    func animateExit(completion: @escaping () -> Void) {
        guard UnifiedMotion.enabled, let view = self.contentView, let layer = view.layer else {
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            view.animator().alphaValue = 0
        }, completionHandler: {
            view.alphaValue = 1
            layer.transform = CATransform3DIdentity
            completion()
        })
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DIdentity
        animation.toValue = CATransform3DMakeScale(0.94, 0.94, 1)
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(animation, forKey: "exit")
        layer.transform = CATransform3DMakeScale(0.94, 0.94, 1)
    }
    
    func debugFrames() {
        NSLog("[UnifiedPopup] window=%@ contentView=%@ effect=%@ container=%@",
              NSStringFromRect(self.frame),
              NSStringFromRect(self.contentView?.frame ?? .zero),
              NSStringFromRect(self.effectView.frame),
              NSStringFromRect(self.scrollContainer.frame))
    }
    
    func refreshContent() {
        // the window's content rect can carry system insets that autoresizing
        // does not track; pin the material to the full content view explicitly
        if let bounds = self.contentView?.bounds, self.effectView.frame != bounds {
            UnifiedPerf.frameSet("effect")
            self.effectView.frame = bounds
        }
        self.content.relayout()
        self.layoutChrome()
        self.scrollContainer.layoutContent()
    }
    
    /// The panel's anchor top (screen maxY), captured at show(). The
    /// window grows DOWNWARD from the menu bar, so every resize —
    /// immediate or animated — must be anchored to THIS value, not to
    /// self.frame.maxY (the model frame can differ from the on-screen
    /// presentation mid-animation, which moved the visual top).
    private var anchorTopY: CGFloat? = nil
    func setAnchorTop(_ value: CGFloat) { self.anchorTopY = value }
    
    /// Target content height for the scroll container/footer geometry.
    /// syncSize/show set this BEFORE the frame reaches it, so chrome
    /// settles at final geometry in the same pass while the spring
    /// animates the window frame (the scroll container's top edge is
    /// constant — only its height follows content; see layoutChrome).
    private var pendingContentHeight: CGFloat? = nil
    
    /// Panel geometry invariant: the window is anchored at the menu bar
    /// and grows DOWNWARD (syncSize preserves maxY in both the immediate
    /// and the spring paths). Therefore at EVERY frame of any resize —
    /// including the expand spring — the content above the expanding
    /// section (brand header and everything before the expansion point)
    /// keeps IDENTICAL screen coordinates; only content at or below the
    /// expansion point translates. Consequences:
    ///  - the scroll container's TOP edge is constant — only its HEIGHT
    ///    follows content;
    ///  - the footer is bottom-anchored (moves with the bottom edge).
    /// `height` is the TARGET content height (pendingContentHeight) so
    /// the scroll/footer settle at final geometry in the same pass.
    func layoutChrome() {
        let height = self.pendingContentHeight ?? self.contentView?.frame.height ?? 0
        let containerFrame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: max(height - 28, 60))
        if self.scrollContainer.frame != containerFrame {
            UnifiedPerf.frameSet("container")
            self.scrollContainer.frame = containerFrame
        }
        let footerFrame = NSRect(x: 0, y: height - 28, width: Self.panelWidth, height: 28)
        if self.footerBar.frame != footerFrame {
            self.footerBar.frame = footerFrame
        }
    }
    
    /// show() sizes the window itself — record its target so chrome
    /// pinning never reads a stale or animating frame.
    func setPendingContentHeight(_ value: CGFloat) { self.pendingContentHeight = value }
    /// QA hook: drive a section header tap (same path as the gesture).
    func simulateHeaderTap(_ module: String) { self.content.simulateHeaderTap(module) }
    var expandedSectionForQA: String? { self.content.expandedSectionForQA }
    /// QA hook: open the all-sensors popover (same path as the row tap).
    func openAllSensorsForQA() { self.content.openAllSensorsForQA() }
    /// QA hook: collapsed states "name=1" pairs for the restore probe.
    var collapsedStatesForQA: String { self.content.collapsedStatesForQA }
    
    func expandSection(_ module: String) {
        self.content.expandSection(module)
    }
    
    func sectionOffset(for module: String) -> CGFloat? {
        self.content.sectionOffset(for: module)
    }
    
    func scrollToSection(_ module: String) {
        guard let offset = self.sectionOffset(for: module) else { return }
        self.scrollToOffset(offset)
    }
    
    func scrollToTop() {
        self.scrollContainer.scrollTo(0)
    }
    
    func scrollToBottom() {
        self.scrollContainer.scrollTo(self.content.frame.height)
    }
    
    func scrollToOffset(_ offset: Double) {
        self.scrollContainer.scrollTo(offset)
    }
    
    @objc private func openActivityMonitor() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc private func openSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Dashboard"])
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    /// Harness QA (STATS_POPUP_CAPTURE=1): renders the panel content into a
    /// PNG on disk, so captures work even when the console is locked.
    /// STATS_POPUP_CAPTURE_CHROME=1 additionally renders the footer bar
    /// next to the content capture as "<path>-footer.png" — the footer
    /// lives in the panel chrome, outside the content view.
    func writeSelfCapture() {
        let content = self.content
        content.relayout()
        let size = content.bounds.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            // A plain setNeedsDisplay + cacheDisplay composites from layer
            // caches: views that never had a display pass (freshly built
            // rows, NSScrollView document content) come out blank. A
            // synchronous display() pass first makes captures faithful.
            content.display()
            content.cacheDisplay(in: content.bounds, to: rep)
        }
        guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
        let path = ProcessInfo.processInfo.environment["STATS_POPUP_CAPTURE_PATH"] ?? "/tmp/unified-panel-selfcapture.png"
        try? png.write(to: URL(fileURLWithPath: path))
        NSLog("[UnifiedPopup] self capture written to %@", path)
        if ProcessInfo.processInfo.environment["STATS_POPUP_CAPTURE_CHROME"] == "1" {
            self.writeChromeCapture(self.footerBar, path: "\(path)-footer.png")
        }
    }
    
    /// Renders one chrome view (footer) into its own PNG. Skips hidden
    /// views.
    private func writeChromeCapture(_ view: NSView, path: String) {
        let size = view.bounds.size
        guard !view.isHidden, size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.display()
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        NSLog("[UnifiedPopup] chrome capture written to %@", path)
    }
}

private extension NSView {
    func setNeedsDisplayRecursively() {
        self.setNeedsDisplay(self.bounds)
        for subview in self.subviews {
            subview.setNeedsDisplayRecursively()
        }
    }
}

private final class UnifiedPopupContentView: NSView {
    var onEscape: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            self.onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
