//
//  popup.swift
//  Battery
//
//  Created by Serhiy Mytrovtsiy on 06/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private let heroHeight: CGFloat = 64

    private let capacityLabelsHeight: CGFloat = 11
    private let capacityValuesHeight: CGFloat = 14
    private let capacityBarGap: CGFloat = 8
    private let capacityBarHeight: CGFloat = 10
    private var capacityHeight: CGFloat {
        self.capacityLabelsHeight + self.capacityValuesHeight + self.capacityBarGap + self.capacityBarHeight
    }

    private let detailsRowCount: Int = 2 // source, time
    private var detailsHeight: CGFloat {
        let rows = CGFloat(self.detailsRowCount)
        return self.sectionHeaderHeight
            + (Constants.Popup.processHeight * rows)
            + (Constants.Design.hairlineWidth * (rows - 1))
            + self.sectionBottomPadding
    }
    private let batteryRowCount: Int = 4 // power, current, voltage, health
    private var batteryHeight: CGFloat {
        let rows = CGFloat(self.batteryRowCount)
        return self.sectionHeaderHeight
            + self.capacityHeight
            + Constants.Design.hairlineWidth
            + (Constants.Popup.processHeight * rows)
            + (Constants.Design.hairlineWidth * (rows - 1))
            + self.sectionBottomPadding
    }
    private let adapterRowCount: Int = 3 // power, current, voltage
    private var adapterHeight: CGFloat {
        let rows = CGFloat(self.adapterRowCount)
        return self.sectionHeaderHeight
            + 22 // is charging badge row
            + (Constants.Popup.processHeight * rows)
            + (Constants.Design.hairlineWidth * rows)
            + self.sectionBottomPadding
    }
    private var processesHeight: CGFloat {
        let n = self.numberOfProcesses
        if n == 0 { return 0 }
        return self.sectionHeaderHeight
            + (Constants.Popup.processHeight * CGFloat(n))
            + self.sectionBottomPadding
    }

    private var levelField: NSTextField? = nil
    private var levelCaptionField: NSTextField? = nil

    private var temperatureChipView: NSView? = nil
    private var temperatureChipField: NSTextField? = nil
    private var cyclesChipView: NSView? = nil
    private var cyclesChipField: NSTextField? = nil

    private var sourceField: NSTextField? = nil
    private var timeLabelField: NSTextField? = nil
    private var timeField: NSTextField? = nil

    private var batterySection: NSView? = nil
    private var barView: BarChartView = BarChartView(size: 10, horizontal: true)
    private var maxCapacityField: NSTextField? = nil
    private var designedCapacityField: NSTextField? = nil
    private var powerField: NSTextField? = nil
    private var currentField: NSTextField? = nil
    private var voltageField: NSTextField? = nil
    private var healthField: NSTextField? = nil

    private var adapterView: NSView? = nil
    private var chargingStateField: StatusBadgeView? = nil
    private var adapterPowerField: NSTextField? = nil
    private var adapterCurrentField: NSTextField? = nil
    private var adapterVoltageField: NSTextField? = nil

    private var processesView: NSView? = nil
    private var processes: ProcessesView? = nil
    private var processesInitialized: Bool = false

    private var footer: NSView? = nil

    private let usageCache = PopupCache<Battery_Usage>()

    private var numberOfProcesses: Int {
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
    }
    private var timeFormat: String {
        Store.shared.string(key: "\(self.title)_timeFormat", defaultValue: "short")
    }

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.spacing = Constants.Design.space2
        self.orientation = .vertical

        self.addArrangedSubview(self.initHero())
        self.addArrangedSubview(self.initDetails())
        self.addArrangedSubview(self.initBattery())
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
        self.barView.display()
    }

    public override func appear() {
        self.replay(self.usageCache, render: self.renderUsage)
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

        let big = NSTextField(labelWithAttributedString: self.levelString(0))
        big.frame = NSRect(x: self.heroSidePadding, y: 18, width: 200, height: 40)
        big.setAccessibilityLabel(localizedString("Battery level"))
        self.levelField = big
        view.addSubview(big)

        let caption = NSTextField(labelWithString: localizedString("Battery level"))
        caption.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: self.heroSidePadding + 1, y: 4, width: 200, height: 13)
        self.levelCaptionField = caption
        view.addSubview(caption)

        let chips = NSStackView()
        chips.orientation = .vertical
        chips.alignment = .trailing
        chips.spacing = 5
        chips.frame = NSRect(x: self.frame.width - self.heroSidePadding - 160, y: 6, width: 160, height: 41)

        let temperatureChip = self.makeChip()
        self.temperatureChipView = temperatureChip.0
        self.temperatureChipField = temperatureChip.1
        let cyclesChip = self.makeChip()
        self.cyclesChipView = cyclesChip.0
        self.cyclesChipField = cyclesChip.1

        chips.addArrangedSubview(temperatureChip.0)
        chips.addArrangedSubview(cyclesChip.0)
        view.addSubview(chips)

        return view
    }

    private func levelString(_ percentage: Int) -> NSAttributedString {
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

        self.sourceField = popupRow(container, title: "\(localizedString("Source")):", value: localizedString("Unknown")).1
        self.addDetailSeparator(container, width: innerWidth)
        let time = popupRow(container, title: "\(localizedString("Time to discharge")):", value: localizedString("Unknown"))
        self.timeLabelField = time.0
        self.timeField = time.1

        view.addSubview(container)

        return view
    }

    private func initCapacity(width: CGFloat) -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: self.capacityHeight))
        view.heightAnchor.constraint(equalToConstant: self.capacityHeight).isActive = true

        let labelsY = self.capacityHeight - self.capacityLabelsHeight
        let valuesY = labelsY - self.capacityValuesHeight

        let maxLabel = LabelField(localizedString("Max capacity"), size: 8)
        maxLabel.textColor = .tertiaryLabelColor
        maxLabel.frame = NSRect(x: 0, y: labelsY, width: width/2, height: self.capacityLabelsHeight)

        let designedLabel = LabelField(localizedString("Designed capacity"), size: 8)
        designedLabel.textColor = .tertiaryLabelColor
        designedLabel.alignment = .right
        designedLabel.frame = NSRect(x: width/2, y: labelsY, width: width/2, height: self.capacityLabelsHeight)

        let maxValue = LabelField("0 mAh", size: 11)
        maxValue.textColor = .secondaryLabelColor
        maxValue.frame = NSRect(x: 0, y: valuesY, width: width/2, height: self.capacityValuesHeight)

        let designedValue = LabelField("0 mAh", size: 11)
        designedValue.textColor = .secondaryLabelColor
        designedValue.alignment = .right
        designedValue.frame = NSRect(x: width/2, y: valuesY, width: width/2, height: self.capacityValuesHeight)

        self.maxCapacityField = maxValue
        self.designedCapacityField = designedValue

        self.barView.frame = NSRect(x: 0, y: 0, width: width, height: self.capacityBarHeight)

        view.addSubview(maxLabel)
        view.addSubview(designedLabel)
        view.addSubview(maxValue)
        view.addSubview(designedValue)
        view.addSubview(self.barView)

        return view
    }

    private func initBattery() -> NSView {
        let view = self.sectionView(localizedString("Battery"), height: self.batteryHeight)
        let innerWidth = self.frame.width - self.sectionSidePadding*2
        let container = NSStackView(frame: NSRect(
            x: self.sectionSidePadding,
            y: self.sectionBottomPadding,
            width: innerWidth,
            height: self.batteryHeight - self.sectionHeaderHeight - self.sectionBottomPadding
        ))
        container.orientation = .vertical
        container.spacing = 0

        container.addArrangedSubview(self.initCapacity(width: innerWidth))
        self.addDetailSeparator(container, width: innerWidth)
        self.powerField = popupRow(container, title: "\(localizedString("Power")):", value: "0 W").1
        self.addDetailSeparator(container, width: innerWidth)
        self.currentField = popupRow(container, title: "\(localizedString("Current")):", value: "0 mA").1
        self.addDetailSeparator(container, width: innerWidth)
        self.voltageField = popupRow(container, title: "\(localizedString("Voltage")):", value: "0 V").1
        self.addDetailSeparator(container, width: innerWidth)
        self.healthField = popupRow(container, title: "\(localizedString("Health")):", value: "").1

        view.addSubview(container)

        self.batterySection = view

        return view
    }

    private func initAdapter() -> NSView {
        let view = self.sectionView(localizedString("Power adapter"), height: self.adapterHeight)
        let innerWidth = self.frame.width - self.sectionSidePadding*2
        let container = NSStackView(frame: NSRect(
            x: self.sectionSidePadding,
            y: self.sectionBottomPadding,
            width: innerWidth,
            height: self.adapterHeight - self.sectionHeaderHeight - self.sectionBottomPadding
        ))
        container.orientation = .vertical
        container.spacing = 0

        self.chargingStateField = popupBadgeRow(container, title: "\(localizedString("Is charging")):", ok: "Yes", notOk: "No").1
        self.addDetailSeparator(container, width: innerWidth)
        self.adapterPowerField = popupRow(container, title: "\(localizedString("Power")):", value: "0 W").1
        self.addDetailSeparator(container, width: innerWidth)
        self.adapterCurrentField = popupRow(container, title: "\(localizedString("Current")):", value: "0 mA").1
        self.addDetailSeparator(container, width: innerWidth)
        self.adapterVoltageField = popupRow(container, title: "\(localizedString("Voltage")):", value: "0 V").1

        view.addSubview(container)

        self.adapterView = view

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

    public func usageCallback(_ value: Battery_Usage) {
        self.apply(value, to: self.usageCache, render: self.renderUsage)
    }

    private func statusText(_ value: Battery_Usage) -> String {
        if value.isBatteryPowered {
            return localizedString("On battery")
        }
        if value.isCharging {
            return localizedString("Charging")
        }
        if value.isCharged && value.level >= 1 {
            return localizedString("Plugged in")
        }
        if value.optimizedChargingEngaged {
            return localizedString("On hold")
        }
        return localizedString("Charging")
    }

    private func renderUsage(_ value: Battery_Usage) {
        let percentage = Int(abs(value.level) * 100)
        self.levelField?.attributedStringValue = self.levelString(percentage)
        self.levelField?.setAccessibilityLabel("\(localizedString("Battery level")): \(percentage)%")
        self.levelField?.toolTip = "\(value.currentCapacity) mAh"
        self.levelCaptionField?.stringValue = "\(localizedString("Battery level")) · \(self.statusText(value))"

        self.temperatureChipView?.isHidden = false
        self.temperatureChipField?.attributedStringValue = self.chipString(temperature(value.temperature), suffix: localizedString("temp"))
        self.temperatureChipView?.toolTip = "\(localizedString("Temperature")): \(temperature(value.temperature))"

        self.cyclesChipView?.isHidden = false
        self.cyclesChipField?.attributedStringValue = self.chipString("\(value.cycles)", suffix: localizedString("cycles"))
        self.cyclesChipView?.toolTip = "\(localizedString("Cycles")): \(value.cycles)"

        self.sourceField?.stringValue = localizedString(value.powerSource)

        if value.isBatteryPowered {
            self.timeLabelField?.stringValue = "\(localizedString("Time to discharge")):"
            if value.timeToEmpty != -1 && value.timeToEmpty != 0 {
                self.timeField?.stringValue = Double(value.timeToEmpty*60).printSecondsToHoursMinutesSeconds(short: self.timeFormat == "short")
            } else {
                self.timeField?.stringValue = localizedString("Unknown")
            }

            if self.adapterView != nil {
                self.adapterView?.removeFromSuperview()
                self.adapterView = nil
                self.recalculateHeight()
            }
        } else {
            self.timeLabelField?.stringValue = "\(localizedString("Time to charge")):"
            if value.timeToCharge != -1 && value.timeToCharge != 0 {
                self.timeField?.stringValue = Double(value.timeToCharge*60).printSecondsToHoursMinutesSeconds(short: self.timeFormat == "short")
            } else {
                self.timeField?.stringValue = localizedString("Unknown")
            }

            if self.adapterView == nil {
                var index: Int = 3
                if let section = self.batterySection, let i = self.arrangedSubviews.firstIndex(of: section) {
                    index = i + 1
                }
                self.insertArrangedSubview(self.initAdapter(), at: index)
                self.applySemanticColors()
                self.recalculateHeight()
            }

            self.chargingStateField?.setStatus(value.isCharging)

            var power: String = value.adapterPower > 0 ? "\(value.adapterPower.roundTo(decimalPlaces: 2)) W" : ""
            if value.ACwatts > 0 {
                power = power.isEmpty ? "\(value.ACwatts) W" : "\(power) / \(value.ACwatts) W"
            }
            self.adapterPowerField?.stringValue = power.isEmpty ? "0 W" : power

            let adapterCurrent = value.adapterVoltage > 0 ? Int((value.adapterPower / value.adapterVoltage) * 1000) : 0
            self.adapterCurrentField?.stringValue = "\(adapterCurrent) mA"
            self.adapterCurrentField?.toolTip = "\(localizedString("Charging")): \(value.chargingCurrent) mA"
            self.adapterVoltageField?.stringValue = "\(value.adapterVoltage.roundTo(decimalPlaces: 2)) V"
            self.adapterVoltageField?.toolTip = "\(localizedString("Charging")): \((Double(value.chargingVoltage)/1000).roundTo(decimalPlaces: 2)) V"
        }

        self.powerField?.stringValue = "\(abs(value.batteryPower).roundTo(decimalPlaces: 2)) W"
        self.currentField?.stringValue = "\(value.current) mA"
        self.voltageField?.stringValue = "\(value.voltage.roundTo(decimalPlaces: 2)) V"

        if value.timeToEmpty == -1 || value.timeToCharge == -1 {
            self.timeField?.stringValue = localizedString("Calculating")
        }
        if value.isCharged {
            self.timeField?.stringValue = localizedString("Fully charged")
        } else if value.optimizedChargingEngaged {
            self.timeField?.stringValue = localizedString("On hold")
        }

        self.barView.setValue(ColorValue(Double(value.health)/100, color: .systemGreen))
        self.maxCapacityField?.stringValue = "\(value.maxCapacity) mAh"
        self.designedCapacityField?.stringValue = "\(value.designedCapacity) mAh"
        self.healthField?.stringValue = "\(value.health)%"
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
                self.processes?.set(i, process, ["\(process.usage)%"], share: share)
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

        return view
    }
}

internal class BatteryView: NSView {
    private var percentage: Double = 0
    private var connected: Bool = false
    private var charging: Bool = false

    public override init(frame: NSRect = NSRect.zero) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let scale: CGFloat = Swift.min(self.frame.width/130, self.frame.height/60, 1)
        let w: CGFloat = 130 * scale
        let h: CGFloat = 60 * scale
        let x: CGFloat = (self.frame.width - w)/2
        let y: CGFloat = (self.frame.size.height - h) / 2
        let lineWidth: CGFloat = Swift.max(1, 2*scale)
        let pointWidth: CGFloat = 7 * scale
        let batteryFrame = NSBezierPath(roundedRect: NSRect(
            x: x + lineWidth/2,
            y: y + lineWidth/2,
            width: w - pointWidth - lineWidth,
            height: h - lineWidth
        ), xRadius: 16*scale, yRadius: 16*scale)

        NSColor.secondaryLabelColor.set()

        let bPX: CGFloat = batteryFrame.bounds.origin.x + batteryFrame.bounds.width
        let bPY: CGFloat = batteryFrame.bounds.origin.y + (batteryFrame.bounds.height/2) - (12*scale)
        let batteryPoint = NSBezierPath(roundedRect: NSRect(x: bPX, y: bPY, width: pointWidth, height: 24*scale), xRadius: 6*scale, yRadius: 6*scale)
        batteryPoint.fill()

        let batteryPointSeparator = NSBezierPath()
        batteryPointSeparator.move(to: CGPoint(x: bPX, y: batteryFrame.bounds.origin.y))
        batteryPointSeparator.line(to: CGPoint(x: bPX, y: batteryFrame.bounds.origin.y + batteryFrame.bounds.height))
        ctx.saveGState()
        ctx.setBlendMode(.destinationOut)
        NSColor.textColor.set()
        batteryPointSeparator.lineWidth = 6*scale
        batteryPointSeparator.stroke()
        ctx.restoreGState()

        batteryFrame.lineWidth = lineWidth
        batteryFrame.stroke()

        if self.percentage == 0 {
            return
        }

        let innerPadding: CGFloat = 5 * scale
        let innerHeight: CGFloat = h - (innerPadding*2)
        let minWidth: CGFloat = 8 * scale
        let track: CGFloat = w - (16*scale)
        var fillWidth: CGFloat = 0
        if self.percentage > 0 {
            fillWidth = minWidth + (track - minWidth) * CGFloat(self.percentage)
        }
        let fillRadius: CGFloat = Swift.min(12*scale, fillWidth/2, innerHeight/2)
        let inner = NSBezierPath(roundedRect: NSRect(
            x: x + innerPadding,
            y: y + innerPadding,
            width: fillWidth,
            height: innerHeight
        ), xRadius: fillRadius, yRadius: fillRadius)
        self.percentage.batteryColorV2().set()
        inner.lineWidth = 0
        inner.stroke()
        inner.close()
        inner.fill()

        if self.connected {
            let center = CGPoint(
                x: batteryFrame.bounds.origin.x + (batteryFrame.bounds.width/2),
                y: batteryFrame.bounds.origin.y + (batteryFrame.bounds.height/2)
            )
            let symbolName: String = self.charging ? "bolt.fill" : "powerplug.fill"
            let symbolSize: CGFloat = 24 * scale

            if self.percentage > 0.55 {
                guard let body = self.coloredSymbol(symbolName, color: .white, size: symbolSize) else { return }
                let size: NSSize = body.size
                body.draw(in: NSRect(x: center.x - (size.width/2), y: center.y - (size.height/2), width: size.width, height: size.height))
                return
            }

            guard let outline = self.coloredSymbol(symbolName, color: .black, size: symbolSize),
                  let body = self.coloredSymbol(symbolName, color: self.percentage.batteryColorV2(), size: symbolSize) else { return }

            let size: NSSize = body.size
            let border: CGFloat = Swift.max(1, 2*scale)
            let origin = CGPoint(x: center.x - (size.width/2), y: center.y - (size.height/2))

            let steps: Int = 24
            for i in 0..<steps {
                let angle: CGFloat = (CGFloat(i) / CGFloat(steps)) * 2 * .pi
                outline.draw(in: NSRect(
                    x: origin.x + (cos(angle) * border),
                    y: origin.y + (sin(angle) * border),
                    width: size.width,
                    height: size.height
                ), from: .zero, operation: .destinationOut, fraction: 1.0)
            }
            body.draw(in: NSRect(origin: origin, size: size))
        }
    }

    public func setValue(_ value: Double, connected: Bool, charging: Bool) {
        if self.percentage == value && self.connected == connected && self.charging == charging { return }

        self.percentage = value
        self.connected = connected
        self.charging = charging

        DispatchQueue.main.async(execute: {
            self.display()
        })
    }

    private func coloredSymbol(_ name: String, color: NSColor, size: CGFloat) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: size, weight: .bold)
        config = config.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = false
        return image
    }
}
