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
    private var populated: Bool = false
    
    private init() {
        self.panel = UnifiedPopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: UnifiedPopupPanel.panelWidth, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }
    
    func show(origin: NSPoint) {
        if !self.populated {
            let selected = UnifiedPopupController.moduleOrder.compactMap { name in
                modules.first(where: { $0.config.name == name })
            }
            self.panel.populate(modules: selected)
            self.populated = true
        }
        
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let height = max(320, min(self.panel.contentHeight, screenHeight * 0.7))
        let width = UnifiedPopupPanel.panelWidth
        let rect = NSRect(x: origin.x - width/2, y: origin.y - height - 3, width: width, height: height)
        self.panel.setFrame(rect, display: true)
        self.panel.appearSections()
        self.panel.scrollToTop()
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
    private var sections: [(header: NSTextField, popup: Popup_p)] = []
    
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
        for (header, popup) in self.sections {
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
            self.sections.append((header, popup))
        }
        self.relayout()
    }
    
    func appearSections() {
        for (_, popup) in self.sections { popup.appear() }
    }
    
    func disappearSections() {
        for (_, popup) in self.sections { popup.disappear() }
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
        for (header, popup) in self.sections {
            header.frame = NSRect(x: margin, y: y, width: Self.panelWidth - margin*2, height: headerHeight)
            y += headerHeight + 4
            popup.frame = NSRect(x: margin, y: y, width: Constants.Popup.width, height: popup.frame.height)
            y += popup.frame.height + 12
        }
        y += margin - 12
        self.document.frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: max(y, 1))
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
