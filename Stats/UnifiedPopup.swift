//
//  UnifiedPopup.swift
//  Stats
//
//  Prototype: unified all-modules popup (mission control panel).
//  Harness-only entry point (STATS_POPUP_MODULE=All); menu bar
//  integration is intentionally not included.
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
        button.image = iconFromSymbol(name: "chart.bar.fill", scale: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = #selector(self.togglePanel)
        button.toolTip = localizedString("Open unified popup")
        self.statusItem = item
        if self.glyphTimer == nil {
            self.glyphTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateGlyph()
                if self?.panel.isVisible == true {
                    self?.panel.updateAttentionChrome()
                }
            }
        }
        self.updateGlyph()
        NSLog("[UnifiedPopup] status item installed (unified_widget=on)")
    }
    
    /// Adaptive glyph + tint, evaluated on a ~1s cadence from the shared
    /// AttentionEvaluator. Status pairs the glyph with a tint: secondary
    /// label color when quiet, systemOrange for attention, systemRed for
    /// critical; accent blue stays reserved for interaction. Attention
    /// tints are baked into the image because NSStatusBarButton does not
    /// reliably apply contentTintColor to swapped symbol images.
    private func updateGlyph() {
        guard let button = self.statusItem?.button else { return }
        let attention = AttentionEvaluator.shared.primary
        let key = attention.map { "\($0.kind.rawValue)-\($0.level.rawValue)" } ?? "default"
        guard key != self.glyphState else { return }
        self.glyphState = key
        
        var image: NSImage
        var tint = NSColor.secondaryLabelColor
        switch attention?.kind {
        case .some(.fan):
            image = self.symbolImage("fanblades.fill", fallback: "wind")
        case .some(.temperature):
            image = self.symbolImage("thermometer.medium", fallback: "thermometer")
        case .some(.memory):
            image = self.symbolImage("memorychip", fallback: "square.stack.3d.up.fill")
        case .some(.gpu):
            image = self.symbolImage("gauge.high", fallback: "gauge")
        case .some(.battery):
            image = self.symbolImage("battery.100bolt", fallback: "bolt.fill")
        default:
            image = iconFromSymbol(name: "chart.bar.fill", scale: .medium)
        }
        if let attention {
            tint = attention.level == .critical ? .systemRed : .systemOrange
            image = self.tinted(image, with: tint)
        }
        button.image = image
        button.contentTintColor = tint
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
        
        // The unified panel re-parents module popup views, so any open
        // module popup must be closed first.
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
        
        // The unified panel re-parents module popup views, so any open
        // module popup must be closed first.
        modules.forEach { $0.closePopupIfVisible() }
        self.show(origin: origin, center: center, scrollTo: target)
    }
    
    @objc private func modulePopupVisibilityChanged(_ notification: Notification) {
        guard let state = notification.userInfo?["state"] as? Bool, state else { return }
        // A module popup is showing (and has reclaimed its view): close the
        // unified surface so both never present module content at once.
        self.hide()
    }
    
    func hide() {
        guard self.panel.isVisible else { return }
        self.panel.disappearSections()
        self.panel.orderOut(nil)
    }
    
    func show(origin: NSPoint, center: CGFloat = 0, scrollTo: String? = nil) {
        let selected = UnifiedPopupController.moduleOrder.compactMap { name in
            modules.first(where: { $0.config.name == name })
        }
        // Re-parent on every show: a module popup may have reclaimed its view.
        self.panel.populate(modules: selected)
        self.panel.updateAttentionChrome()
        
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
        self.panel.appearSections()
        if let scrollTo {
            self.panel.scrollToSection(scrollTo)
        } else {
            self.panel.scrollToTop()
        }
        self.panel.orderFrontRegardless()
        if let scrollTo = ProcessInfo.processInfo.environment["STATS_POPUP_SCROLL_TO"] {
            if scrollTo == "bottom" {
                self.panel.scrollToBottom()
            } else if let offset = Double(scrollTo) {
                self.panel.scrollToOffset(offset)
            }
        }
        NSLog("[UnifiedPopup] shown: %d sections, content %.0fpt, panel %.0fpt", self.panel.sectionsCount, self.panel.contentHeight, height)
    }
}

private final class UnifiedPopupPanel: NSPanel {
    static let panelWidth = Constants.Popup.width + Constants.Popup.margins*2
    
    private let effectView = NSVisualEffectView()
    private let backgroundView = UnifiedPopupBackgroundView()
    private let scrollView = NSScrollView()
    private let document = UnifiedPopupDocumentView()
    private var sections: [(name: String, header: NSTextField, popup: Popup_p)] = []
    private let headlineView = UnifiedPopupHeadlineView()
    private var badges: [String: NSTextField] = [:]
    private let footerBar = NSView()
    
    var contentHeight: CGFloat {
        self.document.frame.height
    }
    var sectionsCount: Int {
        self.sections.count
    }
    
    override var canBecomeKey: Bool { true }
    
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        
        self.level = .normal
        self.collectionBehavior = .moveToActiveSpace
        self.backgroundColor = .clear
        self.hasShadow = true
        
        let content = UnifiedPopupContentView(frame: NSRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height))
        content.onEscape = { [weak self] in
            guard let self else { return }
            self.disappearSections()
            self.orderOut(nil)
        }
        self.contentView = content
        
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
        self.scrollView.documentView = self.document
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
        
        self.headlineView.isHidden = true
        self.document.addSubview(self.headlineView)
        
        content.addSubview(self.effectView)
    }
    
    /// Health headline strip + per-section attention badges, driven by the
    /// shared AttentionEvaluator. The strip hides entirely when quiet.
    func updateAttentionChrome() {
        let attentions = AttentionEvaluator.shared.attentions
        
        if attentions.isEmpty {
            self.headlineView.isHidden = true
        } else {
            let text = NSMutableAttributedString()
            for (index, attention) in attentions.enumerated() {
                if index > 0 {
                    text.append(NSAttributedString(string: "  ·  ", attributes: [
                        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]))
                }
                text.append(NSAttributedString(string: attention.label, attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: attention.level == .critical ? NSColor.systemRed : NSColor.systemOrange
                ]))
            }
            self.headlineView.attributedStringValue = text
            self.headlineView.isHidden = false
        }
        
        for (name, _, _) in self.sections {
            guard let badge = self.badges[name] else { continue }
            if let attention = AttentionEvaluator.shared.attention(for: name) {
                badge.attributedStringValue = NSAttributedString(
                    string: "● \(Self.shortLabel(attention))",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                        .foregroundColor: attention.level == .critical ? NSColor.systemRed : NSColor.systemOrange
                    ]
                )
                badge.isHidden = false
            } else {
                badge.isHidden = true
            }
        }
        
        self.relayout()
    }
    
    private static func shortLabel(_ attention: Attention) -> String {
        switch attention.kind {
        case .fan, .temperature: return attention.label
        default:
            if attention.label.hasPrefix(attention.module + " ") {
                return String(attention.label.dropFirst(attention.module.count + 1))
            }
            return attention.label
        }
    }
    
    func populate(modules: [Module]) {
        for (_, header, popup) in self.sections {
            header.removeFromSuperview()
            popup.removeFromSuperview()
        }
        self.sections = []
        self.badges.values.forEach { $0.removeFromSuperview() }
        self.badges = [:]
        
        for module in modules {
            guard let popup = module.embeddedPopupView else { continue }
            (popup as? PopupWrapper)?.setChromeFooterHidden(true)
            
            let header = NSTextField(labelWithString: "")
            header.attributedStringValue = NSAttributedString(string: module.config.name, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ])
            self.document.addSubview(header)
            self.document.addSubview(popup)
            
            let badge = NSTextField(labelWithString: "")
            badge.lineBreakMode = .byTruncatingTail
            badge.isHidden = true
            self.document.addSubview(badge)
            self.badges[module.config.name] = badge
            
            let previous = popup.sizeCallback
            popup.sizeCallback = { [weak self] size in
                previous?(size)
                self?.relayout()
            }
            self.sections.append((module.config.name, header, popup))
        }
        self.relayout()
    }
    
    func appearSections() {
        for (_, _, popup) in self.sections { popup.appear() }
    }
    
    func disappearSections() {
        for (_, _, popup) in self.sections { popup.disappear() }
    }
    
    func scrollToTop() {
        self.document.scroll(NSPoint(x: 0, y: 0))
    }
    
    func scrollToBottom() {
        self.document.scroll(NSPoint(x: 0, y: self.document.frame.height))
    }
    
    func scrollToOffset(_ offset: Double) {
        self.document.scroll(NSPoint(x: 0, y: offset))
    }
    
    private func relayout() {
        let margin = Constants.Popup.margins
        let headerHeight: CGFloat = 20
        var y: CGFloat = margin
        if !self.headlineView.isHidden {
            self.headlineView.frame = NSRect(x: margin, y: y, width: Self.panelWidth - margin*2, height: 20)
            y += 26
        }
        for (name, header, popup) in self.sections {
            header.frame = NSRect(x: margin, y: y, width: Self.panelWidth - margin*2, height: headerHeight)
            if let badge = self.badges[name] {
                badge.sizeToFit()
                let width = min(badge.frame.width, Self.panelWidth / 2)
                badge.frame = NSRect(x: Self.panelWidth - margin - width, y: y + 3, width: width, height: 14)
            }
            y += headerHeight + 4
            popup.frame = NSRect(x: margin, y: y, width: Constants.Popup.width, height: popup.frame.height)
            y += popup.frame.height + 12
        }
        y += margin - 12
        self.document.frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: max(y, 1))
    }
    
    /// Scroll the document so the named module's section header sits near
    /// the top of the visible area.
    func scrollToSection(_ name: String) {
        guard let section = self.sections.first(where: { $0.name == name }) else { return }
        let target = max(section.header.frame.origin.y - 8, 0)
        self.document.scroll(NSPoint(x: 0, y: target))
    }
    
    @objc private func openActivityMonitor() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc private func openSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Dashboard"])
    }
}

private final class UnifiedPopupDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class UnifiedPopupHeadlineView: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.isEditable = false
        self.isSelectable = false
        self.isBezeled = false
        self.drawsBackground = false
        self.lineBreakMode = .byTruncatingTail
        self.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
