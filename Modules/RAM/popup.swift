//
//  popup.swift
//  Memory
//
//  Created by Serhiy Mytrovtsiy on 18/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private let heroHeight: CGFloat = 64

    private let trendChartHeight: CGFloat = 70
    private let trendMetaHeight: CGFloat = 12
    private let trendMetaGap: CGFloat = 5
    private var trendHeight: CGFloat {
        self.sectionHeaderHeight + self.trendChartHeight + self.trendMetaGap + self.trendMetaHeight + self.sectionBottomPadding
    }

    private let barHeight: CGFloat = 16
    private var detailsHeight: CGFloat {
        self.sectionHeaderHeight
            + (Constants.Popup.processHeight * 5) // used, app, wired, compressed, free
            + self.barHeight
            + (Constants.Design.hairlineWidth * 5)
            + self.sectionBottomPadding
    }
    private var processesHeight: CGFloat {
        let n = self.numberOfProcesses
        if n == 0 { return 0 }
        return self.sectionHeaderHeight
            + (Constants.Popup.processHeight * CGFloat(n))
            + self.sectionBottomPadding
    }

    private var usageField: NSTextField? = nil
    private var peakField: NSTextField? = nil
    private var historyWindowField: NSTextField? = nil

    private var pressureChipView: NSView? = nil
    private var pressureChipField: NSTextField? = nil
    private var swapChipView: NSView? = nil
    private var swapChipField: NSTextField? = nil

    private var usedField: NSTextField? = nil
    private var freeField: NSTextField? = nil

    private var appField: NSTextField? = nil
    private var wiredField: NSTextField? = nil
    private var compressedField: NSTextField? = nil

    private var appColorView: NSView? = nil
    private var wiredColorView: NSView? = nil
    private var compressedColorView: NSView? = nil
    private var freeColorView: NSView? = nil
    private var sliderView: NSView? = nil

    private var chart: LineChartView? = nil
    private var bar: BarChartView = BarChartView(size: 10, horizontal: true)
    private var processesInitialized: Bool = false

    private let loadCache = PopupCache<RAM_Usage>()

    private var processes: ProcessesView? = nil
    private var processesView: NSView? = nil
    private var footer: NSView? = nil

    private var peakUsage: Double = 0
    private var lineChartHistory: Int = 180
    private var lineChartScale: Scale = .none
    private var lineChartFixedScale: Double = 1
    private var chartPrefSection: PreferencesSection? = nil

    private var numberOfProcesses: Int {
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
    }

    private var appColorState: SColor = .secondBlue
    private var appColor: NSColor { self.appColorState.additional as? NSColor ?? NSColor.systemRed }
    private var wiredColorState: SColor = .secondOrange
    private var wiredColor: NSColor { self.wiredColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var compressedColorState: SColor = .pink
    private var compressedColor: NSColor { self.compressedColorState.additional as? NSColor ?? NSColor.lightGray }
    private var freeColorState: SColor = .lightGray
    private var freeColor: NSColor { self.freeColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var chartColorState: SColor = .systemAccent
    private var chartColor: NSColor { self.chartColorState.additional as? NSColor ?? NSColor.systemBlue }

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.spacing = Constants.Design.space2
        self.orientation = .vertical

        self.appColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_appColor", defaultValue: self.appColorState.key))
        self.wiredColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_wiredColor", defaultValue: self.wiredColorState.key))
        self.compressedColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_compressedColor", defaultValue: self.compressedColorState.key))
        self.freeColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_freeColor", defaultValue: self.freeColorState.key))
        self.chartColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_chartColor", defaultValue: self.chartColorState.key))
        self.lineChartHistory = Store.shared.int(key: "\(self.title)_lineChartHistory", defaultValue: self.lineChartHistory)
        self.lineChartScale = Scale.fromString(Store.shared.string(key: "\(self.title)_lineChartScale", defaultValue: self.lineChartScale.key))
        self.lineChartFixedScale = Double(Store.shared.int(key: "\(self.title)_lineChartFixedScale", defaultValue: 100)) / 100

        var subtitleParts: [String] = [Units(bytes: Int64(ProcessInfo.processInfo.physicalMemory)).getReadableMemory(style: .memory)]
        if let dimms = SystemKit.shared.device.info.ram?.dimms {
            let types = Set(dimms.compactMap({ $0.type }).filter({ !$0.isEmpty }))
            if types.count == 1, let type = types.first {
                subtitleParts.append(type)
            }
        }
        self.subtitle = subtitleParts.joined(separator: " · ")

        self.addArrangedSubview(self.initHero())
        self.addArrangedSubview(self.initTrend())
        self.addArrangedSubview(self.initDetails())
        self.addArrangedSubview(self.initProcesses())
        self.footer = self.footerView()
        self.addArrangedSubview(self.footer!)

        self.applySemanticColors()
        self.recalculateHeight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func updateLayer() {
        self.applySemanticColors()
        self.chart?.display()
    }

    public override func appear() {
        self.replay(self.loadCache, render: self.renderLoad)
    }

    public override func disappear() {
        self.processes?.setLock(false)
    }

    private func recalculateHeight() {
        var h: CGFloat = self.spacing * CGFloat(max(self.arrangedSubviews.count - 1, 0))
        self.arrangedSubviews.forEach { v in
            if let v = v as? NSStackView {
                h += v.arrangedSubviews.map({ $0.bounds.height + v.spacing }).reduce(0, +)
            } else {
                h += v.bounds.height
            }
        }
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }

    // MARK: - sections

    private func initHero() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.heroHeight))
        view.heightAnchor.constraint(equalToConstant: self.heroHeight).isActive = true

        let big = NSTextField(labelWithAttributedString: self.usageString(0))
        big.frame = NSRect(x: self.heroSidePadding, y: 18, width: 200, height: 40)
        big.setAccessibilityLabel(localizedString("Memory usage"))
        self.usageField = big
        view.addSubview(big)

        let caption = NSTextField(labelWithString: localizedString("Memory usage"))
        caption.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: self.heroSidePadding + 1, y: 4, width: 200, height: 13)
        view.addSubview(caption)

        let chips = NSStackView()
        chips.orientation = .vertical
        chips.alignment = .trailing
        chips.spacing = 5
        chips.frame = NSRect(x: self.frame.width - self.heroSidePadding - 160, y: 6, width: 160, height: 41)

        let pressureChip = self.makeChip()
        self.pressureChipView = pressureChip.0
        self.pressureChipField = pressureChip.1
        let swapChip = self.makeChip()
        self.swapChipView = swapChip.0
        self.swapChipField = swapChip.1

        chips.addArrangedSubview(pressureChip.0)
        chips.addArrangedSubview(swapChip.0)
        view.addSubview(chips)

        return view
    }

    private func usageString(_ percentage: Int) -> NSAttributedString {
        let value = NSMutableAttributedString(string: "\(percentage)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ])
        value.append(NSAttributedString(string: "%", attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        return value
    }

    private func chipString(_ value: String, suffix: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])
        text.append(NSAttributedString(string: " \(suffix)", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]))
        return text
    }

    private func initTrend() -> NSView {
        let view = self.sectionView(localizedString("Usage history"), height: self.trendHeight)

        let chart = LineChartView(
            frame: NSRect(
                x: 8,
                y: self.sectionBottomPadding + self.trendMetaHeight + self.trendMetaGap,
                width: self.frame.width - 16,
                height: self.trendChartHeight
            ),
            num: self.lineChartHistory,
            scale: self.lineChartScale,
            fixedScale: self.lineChartFixedScale
        )
        chart.setColor(self.chartColor)
        chart.setGradedFill(true)
        self.chart = chart
        view.addSubview(chart)

        let windowField = NSTextField(labelWithString: self.historyWindowString())
        windowField.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        windowField.textColor = .tertiaryLabelColor
        windowField.frame = NSRect(
            x: self.sectionSidePadding,
            y: self.sectionBottomPadding,
            width: 140,
            height: self.trendMetaHeight
        )
        self.historyWindowField = windowField
        view.addSubview(windowField)

        let peakField = NSTextField(labelWithString: "")
        peakField.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        peakField.textColor = .tertiaryLabelColor
        peakField.alignment = .right
        peakField.frame = NSRect(
            x: self.frame.width - self.sectionSidePadding - 140,
            y: self.sectionBottomPadding,
            width: 140,
            height: self.trendMetaHeight
        )
        self.peakField = peakField
        view.addSubview(peakField)

        return view
    }

    private func historyWindowString() -> String {
        if self.lineChartHistory >= 60 && self.lineChartHistory % 60 == 0 {
            return "\(localizedString("Last")) \(self.lineChartHistory/60) min"
        }
        return "\(localizedString("Last")) \(self.lineChartHistory) s"
    }

    private func initDetails() -> NSView {
        let view = self.sectionView(localizedString("Details"), height: self.detailsHeight)
        let innerWidth = self.frame.width - self.sectionSidePadding*2
        let container = NSStackView(frame: NSRect(
            x: self.sectionSidePadding,
            y: self.sectionBottomPadding,
            width: innerWidth,
            height: self.detailsHeight - self.sectionHeaderHeight - self.sectionBottomPadding
        ))
        container.orientation = .vertical
        container.spacing = 0

        var rowCount = 0
        func nextRow() {
            if rowCount > 0 {
                self.addDetailSeparator(container, width: innerWidth)
            }
            rowCount += 1
        }

        nextRow()
        self.usedField = popupRow(container, title: "\(localizedString("Used")):", value: "").1
        nextRow()
        self.bar.heightAnchor.constraint(equalToConstant: self.barHeight).isActive = true
        container.addArrangedSubview(self.bar)
        nextRow()
        (self.appColorView, _, self.appField) = popupWithColorRow(container, color: self.appColor, title: "\(localizedString("App")):", value: "")
        nextRow()
        (self.wiredColorView, _, self.wiredField) = popupWithColorRow(container, color: self.wiredColor, title: "\(localizedString("Wired")):", value: "")
        nextRow()
        (self.compressedColorView, _, self.compressedField) = popupWithColorRow(container, color: self.compressedColor, title: "\(localizedString("Compressed")):", value: "")
        nextRow()
        (self.freeColorView, _, self.freeField) = popupWithColorRow(container, color: self.freeColor.withAlphaComponent(0.5), title: "\(localizedString("Free")):", value: "")

        [self.appColorView, self.wiredColorView, self.compressedColorView, self.freeColorView].forEach {
            $0?.layer?.cornerRadius = 5
        }

        view.addSubview(container)

        return view
    }

    private func initProcesses() -> NSView {
        if self.numberOfProcesses == 0 {
            let v = NSView()
            self.processesView = v
            return v
        }

        let view = self.sectionView(localizedString("Top processes"), height: self.processesHeight)
        let container: ProcessesView = ProcessesView(
            frame: NSRect(
                x: 6,
                y: self.sectionBottomPadding,
                width: self.frame.width - 12,
                height: self.processesHeight - self.sectionHeaderHeight - self.sectionBottomPadding
            ),
            values: [(localizedString("Usage"), nil)],
            n: self.numberOfProcesses,
            header: false,
            shareBars: true
        )
        self.processes = container

        view.addSubview(container)

        self.processesView = view
        return view
    }

    // MARK: - callbacks

    public func loadCallback(_ value: RAM_Usage) {
        self.apply(value, to: self.loadCache, render: self.renderLoad)
        self.chart?.addValue(value.usage)
    }

    private func renderLoad(_ value: RAM_Usage) {
        let percentage = Int(value.usage.rounded(toPlaces: 2) * 100)
        self.usageField?.attributedStringValue = self.usageString(percentage)
        self.usageField?.setAccessibilityLabel("\(localizedString("Memory usage")): \(percentage)%")

        if value.usage > self.peakUsage {
            self.peakUsage = value.usage
        }
        self.peakField?.stringValue = "\(localizedString("Peak")) \(Int(self.peakUsage * 100))%"

        self.pressureChipView?.isHidden = false
        self.pressureChipField?.attributedStringValue = self.chipString(localizedString(value.pressure.value.rawValue.capitalized), suffix: localizedString("pressure"))
        self.pressureChipView?.toolTip = "\(localizedString("Memory pressure")): \(value.pressure.value.rawValue)"

        let swap = Units(bytes: Int64(value.swap.used)).getReadableMemory(style: .memory)
        self.swapChipView?.isHidden = false
        self.swapChipField?.attributedStringValue = self.chipString(swap, suffix: localizedString("swap"))
        self.swapChipView?.toolTip = "\(localizedString("Swap")): \(swap)"

        self.usedField?.stringValue = Units(bytes: Int64(value.used)).getReadableMemory(style: .memory)
        self.appField?.stringValue = Units(bytes: Int64(value.app)).getReadableMemory(style: .memory)
        self.wiredField?.stringValue = Units(bytes: Int64(value.wired)).getReadableMemory(style: .memory)
        self.compressedField?.stringValue = Units(bytes: Int64(value.compressed)).getReadableMemory(style: .memory)
        self.freeField?.stringValue = Units(bytes: Int64(value.free)).getReadableMemory(style: .memory)

        let total: Double = value.total == 0 ? 1 : value.total
        self.bar.setValues([
            ColorValue(value.app/total, color: self.appColor),
            ColorValue(value.wired/total, color: self.wiredColor),
            ColorValue(value.compressed/total, color: self.compressedColor)
        ])

        self.chart?.display()
    }

    public func processCallback(_ list: [TopProcess]) {
        DispatchQueue.main.async(execute: {
            if !(self.window?.isVisible ?? false) && self.processesInitialized {
                return
            }
            let list = list.map { $0 }
            if list.count != self.processes?.count { self.processes?.clear() }

            let maxUsage = list.map({ $0.usage }).max() ?? 0
            for i in 0..<list.count {
                let process = list[i]
                let share = maxUsage > 0 ? process.usage / maxUsage : 0
                self.processes?.set(i, process, [Units(bytes: Int64(process.usage)).getReadableMemory(style: .memory)], share: share)
            }

            self.processesInitialized = true
        })
    }

    public func numberOfProcessesUpdated() {
        if self.processes?.count == self.numberOfProcesses { return }

        DispatchQueue.main.async(execute: {
            self.footer?.removeFromSuperview()
            self.processesView?.removeFromSuperview()
            self.processesView = nil
            self.processes = nil
            self.addArrangedSubview(self.initProcesses())
            self.footer = self.footerView()
            self.addArrangedSubview(self.footer!)
            self.applySemanticColors()
            self.processesInitialized = false
            self.recalculateHeight()
        })
    }

    // MARK: - Settings

    public override func settings() -> NSView? {
        let view = SettingsContainerView()

        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Keyboard shortcut"), component: KeyboardShartcutView(
                callback: self.setKeyboardShortcut,
                value: self.keyboardShortcut
            ))
        ]))

        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("App color"), component: colorSelectView(
                action: #selector(toggleAppColor),
                items: SColor.allColors,
                selected: self.appColorState.key
            )),
            PreferencesRow(localizedString("Wired color"), component: colorSelectView(
                action: #selector(toggleWiredColor),
                items: SColor.allColors,
                selected: self.wiredColorState.key
            )),
            PreferencesRow(localizedString("Compressed color"), component: colorSelectView(
                action: #selector(toggleCompressedColor),
                items: SColor.allColors,
                selected: self.compressedColorState.key
            )),
            PreferencesRow(localizedString("Free color"), component: colorSelectView(
                action: #selector(toggleFreeColor),
                items: SColor.allColors,
                selected: self.freeColorState.key
            ))
        ]))

        self.sliderView = sliderView(
            action: #selector(self.toggleLineChartFixedScale),
            value: Int(self.lineChartFixedScale * 100),
            initialValue: "\(Int(self.lineChartFixedScale * 100)) %"
        )
        self.chartPrefSection = PreferencesSection([
            PreferencesRow(localizedString("Chart color"), component: colorSelectView(
                action: #selector(self.toggleChartColor),
                items: SColor.allColors,
                selected: self.chartColorState.key
            )),
            PreferencesRow(localizedString("Chart history"), component: selectView(
                action: #selector(self.toggleLineChartHistory),
                items: LineChartHistory,
                selected: "\(self.lineChartHistory)"
            )),
            PreferencesRow(localizedString("Main chart scaling"), component: selectView(
                action: #selector(self.toggleLineChartScale),
                items: Scale.allCases,
                selected: self.lineChartScale.key
            )),
            PreferencesRow(localizedString("Scale value"), component: self.sliderView!)
        ])
        self.chartPrefSection?.setRowVisibility(3, newState: self.lineChartScale == .fixed)
        view.addArrangedSubview(self.chartPrefSection!)

        return view
    }

    @objc private func toggleAppColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.appColorState = SColor.fromString(key, defaultValue: self.appColorState)
        Store.shared.set(key: "\(self.title)_appColor", value: self.appColorState.key)
        if let color = self.appColorState.additional as? NSColor {
            self.appColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleWiredColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.wiredColorState = SColor.fromString(key, defaultValue: self.wiredColorState)
        Store.shared.set(key: "\(self.title)_wiredColor", value: self.wiredColorState.key)
        if let color = self.wiredColorState.additional as? NSColor {
            self.wiredColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleCompressedColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.compressedColorState = SColor.fromString(key, defaultValue: self.compressedColorState)
        Store.shared.set(key: "\(self.title)_compressedColor", value: self.compressedColorState.key)
        if let color = self.compressedColorState.additional as? NSColor {
            self.compressedColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleFreeColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.freeColorState = SColor.fromString(key, defaultValue: self.freeColorState)
        Store.shared.set(key: "\(self.title)_freeColor", value: self.freeColorState.key)
        if let color = self.freeColorState.additional as? NSColor {
            self.freeColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleChartColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.chartColorState = SColor.fromString(key, defaultValue: self.chartColorState)
        Store.shared.set(key: "\(self.title)_chartColor", value: self.chartColorState.key)
        if let color = self.chartColorState.additional as? NSColor {
            self.chart?.setColor(color)
        }
    }
    @objc private func toggleLineChartHistory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.lineChartHistory = value
        Store.shared.set(key: "\(self.title)_lineChartHistory", value: value)
        self.chart?.reinit(self.lineChartHistory)
        self.historyWindowField?.stringValue = self.historyWindowString()
    }
    @objc private func toggleLineChartScale(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let value = Scale.allCases.first(where: { $0.key == key }) else { return }
        self.chartPrefSection?.setRowVisibility(3, newState: value == .fixed)
        self.lineChartScale = value
        self.chart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartScale", value: key)
        self.display()
    }
    @objc private func toggleLineChartFixedScale(_ sender: NSSlider) {
        let value = Int(sender.doubleValue)

        if let field = self.sliderView?.subviews.first(where: { $0 is NSTextField }), let view = field as? NSTextField {
            view.stringValue = "\(value) %"
        }

        self.lineChartFixedScale = sender.doubleValue / 100
        self.chart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartFixedScale", value: value)
    }
}
