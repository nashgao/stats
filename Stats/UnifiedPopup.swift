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
        self.installOutsideClickDismissal()
        if ProcessInfo.processInfo.environment["STATS_QA_FAN_CYCLE"] == "1" {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.qaFanSample(_:)),
                name: .unifiedPanelSample,
                object: nil
            )
        }
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
    
    private func dismissForOutsideClick(event: NSEvent?) {
        guard self.isEffectivelyVisible else { return }
        if let event {
            if event.window === self.panel { return }
            if event.window === self.statusItem?.button?.window { return }
        }
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
    private var isEffectivelyVisible: Bool {
        guard self.panel.isVisible, !self.panel.isMiniaturized else { return false }
        return self.panel.isOnActiveSpace
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
        if self.glyphTimer == nil {
            self.glyphTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateGlyph()
                if SMCHelper.shared.reachabilityRefreshDue(maxAge: 5) {
                    SMCHelper.shared.refreshReachability()
                }
                if self?.panel.isVisible == true {
                    withoutImplicitAnimation {
                        self?.panel.refreshContent()
                        self?.panel.syncSize()
                    }
                }
                UnifiedPerf.tick()
            }
        }
        self.updateGlyph()
        // Unified mode hides the module widgets, so nothing else may touch
        // the helper; establish the XPC connection here (idempotent, no-op
        // unless the daemon is registered and loaded).
        SMCHelper.shared.checkForUpdate()
        SMCHelper.shared.healIfNeeded()
        NSLog("[UnifiedPopup] status item installed (unified_widget=on) helper=%d",
              SMCHelper.shared.isActive() ? 1 : 0)
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
        if NSApp.currentEvent?.type == .rightMouseDown {
            self.showStatusMenu()
            return
        }
        self.toggleFromItem()
    }
    
    private func toggleFromItem() {
        if self.isEffectivelyVisible {
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
        guard let state = notification.userInfo?["state"] as? Bool, state else { return }
        self.hide()
    }
    
    func hide() {
        guard self.panel.isVisible else { return }
        self.panel.orderOut(nil)
    }
    
    func show(origin: NSPoint, center: CGFloat = 0, scrollTo: String? = nil) {
        // (Re)establish the SMC helper connection when the panel opens: covers
        // the app having launched before the helper was registered/approved.
        SMCHelper.shared.checkForUpdate()
        SMCHelper.shared.refreshReachability()
        NSLog("[UnifiedPopup] helper active=%d installed=%d signed=%d",
              SMCHelper.shared.isActive() ? 1 : 0,
              SMCHelper.shared.isInstalled ? 1 : 0,
              SMCHelper.shared.isProperlySigned ? 1 : 0)
        self.panel.refreshContent()
        
        // document + pinned island + pinned footer
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let height = max(348, min(self.panel.contentHeight + self.panel.islandSpace + 28, screenHeight * 0.7))
        let width = UnifiedPopupPanel.panelWidth
        var x = origin.x - width/2 + center
        let y = origin.y - height - 3
        
        let buttonPoint = NSPoint(x: origin.x + center, y: origin.y)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonPoint) }) ?? NSScreen.main {
            if x + width > screen.frame.maxX {
                x = screen.frame.maxX - width - 3
            }
            if x < screen.frame.minX {
                x = screen.frame.minX + 3
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
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        self.panel.makeKeyAndOrderFront(nil)
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
private final class UnifiedPanelMaterialView: NSVisualEffectView {
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
    
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        
        self.level = .normal
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
        
        self.effectView.addSubview(self.content.islandView)
        
        self.scrollContainer.wantsLayer = true
        self.scrollContainer.layer?.masksToBounds = true
        self.scrollContainer.frame = NSRect(x: 0, y: 28, width: contentRect.width, height: contentRect.height - 28)
        self.scrollContainer.autoresizingMask = [.width, .height]
        self.scrollContainer.host(self.content)
        self.effectView.addSubview(self.scrollContainer)
        
        self.footerBar.frame = NSRect(x: 0, y: 0, width: contentRect.width, height: 28)
        self.footerBar.autoresizingMask = [.width, .maxYMargin]
        
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
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
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
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var islandSpace: CGFloat { self.content.islandSpace }
    
    /// Total content size the panel needs: document + island + footer.
    var requiredContentSize: NSSize {
        NSSize(width: Self.panelWidth, height: self.content.frame.height + self.content.islandSpace + 28)
    }
    
    /// Resize the window so the document, island, and footer fit without
    /// scrolling; the top edge stays put.
    func syncSize() {
        let needed = self.requiredContentSize
        let current = self.contentView?.frame.size ?? .zero
        let heightDelta = abs(needed.height - current.height)
        guard needed.width != current.width || heightDelta >= 1.5 else { return }
        if UnifiedPerf.enabled {
            UnifiedPerf.frameSet("syncResize")
            NSLog("[UnifiedPerf] syncResize %.1f -> %.1f", current.height, needed.height)
        }
        let top = self.frame.maxY
        self.setContentSize(needed)
        var frame = self.frame
        frame.origin.y = top - frame.height
        self.setFrameOrigin(frame.origin)
    }
    
    func debugFrames() {
        NSLog("[UnifiedPopup] window=%@ contentView=%@ effect=%@ container=%@ island=%@ islandHidden=%d",
              NSStringFromRect(self.frame),
              NSStringFromRect(self.contentView?.frame ?? .zero),
              NSStringFromRect(self.effectView.frame),
              NSStringFromRect(self.scrollContainer.frame),
              NSStringFromRect(self.content.islandView.frame),
              self.content.islandView.isHidden ? 1 : 0)
    }
    
    func refreshContent() {
        // the window's content rect can carry system insets that autoresizing
        // does not track; pin the material to the full content view explicitly
        if let bounds = self.contentView?.bounds, self.effectView.frame != bounds {
            UnifiedPerf.frameSet("effect")
            self.effectView.frame = bounds
        }
        self.content.relayout()
        let island = self.content.islandSpace
        self.content.layoutIsland(width: Self.panelWidth)
        let height = self.contentView?.frame.height ?? 0
        self.content.islandView.frame.origin.y = height - island
        let containerFrame = NSRect(x: 0, y: 28, width: Self.panelWidth, height: max(height - 28 - island, 60))
        if self.scrollContainer.frame != containerFrame {
            UnifiedPerf.frameSet("container")
            self.scrollContainer.frame = containerFrame
        }
        self.scrollContainer.layoutContent()
    }
    
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
    func writeSelfCapture() {
        let content = self.content
        content.relayout()
        let size = content.bounds.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            content.setNeedsDisplayRecursively()
            content.cacheDisplay(in: content.bounds, to: rep)
        }
        guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
        let path = ProcessInfo.processInfo.environment["STATS_POPUP_CAPTURE_PATH"] ?? "/tmp/unified-panel-selfcapture.png"
        try? png.write(to: URL(fileURLWithPath: path))
        NSLog("[UnifiedPopup] self capture written to %@", path)
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
