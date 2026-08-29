//
//  Settings.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 12/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

public extension NSToolbarItem.Identifier {
    static let toggleButton = NSToolbarItem.Identifier("toggleButton")
    static let previewButton = NSToolbarItem.Identifier("previewButton")
}

class SettingsWindow: NSWindow, NSWindowDelegate, NSToolbarDelegate {
    private static let size: CGSize = Constants.Design.settingsDefaultSize
    private static let frameAutosaveName = "eu.exelban.Stats.Settings.WindowFrame"
    
    internal var onClose: (() -> Void)?
    
    private let mainView = MainView(frame: NSRect(
        x: 0,
        y: 0,
        width: SettingsWindow.size.width - Constants.Design.sidebarWidth,
        height: SettingsWindow.size.height
    ))
    private let sidebarView = SidebarView(frame: NSRect(
        x: 0,
        y: 0,
        width: Constants.Design.sidebarWidth,
        height: SettingsWindow.size.height
    ))
    private let sidebarViewController = NSSplitViewController()
    
    private let dashboard = Dashboard()
    private var settings: ApplicationSettings = ApplicationSettings()
    
    private var toggleButton: NSControl? = nil
    private var activeModuleName: String? = nil
    private var settingsPreviewButton: NSView? = nil
    
    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsWindow.size.width,
                height: SettingsWindow.size.height
            ),
            styleMask: [.closable, .titled, .miniaturizable, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        
        let sidebarVC: NSViewController = NSViewController(nibName: nil, bundle: nil)
        sidebarVC.view = self.sidebarView
        let mainVC: NSViewController = NSViewController(nibName: nil, bundle: nil)
        mainVC.view = self.mainView
        
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        let contentItem = NSSplitViewItem(viewController: mainVC)
        
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = Constants.Design.sidebarMinimumWidth
        sidebarItem.maximumThickness = Constants.Design.sidebarMaximumWidth
        contentItem.canCollapse = false
        
        self.sidebarViewController.addSplitViewItem(sidebarItem)
        self.sidebarViewController.addSplitViewItem(contentItem)
        
        contentItem.minimumThickness = Constants.Design.contentMinimumWidth
        
        let newToolbar = NSToolbar(identifier: "eu.exelban.Stats.Settings.Toolbar")
        newToolbar.allowsUserCustomization = false
        newToolbar.autosavesConfiguration = true
        newToolbar.displayMode = .default
        newToolbar.showsBaselineSeparator = true
        newToolbar.delegate = self
        
        self.toolbar = newToolbar
        self.contentViewController = self.sidebarViewController
        self.titlebarAppearsTransparent = true
        if #unavailable(macOS 26.0) {
            self.backgroundColor = .clear
        }
        self.isRestorable = true
        self.isReleasedWhenClosed = false
        self.delegate = self
        self.setFrameAutosaveName(SettingsWindow.frameAutosaveName)
        if !self.setFrameUsingName(SettingsWindow.frameAutosaveName) {
            self.positionCenter()
        }
        self.setIsVisible(false)
        self.minSize = Constants.Design.settingsMinimumSize
        if self.frame.width < self.minSize.width || self.frame.height < self.minSize.height {
            var frame = self.frame
            frame.size.width = max(frame.width, self.minSize.width)
            frame.size.height = max(frame.height, self.minSize.height)
            self.setFrame(frame, display: false)
        }
        self.dashboard.adapt(to: self.frame.width)
        
        let windowController = NSWindowController()
        windowController.window = self
        windowController.loadWindow()
        
        NotificationCenter.default.addObserver(self, selector: #selector(menuCallback), name: .openModuleSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(externalModuleToggle), name: .toggleModule, object: nil)
        
        self.sidebarView.setModules(modules)
        let storedDestination = ProcessInfo.processInfo.environment["STATS_SETTINGS_DESTINATION"]
            ?? Store.shared.string(key: "settings_selected_destination", defaultValue: "Dashboard")
        let knownDestination = storedDestination == "Dashboard" || storedDestination == "Settings" || modules.contains(where: { $0.config.name == storedDestination })
        self.sidebarView.openMenu(knownDestination ? storedDestination : "Dashboard")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .openModuleSettings, object: nil)
        NotificationCenter.default.removeObserver(self, name: .toggleModule, object: nil)
    }
    
    func windowWillClose(_ notification: Notification) {
        let onClose = self.onClose
        DispatchQueue.main.async {
            onClose?()
        }
    }

    func windowDidResize(_ notification: Notification) {
        self.dashboard.adapt(to: self.frame.width)
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == NSEvent.EventType.keyDown && event.modifierFlags.contains(.command) {
            if event.keyCode == 12 || event.keyCode == 13 {
                self.close()
                return true
            } else if event.keyCode == 46 {
                self.miniaturize(event)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func mouseUp(with: NSEvent) {
        NotificationCenter.default.post(name: .clickInSettings, object: nil, userInfo: nil)
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .previewButton:
            let button = SettingsPreviewButton { [weak self] in
                guard let moduleName = self?.activeModuleName else { return }
                NotificationCenter.default.post(name: .togglePreview, object: nil, userInfo: ["module": moduleName])
            }
            self.settingsPreviewButton = button
            
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.view = button
            toolbarItem.isBordered = false
            
            return toolbarItem
        case .toggleButton:
            let switchButton = NSSwitch()
            switchButton.state = .on
            switchButton.action = #selector(self.toggleEnable)
            switchButton.target = self
            switchButton.controlSize = .small
            self.toggleButton = switchButton
            
            let toolbarItem = NSToolbarItem(itemIdentifier: itemIdentifier)
            toolbarItem.toolTip = localizedString("Toggle the module")
            toolbarItem.view = switchButton
            toolbarItem.isBordered = false
            
            return toolbarItem
        default:
            return nil
        }
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .flexibleSpace, .previewButton, .toggleButton]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .flexibleSpace, .previewButton, .toggleButton]
    }
    
    internal func open(module: String? = nil) {
        if !self.isVisible {
            self.setIsVisible(true)
            self.makeKeyAndOrderFront(nil)
        }
        if !self.isKeyWindow {
            self.orderFrontRegardless()
        }
        
        if var name = module {
            if name == "Combined modules" { name = "Dashboard" }
            self.sidebarView.openMenu(name)
        }
    }
    
    @objc private func menuCallback(_ notification: Notification) {
        if let title = notification.userInfo?["module"] as? String {
            var view: NSView = NSView()
            if let detectedModule = modules.first(where: { $0.config.name == title }) {
                if let v = detectedModule.window {
                    view = v
                }
                self.activeModuleName = detectedModule.config.name
                toggleNSControlState(self.toggleButton, state: detectedModule.enabled ? .on : .off)
                self.toggleButton?.isHidden = false
                self.settingsPreviewButton?.isHidden = !detectedModule.config.hasPreview
                NotificationCenter.default.post(name: .openWindow, object: nil, userInfo: ["module": detectedModule.config.name, "state": true])
            } else if title == "Dashboard" {
                view = self.dashboard
                self.toggleButton?.isHidden = true
                self.settingsPreviewButton?.isHidden = true
                NotificationCenter.default.post(name: .openWindow, object: nil, userInfo: ["state": false])
            } else if title == "Settings" {
                self.settings.viewWillAppear()
                view = self.settings
                self.toggleButton?.isHidden = true
                self.settingsPreviewButton?.isHidden = true
                NotificationCenter.default.post(name: .openWindow, object: nil, userInfo: ["state": false])
            }
            
            self.title = localizedString(title)
            if ProcessInfo.processInfo.environment["STATS_SETTINGS_DESTINATION"] == nil {
                Store.shared.set(key: "settings_selected_destination", value: title)
            }
            
            self.mainView.setView(view)
            self.sidebarView.openMenu(title)
        }
    }
    
    @objc private func toggleEnable(_ sender: NSControl) {
        guard let moduleName = self.activeModuleName else { return }
        NotificationCenter.default.post(name: .toggleModule, object: nil, userInfo: ["module": moduleName, "state": controlState(sender)])
    }
    
    @objc private func externalModuleToggle(_ notification: Notification) {
        if let name = notification.userInfo?["module"] as? String, name == self.activeModuleName {
            if let state = notification.userInfo?["state"] as? Bool {
                toggleNSControlState(self.toggleButton, state: state ? .on : .off)
            }
        }
    }
    
    private func positionCenter() {
        guard let screen = NSScreen.main else {
            self.center()
            return
        }
        self.setFrameOrigin(NSPoint(
            x: (screen.frame.width - SettingsWindow.size.width)/2,
            y: ((screen.frame.height - SettingsWindow.size.height)/1.75)
        ))
    }
}

// MARK: - MainView

private class MainView: NSView {
    fileprivate let container: NSStackView = NSStackView()
    
    private let background: NSVisualEffectView = {
        let view = NSVisualEffectView(frame: NSRect.zero)
        view.blendingMode = .withinWindow
        view.material = .contentBackground
        view.state = .active
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }()
    
    override init(frame: NSRect) {
        super.init(frame: NSRect.zero)
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.container.translatesAutoresizingMaskIntoConstraints = false
        
        self.addSubview(self.background, positioned: .below, relativeTo: .none)
        self.addSubview(self.container)
        
        NSLayoutConstraint.activate([
            self.background.leadingAnchor.constraint(equalTo: leadingAnchor),
            self.background.trailingAnchor.constraint(equalTo: trailingAnchor),
            self.background.topAnchor.constraint(equalTo: topAnchor),
            self.background.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            self.container.leadingAnchor.constraint(equalTo: leadingAnchor),
            self.container.trailingAnchor.constraint(equalTo: trailingAnchor),
            self.container.topAnchor.constraint(equalTo: topAnchor, constant: Constants.Popup.headerHeight*1.4),
            self.container.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate func setView(_ view: NSView) {
        self.container.subviews.forEach{ $0.removeFromSuperview() }
        self.container.addArrangedSubview(view)
        
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: self.container.leftAnchor),
            view.rightAnchor.constraint(equalTo: self.container.rightAnchor),
            view.topAnchor.constraint(equalTo: self.container.topAnchor),
            view.bottomAnchor.constraint(equalTo: self.container.bottomAnchor)
        ])
    }
}

// MARK: - Sidebar

private class SidebarView: NSStackView {
    private let scrollView: ScrollableStackView
    
    private let supportPopover = NSPopover()
    private let moreMenu = NSMenu()
    private var pauseButton: NSButton? = nil
    
    private var pauseState: Bool {
        get { Store.shared.bool(key: "pause", defaultValue: false) }
        set { Store.shared.set(key: "pause", value: newValue) }
    }
    
    private var dashboardIcon: NSImage { NSImage(systemSymbolName: "circle.grid.3x3.fill", accessibilityDescription: localizedString("Dashboard"))! }
    private var settingsIcon: NSImage { iconFromSymbol(name: "gear", scale: .large) }
    private var pauseIcon: NSImage { iconFromSymbol(name: "pause.fill", scale: .large) }
    private var resumeIcon: NSImage { iconFromSymbol(name: "play.fill", scale: .large) }
    private var moreIcon: NSImage { iconFromSymbol(name: "ellipsis.circle", scale: .large) }
    
    override init(frame: NSRect) {
        self.scrollView = ScrollableStackView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        self.scrollView.stackView.spacing = 0
        self.scrollView.stackView.alignment = .width
        self.scrollView.stackView.edgeInsets = NSEdgeInsets(
            top: 0,
            left: Constants.Design.space2,
            bottom: 0,
            right: Constants.Design.space2
        )
        
        super.init(frame: frame)
        self.orientation = .vertical
        self.alignment = .width
        self.spacing = 0
        self.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.Design.sidebarMinimumWidth).isActive = true
        self.widthAnchor.constraint(lessThanOrEqualToConstant: Constants.Design.sidebarMaximumWidth).isActive = true
        
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: Constants.Design.space3).isActive = true
        
        self.addMenuItem(MenuItem(icon: self.dashboardIcon, title: "Dashboard"))
        self.addMenuItem(MenuItem(icon: self.settingsIcon, title: "Settings"))
        self.scrollView.stackView.addArrangedSubview(spacer)
        
        self.supportPopover.behavior = .transient
        self.supportPopover.contentViewController = self.supportView()
        
        let footerHeight = Constants.Design.space6 * 2
        let additionalButtons: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: frame.width, height: footerHeight))
        additionalButtons.heightAnchor.constraint(equalToConstant: footerHeight).isActive = true
        additionalButtons.orientation = .horizontal
        additionalButtons.distribution = .fillEqually
        additionalButtons.alignment = .centerY
        additionalButtons.spacing = 0
        additionalButtons.setContentHuggingPriority(.required, for: .vertical)
        additionalButtons.setContentCompressionResistancePriority(.required, for: .vertical)
        self.scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        self.scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let pauseButton = self.makeActionButton(
            title: localizedString(self.pauseState ? "Resume" : "Pause"),
            toolTip: localizedString(self.pauseState ? "Resume the Stats" : "Pause the Stats"),
            image: self.pauseState ? self.resumeIcon : self.pauseIcon,
            action: #selector(togglePause)
        )
        self.pauseButton = pauseButton

        let support = NSMenuItem(title: localizedString("Support upstream Stats"), action: #selector(donateFromMenu), keyEquivalent: "")
        support.target = self
        let report = NSMenuItem(title: localizedString("Report a bug"), action: #selector(reportBug), keyEquivalent: "")
        report.target = self
        let quit = NSMenuItem(title: localizedString("Quit Stats Custom"), action: #selector(closeApp), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        self.moreMenu.addItem(support)
        self.moreMenu.addItem(report)
        self.moreMenu.addItem(.separator())
        self.moreMenu.addItem(quit)
        
        additionalButtons.addArrangedSubview(pauseButton)
        additionalButtons.addArrangedSubview(self.makeActionButton(
            title: localizedString("More"),
            toolTip: localizedString("More actions"),
            image: self.moreIcon,
            action: #selector(showMore)
        ))
        
        self.addArrangedSubview(self.scrollView)
        self.addArrangedSubview(additionalButtons)
        NSLayoutConstraint.activate([
            self.scrollView.widthAnchor.constraint(equalTo: self.widthAnchor),
            additionalButtons.widthAnchor.constraint(equalTo: self.widthAnchor)
        ])
        
        NotificationCenter.default.addObserver(self, selector: #selector(listenForPause), name: .pause, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .pause, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate func openMenu(_ title: String) {
        self.scrollView.stackView.subviews.forEach({ (m: NSView) in
            if let menu = m as? MenuItem {
                if menu.destination == title {
                    menu.activate()
                    menu.scrollToVisible(menu.bounds)
                } else {
                    menu.reset()
                }
            }
        })
    }
    
    fileprivate func setModules(_ list: [Module]) {
        list.reversed().forEach { (m: Module) in
            if !m.available { return }
            self.addMenuItem(MenuItem(icon: m.config.icon, title: m.config.name), at: 3)
        }
    }

    private func addMenuItem(_ menu: MenuItem, at index: Int? = nil) {
        if let index {
            self.scrollView.stackView.insertArrangedSubview(menu, at: index)
        } else {
            self.scrollView.stackView.addArrangedSubview(menu)
        }
        menu.widthAnchor.constraint(
            equalTo: self.scrollView.stackView.widthAnchor,
            constant: -Constants.Design.space4
        ).isActive = true
    }
    
    private func makeActionButton(title: String, toolTip: String, image: NSImage, action: Selector) -> NSButton {
        let button = NSButtonWithPadding()
        button.title = title
        button.toolTip = toolTip
        button.bezelStyle = .regularSquare
        button.translatesAutoresizingMaskIntoConstraints = false
        button.imageScaling = .scaleNone
        button.image = image
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        button.horizontalPadding = Constants.Design.space2
        button.contentTintColor = .secondaryLabelColor
        button.isBordered = false
        button.action = action
        button.target = self
        button.focusRingType = .default
        button.setAccessibilityLabel(toolTip)
        button.heightAnchor.constraint(equalToConstant: Constants.Design.minimumControlSize).isActive = true
        
        return button
    }
    
    private func supportView() -> NSViewController {
        let vc: NSViewController = NSViewController(nibName: nil, bundle: nil)
        let view: NSStackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 220, height: 54))
        view.spacing = 10
        view.edgeInsets = NSEdgeInsets(top: 0, left: 15, bottom: 0, right: 0)
        view.orientation = .horizontal
        
        let systemStats = SupportButtonView(name: "System Stats", image: "AppIcon", action: {
            NSWorkspace.shared.open(URL(string: "https://www.system-stats.com")!)
        })
        let github = SupportButtonView(name: "GitHub Sponsors", image: "github", action: {
            NSWorkspace.shared.open(URL(string: "https://github.com/sponsors/exelban")!)
        })
        let paypal = SupportButtonView(name: "PayPal", image: "paypal", action: {
            NSWorkspace.shared.open(URL(string: "https://www.paypal.com/donate?hosted_button_id=3DS5JHDBATMTC")!)
        })
        let koFi = SupportButtonView(name: "Ko-fi", image: "ko-fi", action: {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/exelban")!)
        })
        let patreon = SupportButtonView(name: "Patreon", image: "patreon", action: {
            NSWorkspace.shared.open(URL(string: "https://patreon.com/exelban")!)
        })
        
        view.addArrangedSubview(systemStats)
        view.addArrangedSubview(github)
        view.addArrangedSubview(paypal)
        view.addArrangedSubview(koFi)
        view.addArrangedSubview(patreon)
        
        vc.view = view
        return vc
    }
    
    @objc private func reportBug() {
        NSWorkspace.shared.open(StatsLinks.newIssue)
    }
    
    @objc private func donateFromMenu() {
        guard let view = self.pauseButton?.superview else { return }
        self.supportPopover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
    
    @objc private func closeApp(_ sender: Any) {
        NSApp.terminate(sender)
    }

    @objc private func showMore(_ sender: NSButton) {
        self.moreMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
    }
    
    @objc private func togglePause() {
        self.pauseState = !self.pauseState
        self.pauseButton?.title = localizedString(self.pauseState ? "Resume" : "Pause")
        self.pauseButton?.toolTip = localizedString(self.pauseState ? "Resume the Stats" : "Pause the Stats")
        self.pauseButton?.setAccessibilityLabel(localizedString(self.pauseState ? "Resume the Stats" : "Pause the Stats"))
        self.pauseButton?.image = self.pauseState ? self.resumeIcon : self.pauseIcon
        NotificationCenter.default.post(name: .pause, object: nil, userInfo: ["state": self.pauseState])
    }
    
    @objc func listenForPause() {
        self.pauseButton?.title = localizedString(self.pauseState ? "Resume" : "Pause")
        self.pauseButton?.toolTip = localizedString(self.pauseState ? "Resume the Stats" : "Pause the Stats")
        self.pauseButton?.setAccessibilityLabel(localizedString(self.pauseState ? "Resume the Stats" : "Pause the Stats"))
        self.pauseButton?.image = self.pauseState ? self.resumeIcon : self.pauseIcon
    }
}

private class MenuItem: NSButtonWithPadding {
    fileprivate let destination: String
    
    private var active: Bool = false
    
    init(icon: NSImage?, title: String) {
        self.destination = title
        
        super.init(frame: NSRect.zero)
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.cornerRadius = Constants.Design.space2
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.image = icon
        self.imagePosition = .imageLeading
        self.imageHugsTitle = true
        self.imageScaling = .scaleProportionallyDown
        self.alignment = .left
        self.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        self.horizontalPadding = Constants.Design.space4
        self.target = self
        self.action = #selector(selectDestination)
        self.focusRingType = .default
        self.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        if title == "Settings" {
            self.toolTip = localizedString("Open application settings")
        } else if title == "Dashboard" {
            self.toolTip = localizedString("Open dashboard")
        } else {
            self.toolTip = localizedString("Open \(title) settings")
        }
        self.setAccessibilityLabel(localizedString(title))
        self.updateAppearance()
        
        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: Constants.Design.navigationRowHeight)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func selectDestination() {
        self.activate()
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 125 || event.keyCode == 126,
              let stack = self.superview as? NSStackView else {
            super.keyDown(with: event)
            return
        }
        let items = stack.arrangedSubviews.compactMap { $0 as? MenuItem }
        guard let index = items.firstIndex(of: self) else { return }
        let offset = event.keyCode == 125 ? 1 : -1
        let destinationIndex = min(max(index + offset, 0), items.count - 1)
        let item = items[destinationIndex]
        self.window?.makeFirstResponder(item)
        item.activate()
    }
    
    fileprivate func activate() {
        guard !self.active else { return }
        self.active = true
        
        NotificationCenter.default.post(name: .openModuleSettings, object: nil, userInfo: ["module": self.destination])
        self.updateAppearance()
    }
    
    fileprivate func reset() {
        self.active = false
        self.updateAppearance()
    }

    private func updateAppearance() {
        let color: NSColor = self.active ? .alternateSelectedControlTextColor : .labelColor
        self.layer?.backgroundColor = self.active ? NSColor.selectedContentBackgroundColor.cgColor : NSColor.clear.cgColor
        self.contentTintColor = color
        self.attributedTitle = NSAttributedString(
            string: localizedString(self.destination),
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: self.active ? .medium : .regular),
                .foregroundColor: color
            ]
        )
    }
}

private class SettingsPreviewButton: NSStackView {
    private var callback: () -> Void
    
    private var settingsIcon: NSImage { iconFromSymbol(name: "gear", scale: .large) }
    private var previewIcon: NSImage { iconFromSymbol(name: "command", scale: .large) }
    
    private var button: NSButton? = nil
    private var isSettingsEnabled: Bool = false
    
    fileprivate init(callback: @escaping () -> Void) {
        self.callback = callback
        
        super.init(frame: .zero)
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.edgeInsets = NSEdgeInsets(
            top: Constants.Settings.margin,
            left: Constants.Settings.margin,
            bottom: Constants.Settings.margin,
            right: Constants.Settings.margin
        )
        self.spacing = Constants.Settings.margin
        
        let button = NSButton()
        button.toolTip = localizedString("Open module settings")
        button.bezelStyle = .regularSquare
        button.translatesAutoresizingMaskIntoConstraints = false
        button.imageScaling = .scaleNone
        button.image = self.settingsIcon
        button.contentTintColor = .secondaryLabelColor
        button.isBordered = false
        button.action = #selector(self.action)
        button.target = self
        button.focusRingType = .default
        button.widthAnchor.constraint(equalToConstant: Constants.Widget.height).isActive = true
        self.button = button
        
        self.addArrangedSubview(button)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func action() {
        guard let button = self.button else { return }
        self.callback()
        
        self.isSettingsEnabled = !self.isSettingsEnabled
        
        if self.isSettingsEnabled {
            button.image = self.previewIcon
            button.toolTip = localizedString("Close module settings")
        } else {
            button.image = self.settingsIcon
            button.toolTip = localizedString("Open module settings")
        }
    }
}
