//
//  popup.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 11/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public final class PopupCache<T> {
    public var value: T?
    public var initialized: Bool = false
    
    public init() {}
    
    public func apply(_ value: T, visible: Bool, render: (T) -> Void) {
        self.value = value
        if visible || !self.initialized {
            render(value)
            self.initialized = true
        }
    }
    
    public func replay(render: (T) -> Void) {
        if let v = self.value { render(v) }
    }
}

public protocol Popup_p: NSView {
    var keyboardShortcut: [UInt16] { get }
    var subtitle: String? { get }
    var sizeCallback: ((NSSize) -> Void)? { get set }
    
    func settings() -> NSView?
    
    func appear()
    func disappear()
    func setKeyboardShortcut(_ binding: [UInt16])
}

open class PopupWrapper: NSStackView, Popup_p {
    public var title: String
    public var keyboardShortcut: [UInt16] = []
    open var subtitle: String? = nil
    open var sizeCallback: ((NSSize) -> Void)? = nil

    internal let module: ModuleType

    public let sectionTopPadding: CGFloat = 9
    public let sectionTitleHeight: CGFloat = 13
    public let sectionTitleGap: CGFloat = 7
    public let sectionSidePadding: CGFloat = Constants.Design.space3
    public let sectionBottomPadding: CGFloat = 10
    public let heroSidePadding: CGFloat = Constants.Design.space3
    public var sectionHeaderHeight: CGFloat {
        self.sectionTopPadding + self.sectionTitleHeight + self.sectionTitleGap
    }

    internal var tonalViews: [NSView] = []
    internal var hairlineViews: [NSView] = []

    public init(_ typ: ModuleType, frame: NSRect) {
        self.title = typ.stringValue
        self.module = typ
        self.keyboardShortcut = Store.shared.array(key: "\(typ.stringValue)_popup_keyboardShortcut", defaultValue: []) as? [UInt16] ?? []

        super.init(frame: frame)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open func settings() -> NSView? { return nil }
    open func appear() {}
    open func disappear() {}
    
    open func setKeyboardShortcut(_ binding: [UInt16]) {
        self.keyboardShortcut = binding
        Store.shared.set(key: "\(self.title)_popup_keyboardShortcut", value: binding)
    }
    
    public func apply<T>(_ value: T, to cache: PopupCache<T>, render: @escaping (T) -> Void) {
        DispatchQueue.main.async {
            cache.apply(value, visible: self.window?.isVisible ?? false, render: render)
        }
    }
    
    public func replay<T>(_ cache: PopupCache<T>, render: (T) -> Void) {
        cache.replay(render: render)
    }

    // MARK: - unified panel chrome

    private var chromeFooterHidden: Bool = false

    /// Embedded mode: the unified panel hides the per-popup footer (it has
    /// its own shared footer) and resets it when the view is re-attached to
    /// its classic popup window. Classic popups never set this.
    public func setChromeFooterHidden(_ hidden: Bool) {
        guard self.chromeFooterHidden != hidden else { return }
        self.chromeFooterHidden = hidden
        self.applyChromeFooterState()
        self.refreshContentHeight()
    }

    private func applyChromeFooterState() {
        self.subviews.forEach { subview in
            if subview is PopupFooterView {
                subview.isHidden = self.chromeFooterHidden
            }
        }
    }

    open override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if self.chromeFooterHidden, subview is PopupFooterView {
            subview.isHidden = true
        }
    }

    /// Stack height of the visible content, matching the recalculateHeight
    /// formula shared by the module popups, with hidden chrome excluded.
    public func contentHeight() -> CGFloat {
        var h: CGFloat = self.spacing * CGFloat(max(self.arrangedSubviews.count - 1, 0))
        self.arrangedSubviews.forEach { v in
            if v.isHidden { return }
            if let v = v as? NSStackView {
                let rows = v.arrangedSubviews
                h += v.edgeInsets.top + v.edgeInsets.bottom
                h += rows.map({ $0.bounds.height }).reduce(0, +)
                h += v.spacing * CGFloat(max(rows.count - 1, 0))
            } else {
                h += v.bounds.height
            }
        }
        return h
    }

    public func refreshContentHeight() {
        let h = self.contentHeight()
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
        }
        self.sizeCallback?(self.frame.size)
    }

    // MARK: - redesign scaffolding

    public func applySemanticColors() {
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            let group = Constants.Design.surfaceGroup.cgColor
            let hairline = Constants.Design.separatorSubtle.withAlphaComponent(Constants.Design.separatorOpacity).cgColor
            self.tonalViews.forEach { $0.layer?.backgroundColor = group }
            self.hairlineViews.forEach { $0.layer?.backgroundColor = hairline }
        }
    }

    public func untrackTonalViews(_ views: [NSView]) {
        self.tonalViews.removeAll(where: { views.contains($0) })
    }

    private func sectionTitleLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 0.6
        ])
        return label
    }

    public func sectionView(_ title: String, height: CGFloat, button: NSButton? = nil) -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: height))
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        view.wantsLayer = true
        view.layer?.cornerRadius = Constants.Design.innerRadius
        self.tonalViews.append(view)

        let label = self.sectionTitleLabel(title)
        label.frame = NSRect(
            x: self.sectionSidePadding,
            y: height - self.sectionTopPadding - self.sectionTitleHeight,
            width: self.frame.width - self.sectionSidePadding*2,
            height: self.sectionTitleHeight
        )
        view.addSubview(label)

        if let button {
            view.addSubview(button)
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -self.sectionSidePadding + 4),
                button.topAnchor.constraint(equalTo: view.topAnchor, constant: 3)
            ])
        }

        return view
    }

    public func sectionStack(_ title: String, button: NSButton? = nil) -> NSStackView {
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width - self.sectionSidePadding*2, height: 0))
        view.orientation = .vertical
        view.spacing = 0
        view.wantsLayer = true
        view.layer?.cornerRadius = Constants.Design.innerRadius
        view.edgeInsets = NSEdgeInsets(
            top: 0,
            left: self.sectionSidePadding,
            bottom: self.sectionBottomPadding,
            right: self.sectionSidePadding
        )
        view.widthAnchor.constraint(equalToConstant: self.frame.width).isActive = true
        self.tonalViews.append(view)

        let header = NSView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: self.sectionHeaderHeight))
        header.heightAnchor.constraint(equalToConstant: self.sectionHeaderHeight).isActive = true

        let label = self.sectionTitleLabel(title)
        label.frame = NSRect(
            x: 0,
            y: self.sectionHeaderHeight - self.sectionTopPadding - self.sectionTitleHeight,
            width: view.frame.width,
            height: self.sectionTitleHeight
        )
        header.addSubview(label)
        view.addArrangedSubview(header)

        if let button {
            header.addSubview(button)
            NSLayoutConstraint.activate([
                button.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: 4),
                button.topAnchor.constraint(equalTo: header.topAnchor, constant: 3)
            ])
        }

        return view
    }

    public func makeChip() -> (NSView, NSTextField) {
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false

        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = Constants.Design.chipRadius
        chip.isHidden = true
        chip.addSubview(field)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            chip.heightAnchor.constraint(equalToConstant: 18)
        ])

        self.tonalViews.append(chip)

        return (chip, field)
    }

    public func addDetailSeparator(_ container: NSStackView, width: CGFloat) {
        let hairline = NSView(frame: NSRect(x: 0, y: 0, width: width, height: Constants.Design.hairlineWidth))
        hairline.heightAnchor.constraint(equalToConstant: Constants.Design.hairlineWidth).isActive = true
        hairline.wantsLayer = true
        self.hairlineViews.append(hairline)
        container.addArrangedSubview(hairline)
    }

    public func footerView() -> NSView {
        return PopupFooterView(width: self.frame.width, module: self.module)
    }
}

internal enum PopupKeyAction: Equatable {
    case close
    case settings
    case none
}

internal func popupKeyAction(for event: NSEvent) -> PopupKeyAction {
    guard event.type == .keyDown else { return .none }
    if event.keyCode == 53 { return .close }
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "," {
        return .settings
    }
    return .none
}

public class PopupWindow: NSWindow, NSWindowDelegate {
    private let viewController: PopupViewController
    internal var locked: Bool = false
    internal var openedBy: widget_t? = nil
    
    public init(title: String, module: ModuleType, view: Popup_p?, visibilityCallback: @escaping (_ state: Bool) -> Void) {
        self.viewController = PopupViewController(module: module)
        self.viewController.setup(title: title, view: view)
        
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: self.viewController.view.frame.width,
                height: self.viewController.view.frame.height
            ),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        
        self.viewController.visibilityCallback = { [weak self] state in
            self?.locked = false
            visibilityCallback(state)
        }
        
        self.title = title
        self.titleVisibility = .hidden
        self.contentViewController = self.viewController
        self.titlebarAppearsTransparent = true
        self.animationBehavior = .default
        self.collectionBehavior = .moveToActiveSpace
        self.backgroundColor = .clear
        self.hasShadow = true
        self.setIsVisible(false)
        self.delegate = self
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        switch popupKeyAction(for: event) {
        case .close:
            self.setIsVisible(false)
            return true
        case .settings:
            NotificationCenter.default.post(
                name: .toggleSettings,
                object: nil,
                userInfo: ["module": self.title]
            )
            self.setIsVisible(false)
            return true
        case .none:
            return super.performKeyEquivalent(with: event)
        }
    }
    
    public func windowWillMove(_ notification: Notification) {
        self.viewController.setCloseButton(true)
        self.locked = true
    }
    
    /// Re-embed the popup content view into this window. Called when the
    /// popup is opened while its view is hosted inside the unified popup.
    /// Resets the unified panel's embedded chrome state so the classic popup
    /// keeps its full footer.
    public func reattachView(_ view: Popup_p?) {
        guard let view else { return }
        (view as? PopupWrapper)?.setChromeFooterHidden(false)
        self.viewController.setup(title: self.title, view: view)
    }
    
    public func windowDidResignKey(_ notification: Notification) {
        if self.locked {
            return
        }
        
        self.viewController.setCloseButton(false)
        self.setIsVisible(false)
    }
}

internal class PopupViewController: NSViewController {
    fileprivate var visibilityCallback: (_ state: Bool) -> Void = {_ in }
    private var popup: PopupView
    
    public init(module: ModuleType) {
        self.popup = PopupView(frame: NSRect(
            x: 0,
            y: 0,
            width: Constants.Popup.width + (Constants.Popup.margins * 2),
            height: Constants.Popup.height+Constants.Popup.headerHeight
        ), module: module)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        self.view = self.popup
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        self.popup.appear()
        self.visibilityCallback(true)
        NotificationCenter.default.post(name: .popupVisibilityChanged, object: nil, userInfo: ["state": true])
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        self.popup.disappear()
        self.visibilityCallback(false)
        NotificationCenter.default.post(name: .popupVisibilityChanged, object: nil, userInfo: ["state": false])
    }
    
    fileprivate func setup(title: String, view: Popup_p?) {
        self.title = title
        self.popup.setTitle(title)
        self.popup.setView(view)
    }
    
    fileprivate func setCloseButton(_ state: Bool) {
        self.popup.setCloseButton(state)
    }
}

internal class PopupView: NSView {
    private var view: Popup_p? = nil
    
    private var foreground: NSVisualEffectView
    private var background: NSView
    
    private let header: HeaderView
    private let body: NSScrollView
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: self.frame.width, height: self.frame.height)
    }
    private var windowHeight: CGFloat?
    private var containerHeight: CGFloat?
    
    init(frame: NSRect, module: ModuleType) {
        self.header = HeaderView(frame: NSRect(
            x: 0,
            y: frame.height - Constants.Popup.headerHeight,
            width: frame.width,
            height: Constants.Popup.headerHeight
        ), module: module)
        self.body = NSScrollView(frame: NSRect(
            x: Constants.Popup.margins,
            y: Constants.Popup.margins,
            width: frame.width - Constants.Popup.margins*2,
            height: frame.height - self.header.frame.height - Constants.Popup.margins*2
        ))
        self.windowHeight = NSScreen.main?.visibleFrame.height
        self.containerHeight = self.body.documentView?.frame.height
        
        self.foreground = NSVisualEffectView(frame: frame)
        self.foreground.material = .titlebar
        self.foreground.blendingMode = .behindWindow
        self.foreground.state = .active
        self.foreground.wantsLayer = true
        self.foreground.layer?.backgroundColor = NSColor.clear.cgColor
        self.foreground.layer?.cornerRadius = Constants.Popup.radius
        self.foreground.layer?.masksToBounds = true
        
        self.background = NSView(frame: frame)
        self.background.wantsLayer = true
        self.foreground.addSubview(self.background)
        
        super.init(frame: frame)
        
        self.body.drawsBackground = false
        self.body.translatesAutoresizingMaskIntoConstraints = true
        self.body.borderType = .noBorder
        self.body.hasVerticalScroller = true
        self.body.hasHorizontalScroller = false
        self.body.autohidesScrollers = true
        self.body.horizontalScrollElasticity = .none
        self.body.scrollerStyle = .overlay
        self.body.verticalScroller?.controlSize = .small
        self.body.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: -4)
        
        self.addSubview(self.foreground, positioned: .below, relativeTo: .none)
        self.addSubview(self.header)
        self.addSubview(self.body)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        self.background.layer?.backgroundColor = self.isDarkMode
            ? .clear
            : Constants.Design.surfaceElevated.cgColor
    }
    
    fileprivate func setView(_ view: Popup_p?) {
        self.view = view
        self.header.setSubtitle(view?.subtitle)
        
        var size: NSSize = NSSize(
            width: (view?.frame.width ?? Constants.Popup.width) + (Constants.Popup.margins*2),
            height: (view?.frame.height ?? 0) + Constants.Popup.headerHeight + (Constants.Popup.margins*2)
        )
        
        self.windowHeight = NSScreen.main?.visibleFrame.height
        size.height = self.constrainedHeight(size.height)
        if let screenWidth = NSScreen.main?.visibleFrame.width, size.width > screenWidth {
            size.width = screenWidth
        }
        
        self.setFrameSize(size)
        self.foreground.setFrameSize(size)
        self.background.setFrameSize(size)
        self.body.setFrameSize(NSSize(
            width: size.width - (Constants.Popup.margins*2),
            height: size.height - Constants.Popup.headerHeight - (Constants.Popup.margins*2)
        ))
        self.header.setFrameOrigin(NSPoint(x: 0, y: size.height - Constants.Popup.headerHeight))
        
        if let view = view {
            self.body.documentView = view
            self.containerHeight = view.frame.height
            view.sizeCallback = { [weak self] size in
                self?.recalculateHeight(size)
            }
        }
    }
    
    fileprivate func setTitle(_ newTitle: String) {
        self.header.setTitle(newTitle)
    }
    
    fileprivate func setCloseButton(_ state: Bool) {
        self.header.setCloseButton(state)
    }
    
    internal func appear() {
        self.view?.appear()
        
        self.display()
        self.body.subviews.first?.display()
        
        if let screenHeight = NSScreen.main?.visibleFrame.height, let size = self.body.documentView?.frame.size {
            if screenHeight != self.windowHeight {
                self.recalculateHeight(size)
            }
        }
        
        if let documentView = self.body.documentView {
            documentView.scroll(NSPoint(x: 0, y: documentView.bounds.size.height))
        }
    }
    internal func disappear() {
        self.header.setCloseButton(false)
        self.view?.disappear()
    }
    
    private func recalculateHeight(_ size: NSSize) {
        NSLog("[SensorsDebug] container recalc: size=%@", NSStringFromSize(size))
        var windowSize: NSSize = NSSize(
            width: size.width + (Constants.Popup.margins*2),
            height: size.height + Constants.Popup.headerHeight + (Constants.Popup.margins*2)
        )
        let h0 = self.containerHeight ?? 0
        
        self.windowHeight = NSScreen.main?.visibleFrame.height
        self.containerHeight = self.body.documentView?.frame.height
        windowSize.height = self.constrainedHeight(windowSize.height)
        if let screenWidth = NSScreen.main?.visibleFrame.width, windowSize.width > screenWidth {
            windowSize.width = screenWidth
        }
        
        self.window?.setContentSize(windowSize)
        self.foreground.setFrameSize(windowSize)
        self.background.setFrameSize(windowSize)
        self.body.setFrameSize(NSSize(
            width: windowSize.width - (Constants.Popup.margins*2),
            height: windowSize.height - Constants.Popup.headerHeight - (Constants.Popup.margins*2)
        ))
        self.header.setFrameOrigin(NSPoint(
            x: self.header.frame.origin.x,
            y: self.body.frame.height + (Constants.Popup.margins*2)
        ))
        
        if let documentView = self.body.documentView {
            let diff = h0 - (self.body.documentView?.frame.height ?? 0)
            documentView.scroll(NSPoint(
                x: 0,
                y: self.body.documentVisibleRect.origin.y - (diff < 0 ? diff : 0)
            ))
        }
    }

    private func constrainedHeight(_ desiredHeight: CGFloat) -> CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? Constants.Popup.maximumHeight
        let screenLimit = visibleHeight - Constants.Design.space6
        return min(desiredHeight, min(Constants.Popup.maximumHeight, screenLimit))
    }
}

internal class HeaderView: NSStackView {
    private var titleView: NSTextField? = nil
    private var subtitleView: NSTextField? = nil
    private var activityButton: NSButton?
    
    private var title: String = ""
    private var isCloseAction: Bool = false
    private let activityMonitor: URL?
    private let calendar: URL?
    private var module: ModuleType
    
    private var titleCenterConstraint: NSLayoutConstraint? = nil
    private var titleLeadingConstraint: NSLayoutConstraint? = nil
    
    init(frame: NSRect, module: ModuleType) {
        self.module = module
        self.activityMonitor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
        self.calendar = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        
        super.init(frame: CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height))
        
        self.orientation = .horizontal
        self.distribution = .gravityAreas
        self.spacing = 0
        
        let activity = NSButtonWithPadding()
        activity.frame = CGRect(x: 0, y: 0, width: 24, height: self.frame.height)
        activity.horizontalPadding = activity.frame.height - 24
        activity.bezelStyle = .regularSquare
        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.imageScaling = .scaleNone
        activity.contentTintColor = .secondaryLabelColor
        activity.isBordered = false
        activity.target = self
        activity.focusRingType = .default
        self.activityButton = activity
        self.setupActionButton()
        
        let title = NSTextField(frame: NSRect(x: 0, y: 0, width: frame.width/2, height: 18))
        title.isEditable = false
        title.isSelectable = false
        title.isBezeled = false
        title.wantsLayer = true
        title.textColor = .labelColor
        title.backgroundColor = .clear
        title.canDrawSubviewsIntoLayer = true
        title.alignment = .center
        title.font = Constants.Design.sectionTitleFont
        title.stringValue = ""
        title.translatesAutoresizingMaskIntoConstraints = false
        self.titleView = title
        
        let subtitle = NSTextField(labelWithString: "")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = Constants.Design.captionRegularFont
        subtitle.textColor = .tertiaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.isHidden = true
        self.subtitleView = subtitle
        
        let titleContainer = NSView()
        titleContainer.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addSubview(title)
        titleContainer.addSubview(subtitle)
        
        self.titleCenterConstraint = title.centerXAnchor.constraint(equalTo: titleContainer.centerXAnchor)
        self.titleLeadingConstraint = title.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor)
        NSLayoutConstraint.activate([
            self.titleCenterConstraint!,
            title.centerYAnchor.constraint(equalTo: titleContainer.centerYAnchor),
            subtitle.centerYAnchor.constraint(equalTo: titleContainer.centerYAnchor),
            subtitle.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -Constants.Design.space2),
            subtitle.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: Constants.Design.space2)
        ])
        
        let settings = NSButtonWithPadding()
        settings.frame = CGRect(x: 0, y: 0, width: 24, height: self.frame.height)
        settings.horizontalPadding = activity.frame.height - 24
        settings.bezelStyle = .regularSquare
        settings.translatesAutoresizingMaskIntoConstraints = false
        settings.imageScaling = .scaleNone
        settings.image = iconFromSymbol(name: "gearshape", scale: .large)
        settings.contentTintColor = .secondaryLabelColor
        settings.isBordered = false
        settings.action = #selector(self.openSettings)
        settings.target = self
        settings.toolTip = localizedString("Open module settings")
        settings.focusRingType = .default
        settings.setAccessibilityLabel(settings.toolTip)
        
        self.addArrangedSubview(activity)
        self.addArrangedSubview(titleContainer)
        self.addArrangedSubview(settings)
        
        NSLayoutConstraint.activate([
            titleContainer.widthAnchor.constraint(
                equalToConstant: self.frame.width - activity.intrinsicContentSize.width - settings.intrinsicContentSize.width
            )
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate func setTitle(_ newTitle: String) {
        self.title = newTitle
        self.titleView?.stringValue = localizedString(newTitle)
        self.titleView?.setAccessibilityLabel(localizedString(newTitle))
    }
    
    fileprivate func setSubtitle(_ newValue: String?) {
        let value = newValue ?? ""
        self.subtitleView?.stringValue = value
        self.subtitleView?.isHidden = value.isEmpty
        self.titleCenterConstraint?.isActive = value.isEmpty
        self.titleLeadingConstraint?.isActive = !value.isEmpty
    }
    
    private func setupActionButton() {
        guard let button = self.activityButton else { return }
        
        if self.isCloseAction {
            button.action = #selector(self.closePopup)
            button.image = iconFromSymbol(name: "xmark.circle.fill", scale: .xlarge)
            button.toolTip = localizedString("Close")
            button.setAccessibilityLabel(button.toolTip)
            return
        }
        
        if self.module == .clock {
            button.action = #selector(self.openCalendar)
            button.image = iconFromSymbol(name: "calendar", scale: .large)
            button.toolTip = localizedString("Open Calendar")
            button.setAccessibilityLabel(button.toolTip)
            return
        } else if self.module == .remote {
            button.action = #selector(self.openSystemStats)
            button.image = iconFromSymbol(name: "globe", scale: .large)
            button.toolTip = localizedString("Open System Stats")
            button.setAccessibilityLabel(button.toolTip)
            return
        }
        
        button.action = #selector(self.openActivityMonitor)
        button.image = iconFromSymbol(name: "chart.bar.fill", scale: .medium)
        button.toolTip = localizedString("Open Activity Monitor")
        button.setAccessibilityLabel(button.toolTip)
    }
    
    @objc func openActivityMonitor() {
        guard let app = self.activityMonitor else { return }
        if let tab = self.module.activityMonitorTab {
            UserDefaults(suiteName: "com.apple.ActivityMonitor")?.set(tab, forKey: "SelectedTab")
        }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc func openCalendar() {
        guard let app = self.calendar else { return }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
    
    @objc func openSystemStats() {
        guard let url = URL(string: "https://app.system-stats.com") else { return }
        NSWorkspace.shared.open(url)
    }
    
    @objc func openSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": self.title])
    }
    
    @objc private func closePopup() {
        self.window?.setIsVisible(false)
        self.setCloseButton(false)
        return
    }
    
    fileprivate func setCloseButton(_ state: Bool) {
        guard state != self.isCloseAction else { return }
        self.isCloseAction = state
        self.setupActionButton()
    }
}

internal class PopupFooterView: NSView {
    private let activityMonitor: URL?
    private let calendar: URL?
    private let module: ModuleType

    init(width: CGFloat, module: ModuleType) {
        self.module = module
        self.activityMonitor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
        self.calendar = URL(fileURLWithPath: "/System/Applications/Calendar.app")

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 28))
        self.heightAnchor.constraint(equalToConstant: self.frame.height).isActive = true

        var label = localizedString("Open Activity Monitor")
        if module == .clock {
            label = localizedString("Open Calendar")
        } else if module == .remote {
            label = localizedString("Open System Stats")
        }

        let action = NSButton()
        action.isBordered = false
        action.attributedTitle = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor
        ])
        action.target = self
        action.action = #selector(self.openAction)
        action.toolTip = label
        action.setAccessibilityLabel(label)
        action.focusRingType = .default
        action.sizeToFit()
        action.frame = NSRect(x: Constants.Design.space3, y: 4, width: action.frame.width, height: 20)
        self.addSubview(action)

        let settings = NSButton()
        settings.isBordered = false
        settings.attributedTitle = NSAttributedString(
            string: "⌘, \(localizedString("Settings").lowercased())",
            attributes: [
                .font: Constants.Design.captionRegularFont,
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        settings.target = self
        settings.action = #selector(self.openSettings)
        settings.toolTip = localizedString("Open module settings")
        settings.setAccessibilityLabel(settings.toolTip)
        settings.focusRingType = .default
        settings.sizeToFit()
        settings.frame = NSRect(
            x: width - Constants.Design.space3 - settings.frame.width,
            y: 7,
            width: settings.frame.width,
            height: 14
        )
        self.addSubview(settings)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func openAction() {
        if self.module == .clock {
            guard let app = self.calendar else { return }
            NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return
        } else if self.module == .remote {
            guard let url = URL(string: "https://app.system-stats.com") else { return }
            NSWorkspace.shared.open(url)
            return
        }

        guard let app = self.activityMonitor else { return }
        if let tab = self.module.activityMonitorTab {
            UserDefaults(suiteName: "com.apple.ActivityMonitor")?.set(tab, forKey: "SelectedTab")
        }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": self.module.stringValue])
    }
}
