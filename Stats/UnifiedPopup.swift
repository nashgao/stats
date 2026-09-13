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

final class UnifiedPopupController {
    static let shared = UnifiedPopupController()
    
    static let moduleOrder = ["CPU", "GPU", "RAM", "Disk", "Network", "Sensors", "Battery"]
    
    private let panel: UnifiedPopupPanel
    private var statusItem: NSStatusItem? = nil
    private var glyphTimer: Timer?
    private var glyphState: String = ""
    
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
    }
    
    var isVisible: Bool {
        self.panel.isVisible
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
        button.toolTip = localizedString("Open unified popup")
        self.statusItem = item
        if self.glyphTimer == nil {
            self.glyphTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateGlyph()
                if self?.panel.isVisible == true {
                    self?.panel.refreshContent()
                }
            }
        }
        self.updateGlyph()
        NSLog("[UnifiedPopup] status item installed (unified_widget=on)")
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
        if self.panel.isVisible {
            self.hide()
            return
        }
        
        // Only one popup surface at a time.
        modules.forEach { $0.closePopupIfVisible() }
        
        guard let window = self.statusItem?.button?.window else { return }
        self.show(origin: window.frame.origin, center: window.frame.width/2)
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
        
        if self.panel.isVisible {
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
        self.panel.refreshContent()
        
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let height = max(320, min(self.panel.contentHeight, screenHeight * 0.7))
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
        
        self.panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if let scrollTo, let offset = self.panel.sectionOffset(for: scrollTo) {
            self.panel.scrollToOffset(offset)
        } else {
            self.panel.scrollToTop()
        }
        self.panel.orderFrontRegardless()
        if let scrollToEnv = ProcessInfo.processInfo.environment["STATS_POPUP_SCROLL_TO"] {
            if scrollToEnv == "bottom" {
                self.panel.scrollToBottom()
            } else if let offset = Double(scrollToEnv) {
                self.panel.scrollToOffset(offset)
            }
        }
        if ProcessInfo.processInfo.environment["STATS_POPUP_CAPTURE"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.panel.writeSelfCapture()
            }
        }
        NSLog("[UnifiedPopup] shown: content %.0fpt, panel %.0fpt", self.panel.contentHeight, height)
    }
}

private final class UnifiedPopupPanel: NSPanel {
    static let panelWidth: CGFloat = 360
    
    private let effectView = NSVisualEffectView()
    private let backgroundView = UnifiedPopupBackgroundView()
    private let scrollView = NSScrollView()
    private let content = UnifiedPanelContent(width: panelWidth - Constants.Popup.margins * 2)
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
        self.hasShadow = true
        
        let chrome = UnifiedPopupContentView(frame: NSRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height))
        chrome.onEscape = { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
        }
        self.contentView = chrome
        
        self.effectView.material = .titlebar
        self.effectView.blendingMode = .behindWindow
        self.effectView.state = .active
        self.effectView.wantsLayer = true
        self.effectView.layer?.cornerRadius = Constants.Popup.radius
        self.effectView.layer?.masksToBounds = true
        self.effectView.frame = content.bounds
        self.effectView.autoresizingMask = [.width, .height]
        
        self.backgroundView.wantsLayer = true
        self.backgroundView.frame = self.effectView.bounds
        self.backgroundView.autoresizingMask = [.width, .height]
        self.effectView.addSubview(self.backgroundView)
        
        self.scrollView.drawsBackground = false
        self.scrollView.borderType = .noBorder
        self.scrollView.hasVerticalScroller = true
        self.scrollView.hasHorizontalScroller = false
        self.scrollView.autohidesScrollers = true
        self.scrollView.horizontalScrollElasticity = .none
        self.scrollView.scrollerStyle = .overlay
        self.scrollView.frame = NSRect(x: 0, y: 28, width: contentRect.width, height: contentRect.height - 28)
        self.scrollView.autoresizingMask = [.width, .height]
        self.scrollView.documentView = self.content
        self.effectView.addSubview(self.scrollView)
        
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
        settings.frame = NSRect(x: contentRect.width - 12 - settings.frame.width, y: 3, width: settings.frame.width, height: 20)
        settings.autoresizingMask = [.minXMargin]
        self.footerBar.addSubview(settings)
        
        self.effectView.addSubview(self.footerBar)
        
        chrome.addSubview(self.effectView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func refreshContent() {
        self.content.relayout()
    }
    
    func sectionOffset(for module: String) -> CGFloat? {
        self.content.sectionOffset(for: module)
    }
    
    func scrollToSection(_ module: String) {
        guard let offset = self.sectionOffset(for: module) else { return }
        self.scrollToOffset(offset)
    }
    
    func scrollToTop() {
        self.content.scroll(NSPoint(x: 0, y: 0))
    }
    
    func scrollToBottom() {
        self.content.scroll(NSPoint(x: 0, y: self.content.frame.height))
    }
    
    func scrollToOffset(_ offset: Double) {
        self.content.scroll(NSPoint(x: 0, y: offset))
    }
    
    @objc private func openActivityMonitor() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc private func openSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Dashboard"])
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

private final class UnifiedPopupBackgroundView: NSView {
    override func updateLayer() {
        self.layer?.backgroundColor = self.isDarkMode
            ? .clear
            : Constants.Design.surfaceElevated.cgColor
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
