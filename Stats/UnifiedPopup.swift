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
        NSLog("[UnifiedPopup] status item installed (unified_widget=on)")
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
    /// clicked widget, scrolled to that module's section. If the panel is
    /// already open, just re-anchors the scroll.
    @objc private func routeUnifiedPopup(_ notification: Notification) {
        guard UnifiedPopupRouting.isEnabled,
              let origin = notification.userInfo?["origin"] as? CGPoint,
              let center = notification.userInfo?["center"] as? CGFloat else { return }
        let anchor = notification.userInfo?["module"] as? String
        
        if self.panel.isVisible {
            if let anchor {
                self.panel.scrollToSection(anchor)
            }
            return
        }
        
        // The unified panel re-parents module popup views, so any open
        // module popup must be closed first.
        modules.forEach { $0.closePopupIfVisible() }
        self.show(origin: origin, center: center, scrollTo: anchor)
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
        self.scrollView.frame = content.bounds
        self.scrollView.autoresizingMask = [.width, .height]
        self.scrollView.documentView = self.document
        self.effectView.addSubview(self.scrollView)
        
        content.addSubview(self.effectView)
    }
    
    func populate(modules: [Module]) {
        for (_, header, popup) in self.sections {
            header.removeFromSuperview()
            popup.removeFromSuperview()
        }
        self.sections = []
        
        for module in modules {
            guard let popup = module.embeddedPopupView else { continue }
            
            let header = NSTextField(labelWithString: "")
            header.attributedStringValue = NSAttributedString(string: module.config.name, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ])
            self.document.addSubview(header)
            self.document.addSubview(popup)
            
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
        for (_, header, popup) in self.sections {
            header.frame = NSRect(x: margin, y: y, width: Self.panelWidth - margin*2, height: headerHeight)
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
}

private final class UnifiedPopupDocumentView: NSView {
    override var isFlipped: Bool { true }
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
