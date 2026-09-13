//
//  popup.swift
//  CPU
//
//  Created by Serhiy Mytrovtsiy on 15/04/2020.
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

    private var detailsRowCount: Int {
        var count: Int = 5 // system, user, idle, uptime, average load
        if !isARM {
            count += 2 // scheduler limit, speed limit
        }
        if SystemKit.shared.device.info.cpu?.eCores != nil {
            count += 1
        }
        if SystemKit.shared.device.info.cpu?.sCores != nil {
            count += 1
        }
        if SystemKit.shared.device.info.cpu?.pCores != nil {
            count += 1
        }
        return count
    }
    private var detailsHeight: CGFloat {
        let rows = CGFloat(self.detailsRowCount)
        return self.sectionHeaderHeight
            + (Constants.Popup.processHeight * rows)
            + (Constants.Design.hairlineWidth * (rows - 1))
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

    private var temperatureChipView: NSView? = nil
    private var temperatureChipField: NSTextField? = nil
    private var frequencyChipView: NSView? = nil
    private var frequencyChipField: NSTextField? = nil

    private var systemField: NSTextField? = nil
    private var userField: NSTextField? = nil
    private var idleField: NSTextField? = nil
    private var shedulerLimitField: NSTextField? = nil
    private var speedLimitField: NSTextField? = nil
    private var eCoresField: NSTextField? = nil
    private var pCoresField: NSTextField? = nil
    private var sCoresField: NSTextField? = nil
    private var uptimeField: NSTextField? = nil
    private var averageField: NSTextField? = nil

    private var systemColorView: NSView? = nil
    private var userColorView: NSView? = nil
    private var idleColorView: NSView? = nil
    private var eCoresColorView: NSView? = nil
    private var pCoresColorView: NSView? = nil
    private var sCoresColorView: NSView? = nil

    private var chartPrefSection: PreferencesSection? = nil
    private var sliderView: NSView? = nil

    private var lineChart: LineChartView? = nil
    private var initializedProcesses: Bool = false

    private let loadCache = PopupCache<CPU_Load>()
    private let temperatureCache = PopupCache<Double>()
    private let frequencyCache = PopupCache<CPU_Frequency>()
    private let limitCache = PopupCache<CPU_Limit>()
    private let averageCache = PopupCache<CPU_AverageLoad>()

    private var processes: ProcessesView? = nil
    private var maxFreq: Double = 0
    private var peakUsage: Double = 0
    private var lineChartHistory: Int = 180
    private var lineChartScale: Scale = .none
    private var lineChartFixedScale: Double = 1

    private var systemColorState: SColor = .secondRed
    private var systemColor: NSColor { self.systemColorState.additional as? NSColor ?? NSColor.systemRed }
    private var userColorState: SColor = .secondBlue
    private var userColor: NSColor { self.userColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var idleColorState: SColor = .lightGray
    private var idleColor: NSColor { self.idleColorState.additional as? NSColor ?? NSColor.lightGray }
    private var chartColorState: SColor = .systemAccent
    private var chartColor: NSColor { self.chartColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var eCoresColorState: SColor = .teal
    private var eCoresColor: NSColor { self.eCoresColorState.additional as? NSColor ?? NSColor.systemTeal }
    private var pCoresColorState: SColor = .indigo
    private var pCoresColor: NSColor { self.pCoresColorState.additional as? NSColor ?? NSColor.systemBlue }
    private var sCoresColorState: SColor = .orange
    private var sCoresColor: NSColor { self.sCoresColorState.additional as? NSColor ?? NSColor.systemOrange }

    private var processesView: NSView? = nil
    private var footer: NSView? = nil

    private var numberOfProcesses: Int {
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
    }
    private var uptimeValue: String {
        let form = DateComponentsFormatter()
        form.maximumUnitCount = 2
        form.unitsStyle = .full
        form.allowedUnits = [.day, .hour, .minute]
        var value = localizedString("Unknown")
        if let bootDate = SystemKit.shared.device.bootDate {
            if let duration = form.string(from: bootDate, to: Date()) {
                value = duration
            }
        }
        return value
    }

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.spacing = Constants.Design.space2
        self.orientation = .vertical

        self.systemColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_systemColor", defaultValue: self.systemColorState.key))
        self.userColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_userColor", defaultValue: self.userColorState.key))
        self.idleColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_idleColor", defaultValue: self.idleColorState.key))
        self.chartColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_chartColor", defaultValue: self.chartColorState.key))
        self.eCoresColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_eCoresColor", defaultValue: self.eCoresColorState.key))
        self.pCoresColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_pCoresColor", defaultValue: self.pCoresColorState.key))
        self.sCoresColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_sCoresColor", defaultValue: self.sCoresColorState.key))
        self.lineChartHistory = Store.shared.int(key: "\(self.title)_lineChartHistory", defaultValue: self.lineChartHistory)
        self.lineChartScale = Scale.fromString(Store.shared.string(key: "\(self.title)_lineChartScale", defaultValue: self.lineChartScale.key))
        self.lineChartFixedScale = Double(Store.shared.int(key: "\(self.title)_lineChartFixedScale", defaultValue: 100)) / 100

        if let cpu = SystemKit.shared.device.info.cpu {
            var subtitleParts: [String] = []
            if let name = cpu.name, !name.isEmpty {
                subtitleParts.append(name)
            }
            if let cores = cpu.logicalCores {
                subtitleParts.append("\(cores) \(localizedString("cores"))")
            }
            if !subtitleParts.isEmpty {
                self.subtitle = subtitleParts.joined(separator: " · ")
            }
        }

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
        self.lineChart?.display()
    }

    public override func appear() {
        self.uptimeField?.stringValue = self.uptimeValue
        self.replay(self.loadCache, render: self.renderLoad)
        self.replay(self.temperatureCache, render: self.renderTemperature)
        self.replay(self.frequencyCache, render: self.renderFrequency)
        self.replay(self.limitCache, render: self.renderLimit)
        self.replay(self.averageCache, render: self.renderAverage)
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
        big.setAccessibilityLabel(localizedString("CPU usage"))
        self.usageField = big
        view.addSubview(big)

        let caption = NSTextField(labelWithString: localizedString("CPU usage"))
        caption.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: self.heroSidePadding + 1, y: 4, width: 200, height: 13)
        view.addSubview(caption)

        let chips = NSStackView()
        chips.orientation = .vertical
        chips.alignment = .trailing
        chips.spacing = 5
        chips.frame = NSRect(x: self.frame.width - self.heroSidePadding - 160, y: 6, width: 160, height: 41)

        let temperatureChip = self.makeChip()
        self.temperatureChipView = temperatureChip.0
        self.temperatureChipField = temperatureChip.1
        let frequencyChip = self.makeChip()
        self.frequencyChipView = frequencyChip.0
        self.frequencyChipField = frequencyChip.1

        chips.addArrangedSubview(temperatureChip.0)
        chips.addArrangedSubview(frequencyChip.0)
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
        self.lineChart = chart
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
        (self.systemColorView, _, self.systemField) = popupWithColorRow(container, color: self.systemColor, title: "\(localizedString("System")):", value: "")
        nextRow()
        (self.userColorView, _, self.userField) = popupWithColorRow(container, color: self.userColor, title: "\(localizedString("User")):", value: "")
        nextRow()
        (self.idleColorView, _, self.idleField) = popupWithColorRow(container, color: self.idleColor.withAlphaComponent(0.5), title: "\(localizedString("Idle")):", value: "")

        if !isARM {
            nextRow()
            self.shedulerLimitField = popupRow(container, title: "\(localizedString("Scheduler limit")):", value: "").1
            nextRow()
            self.speedLimitField = popupRow(container, title: "\(localizedString("Speed limit")):", value: "").1
        }

        if SystemKit.shared.device.info.cpu?.eCores != nil {
            nextRow()
            (self.eCoresColorView, _, self.eCoresField) = popupWithColorRow(container, color: self.eCoresColor, title: "\(localizedString("Efficiency cores")):", value: "")
        }
        if SystemKit.shared.device.info.cpu?.pCores != nil {
            nextRow()
            (self.pCoresColorView, _, self.pCoresField) = popupWithColorRow(container, color: self.pCoresColor, title: "\(localizedString("Performance cores")):", value: "")
        }
        if SystemKit.shared.device.info.cpu?.sCores != nil {
            nextRow()
            (self.sCoresColorView, _, self.sCoresField) = popupWithColorRow(container, color: self.sCoresColor, title: "\(localizedString("Super cores")):", value: "")
        }

        nextRow()
        self.uptimeField = popupRow(container, title: "\(localizedString("Uptime")):", value: self.uptimeValue).1
        self.uptimeField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)

        nextRow()
        self.averageField = popupRow(container, title: "\(localizedString("Average load")) (1/5/15):", value: "").1

        [self.systemColorView, self.userColorView, self.idleColorView, self.eCoresColorView, self.pCoresColorView, self.sCoresColorView].forEach {
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

    public func loadCallback(_ value: CPU_Load) {
        self.apply(value, to: self.loadCache, render: self.renderLoad)
        self.lineChart?.addValue(value.totalUsage)
    }

    private func renderLoad(_ value: CPU_Load) {
        let percentage = Int(value.totalUsage.rounded(toPlaces: 2) * 100)
        self.usageField?.attributedStringValue = self.usageString(percentage)
        self.usageField?.setAccessibilityLabel("\(localizedString("CPU usage")): \(percentage)%")

        if value.totalUsage > self.peakUsage {
            self.peakUsage = value.totalUsage
        }
        self.peakField?.stringValue = "\(localizedString("Peak")) \(Int(self.peakUsage * 100))%"

        self.systemField?.stringValue = "\(Int(value.systemLoad.rounded(toPlaces: 2) * 100))%"
        self.userField?.stringValue = "\(Int(value.userLoad.rounded(toPlaces: 2) * 100))%"
        self.idleField?.stringValue = "\(Int(value.idleLoad.rounded(toPlaces: 2) * 100))%"

        if let field = self.eCoresField, let usage = value.usageECores {
            field.stringValue = "\(Int(usage * 100))%"
        }
        if let field = self.pCoresField, let usage = value.usagePCores {
            field.stringValue = "\(Int(usage * 100))%"
        }
        if let field = self.sCoresField, let usage = value.usageSCores {
            field.stringValue = "\(Int(usage * 100))%"
        }

        self.lineChart?.display()
    }

    public func temperatureCallback(_ value: Double?) {
        guard let value else { return }
        self.apply(value, to: self.temperatureCache, render: self.renderTemperature)
    }

    private func renderTemperature(_ value: Double) {
        self.temperatureChipView?.isHidden = false
        self.temperatureChipField?.attributedStringValue = self.chipString(temperature(value), suffix: localizedString("temp"))
        self.temperatureChipView?.toolTip = "\(localizedString("CPU temperature")): \(temperature(value))"
    }

    public func frequencyCallback(_ value: CPU_Frequency?) {
        guard let value else { return }
        self.apply(value, to: self.frequencyCache, render: self.renderFrequency)
    }

    private func renderFrequency(_ value: CPU_Frequency) {
        guard let v = value.value else { return }
        if v > self.maxFreq {
            self.maxFreq = v
        }

        self.frequencyChipView?.isHidden = false
        self.frequencyChipField?.attributedStringValue = self.chipString("\((v/1000).rounded(toPlaces: 2))", suffix: "GHz")
        self.frequencyChipView?.toolTip = "\(localizedString("CPU frequency")): \(Int(v)) MHz - \(((100*v)/self.maxFreq).rounded(toPlaces: 2))%"
    }

    public func processCallback(_ list: [TopProcess]?) {
        guard let list else { return }

        DispatchQueue.main.async(execute: {
            if !(self.window?.isVisible ?? false) && self.initializedProcesses {
                return
            }
            let list = list.map { $0 }
            if list.count != self.processes?.count { self.processes?.clear() }

            let maxUsage = list.map({ $0.usage }).max() ?? 0
            for i in 0..<list.count {
                let process = list[i]
                let share = maxUsage > 0 ? process.usage / maxUsage : 0
                self.processes?.set(i, process, ["\(process.usage)%"], share: share)
            }

            self.initializedProcesses = true
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
            self.initializedProcesses = false
            self.recalculateHeight()
        })
    }

    public func limitCallback(_ value: CPU_Limit?) {
        guard let value else { return }
        self.apply(value, to: self.limitCache, render: self.renderLimit)
    }

    private func renderLimit(_ value: CPU_Limit) {
        self.shedulerLimitField?.stringValue = "\(value.scheduler)%"
        self.speedLimitField?.stringValue = "\(value.speed)%"
    }

    public func averageCallback(_ value: CPU_AverageLoad?) {
        guard let value else { return }
        self.apply(value, to: self.averageCache, render: self.renderAverage)
    }

    private func renderAverage(_ value: CPU_AverageLoad) {
        self.averageField?.stringValue = "\(value.load1) · \(value.load5) · \(value.load15)"
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
            PreferencesRow(localizedString("System color"), component: colorSelectView(
                action: #selector(self.toggleSystemColor),
                items: SColor.allColors,
                selected: self.systemColorState.key
            )),
            PreferencesRow(localizedString("User color"), component: colorSelectView(
                action: #selector(self.toggleUserColor),
                items: SColor.allColors,
                selected: self.userColorState.key
            )),
            PreferencesRow(localizedString("Idle color"), component: colorSelectView(
                action: #selector(self.toggleIdleColor),
                items: SColor.allColors,
                selected: self.idleColorState.key
            ))
        ]))

        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Efficiency cores color"), component: colorSelectView(
                action: #selector(self.toggleECoresColor),
                items: SColor.allColors,
                selected: self.eCoresColorState.key
            )),
            PreferencesRow(localizedString("Performance cores color"), component: colorSelectView(
                action: #selector(self.togglePCoresColor),
                items: SColor.allColors,
                selected: self.pCoresColorState.key
            )),
            PreferencesRow(localizedString("Super cores color"), component: colorSelectView(
                action: #selector(self.toggleSCoresColor),
                items: SColor.allColors,
                selected: self.sCoresColorState.key
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
        view.addArrangedSubview(self.chartPrefSection!)
        self.chartPrefSection?.setRowVisibility(3, newState: self.lineChartScale == .fixed)

        return view
    }

    @objc private func toggleSystemColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.systemColorState = SColor.fromString(key, defaultValue: self.systemColorState)
        Store.shared.set(key: "\(self.title)_systemColor", value: self.systemColorState.key)
        self.systemColorView?.layer?.backgroundColor = (self.systemColorState.additional as? NSColor)?.cgColor
    }
    @objc private func toggleUserColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.userColorState = SColor.fromString(key, defaultValue: self.userColorState)
        Store.shared.set(key: "\(self.title)_userColor", value: self.userColorState.key)
        self.userColorView?.layer?.backgroundColor = (self.userColorState.additional as? NSColor)?.cgColor
    }
    @objc private func toggleIdleColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.idleColorState = SColor.fromString(key, defaultValue: self.idleColorState)
        Store.shared.set(key: "\(self.title)_idleColor", value: self.idleColorState.key)
        self.idleColorView?.layer?.backgroundColor = (self.idleColorState.additional as? NSColor)?.cgColor
    }
    @objc private func toggleChartColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.chartColorState = SColor.fromString(key, defaultValue: self.chartColorState)
        Store.shared.set(key: "\(self.title)_chartColor", value: self.chartColorState.key)
        if let color = self.chartColorState.additional as? NSColor {
            self.lineChart?.setColor(color)
        }
    }
    @objc private func toggleECoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.eCoresColorState = SColor.fromString(key, defaultValue: self.eCoresColorState)
        Store.shared.set(key: "\(self.title)_eCoresColor", value: self.eCoresColorState.key)
        if let color = (self.eCoresColorState.additional as? NSColor) {
            self.eCoresColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func togglePCoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.pCoresColorState = SColor.fromString(key, defaultValue: self.pCoresColorState)
        Store.shared.set(key: "\(self.title)_pCoresColor", value: self.pCoresColorState.key)
        if let color = (self.pCoresColorState.additional as? NSColor) {
            self.pCoresColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleSCoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.sCoresColorState = SColor.fromString(key, defaultValue: self.sCoresColorState)
        Store.shared.set(key: "\(self.title)_sCoresColor", value: self.sCoresColorState.key)
        if let color = (self.sCoresColorState.additional as? NSColor) {
            self.sCoresColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleLineChartHistory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.lineChartHistory = value
        Store.shared.set(key: "\(self.title)_lineChartHistory", value: value)
        self.lineChart?.reinit(self.lineChartHistory)
        self.historyWindowField?.stringValue = self.historyWindowString()
    }
    @objc private func toggleLineChartScale(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let value = Scale.allCases.first(where: { $0.key == key }) else { return }
        self.chartPrefSection?.setRowVisibility(3, newState: value == .fixed)
        self.lineChartScale = value
        self.lineChart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartScale", value: key)
        self.display()
    }
    @objc private func toggleLineChartFixedScale(_ sender: NSSlider) {
        let value = Int(sender.doubleValue)

        if let field = self.sliderView?.subviews.first(where: { $0 is NSTextField }), let view = field as? NSTextField {
            view.stringValue = "\(value) %"
        }

        self.lineChartFixedScale = sender.doubleValue / 100
        self.lineChart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartFixedScale", value: value)
    }
}
