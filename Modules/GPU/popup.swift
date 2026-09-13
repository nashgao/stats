//
//  popup.swift
//  GPU
//
//  Created by Serhiy Mytrovtsiy on 17/08/2020.
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

    private let detailsRowCount: Int = 7 // model, cores, utilization, render, tiler, ane, fps
    private var detailsHeight: CGFloat {
        let rows = CGFloat(self.detailsRowCount)
        return self.sectionHeaderHeight
            + (Constants.Popup.processHeight * rows)
            + (Constants.Design.hairlineWidth * (rows - 1))
            + self.sectionBottomPadding
    }

    private let loadCache = PopupCache<GPU_Info>()

    private var usageField: NSTextField? = nil
    private var peakField: NSTextField? = nil
    private var historyWindowField: NSTextField? = nil

    private var temperatureChipView: NSView? = nil
    private var temperatureChipField: NSTextField? = nil
    private var coreClockChipView: NSView? = nil
    private var coreClockChipField: NSTextField? = nil
    private var fanSpeedChipView: NSView? = nil
    private var fanSpeedChipField: NSTextField? = nil

    private var chart: LineChartView? = nil
    private var lineChartHistory: Int = 180
    private var lineChartScale: Scale = .none
    private var lineChartFixedScale: Double = 1

    private var modelField: NSTextField? = nil
    private var coresField: NSTextField? = nil
    private var utilizationField: NSTextField? = nil
    private var renderField: NSTextField? = nil
    private var tilerField: NSTextField? = nil
    private var aneField: NSTextField? = nil
    private var fpsField: NSTextField? = nil

    private var footer: NSView? = nil

    private var peakUsage: Double = 0

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.spacing = Constants.Design.space2
        self.orientation = .vertical

        if let gpus = SystemKit.shared.device.info.gpu {
            var subtitleParts: [String] = []
            if let name = gpus.first(where: { $0.name != nil && !($0.name!.isEmpty) })?.name {
                subtitleParts.append(name)
            }
            if let cores = gpus.first(where: { $0.cores != nil })?.cores {
                subtitleParts.append("\(cores) \(localizedString("cores"))")
            }
            if !subtitleParts.isEmpty {
                self.subtitle = subtitleParts.joined(separator: " · ")
            }
        }

        self.addArrangedSubview(self.initHero())
        self.addArrangedSubview(self.initTrend())
        self.addArrangedSubview(self.initDetails())
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
        big.setAccessibilityLabel(localizedString("GPU usage"))
        self.usageField = big
        view.addSubview(big)

        let caption = NSTextField(labelWithString: localizedString("GPU usage"))
        caption.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: self.heroSidePadding + 1, y: 4, width: 200, height: 13)
        view.addSubview(caption)

        let chips = NSStackView()
        chips.orientation = .vertical
        chips.alignment = .trailing
        chips.spacing = 5
        chips.frame = NSRect(x: self.frame.width - self.heroSidePadding - 160, y: 0, width: 160, height: self.heroHeight)

        let temperatureChip = self.makeChip()
        self.temperatureChipView = temperatureChip.0
        self.temperatureChipField = temperatureChip.1
        let coreClockChip = self.makeChip()
        self.coreClockChipView = coreClockChip.0
        self.coreClockChipField = coreClockChip.1
        let fanSpeedChip = self.makeChip()
        self.fanSpeedChipView = fanSpeedChip.0
        self.fanSpeedChipField = fanSpeedChip.1

        chips.addArrangedSubview(temperatureChip.0)
        chips.addArrangedSubview(coreClockChip.0)
        chips.addArrangedSubview(fanSpeedChip.0)
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
        chart.setColor(.controlAccentColor)
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
        self.modelField = popupRow(container, title: "\(localizedString("Model")):", value: "").1
        nextRow()
        self.coresField = popupRow(container, title: "\(localizedString("Cores")):", value: localizedString("Unknown")).1
        nextRow()
        self.utilizationField = popupRow(container, title: "\(localizedString("Utilization")):", value: "").1
        nextRow()
        self.renderField = popupRow(container, title: "\(localizedString("Render utilization")):", value: "").1
        nextRow()
        self.tilerField = popupRow(container, title: "\(localizedString("Tiler utilization")):", value: "").1
        nextRow()
        self.aneField = popupRow(container, title: "\(localizedString("ANE utilization")):", value: "").1
        nextRow()
        self.fpsField = popupRow(container, title: "\(localizedString("FPS")):", value: "").1

        view.addSubview(container)

        return view
    }

    // MARK: - Callback

    public func loadCallback(_ value: GPU_Info) {
        self.apply(value, to: self.loadCache, render: self.renderLoad)
        if let utilization = value.utilization {
            self.chart?.addValue(utilization)
        }
    }

    private func renderLoad(_ value: GPU_Info) {
        self.modelField?.stringValue = value.model

        if let cores = value.cores {
            self.coresField?.stringValue = "\(cores)"
        }

        if let utilization = value.utilization {
            let percentage = Int(utilization.rounded(toPlaces: 2) * 100)
            self.usageField?.attributedStringValue = self.usageString(percentage)
            self.usageField?.setAccessibilityLabel("\(localizedString("GPU usage")): \(percentage)%")

            if utilization > self.peakUsage {
                self.peakUsage = utilization
            }
            self.peakField?.stringValue = "\(localizedString("Peak")) \(Int(self.peakUsage * 100))%"

            self.utilizationField?.stringValue = "\(Int(utilization*100))%"
        }
        if let utilization = value.renderUtilization {
            self.renderField?.stringValue = "\(Int(utilization*100))%"
        }
        if let utilization = value.tilerUtilization {
            self.tilerField?.stringValue = "\(Int(utilization*100))%"
        }
        if let utilization = value.aneUtilization {
            self.aneField?.stringValue = "\(Int(utilization*100))%"
        }
        if let fps = value.fps {
            self.fpsField?.stringValue = "\(Int(fps.rounded()))"
        }

        if let t = value.temperature {
            self.temperatureChipView?.isHidden = false
            self.temperatureChipField?.attributedStringValue = self.chipString(temperature(t), suffix: localizedString("temp"))
            self.temperatureChipView?.toolTip = "\(localizedString("GPU temperature")): \(temperature(t))"
        }
        if let coreClock = value.coreClock {
            self.coreClockChipView?.isHidden = false
            self.coreClockChipField?.attributedStringValue = self.chipString("\(coreClock)", suffix: "MHz")
            self.coreClockChipView?.toolTip = "\(localizedString("GPU core clock")): \(coreClock) MHz"
        }
        if let fanSpeed = value.fanSpeed {
            self.fanSpeedChipView?.isHidden = false
            self.fanSpeedChipField?.attributedStringValue = self.chipString("\(fanSpeed)", suffix: "%")
            self.fanSpeedChipView?.toolTip = "\(localizedString("GPU fan speed")): \(fanSpeed)%"
        }

        self.chart?.display()
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

        return view
    }
}
