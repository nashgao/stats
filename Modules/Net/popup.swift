//
//  popup.swift
//  Net
//
//  Created by Serhiy Mytrovtsiy on 24/05/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

// swiftlint:disable:next type_body_length
internal class Popup: PopupWrapper {
    private let heroHeight: CGFloat = 64

    private let trendChartHeight: CGFloat = 90
    private let trendMetaHeight: CGFloat = 12
    private let trendMetaGap: CGFloat = 5
    private var trendHeight: CGFloat {
        self.sectionHeaderHeight + self.trendChartHeight + self.trendMetaGap + self.trendMetaHeight + self.sectionBottomPadding
    }

    private let connectivityChartHeight: CGFloat = 30
    private var connectivityHeight: CGFloat {
        self.sectionHeaderHeight + self.connectivityChartHeight + self.sectionBottomPadding
    }

    private let badgeRowHeight: CGFloat = 22 // matches popupBadgeRow internals
    private var detailsRowHeights: [CGFloat] {
        [
            Constants.Popup.processHeight, // total upload
            Constants.Popup.processHeight, // total download
            self.badgeRowHeight, // status
            self.badgeRowHeight, // internet connection
            Constants.Popup.processHeight, // latency
            Constants.Popup.processHeight // jitter
        ]
    }
    private var detailsHeight: CGFloat {
        let rows = self.detailsRowHeights
        return self.sectionHeaderHeight
            + rows.reduce(0, +)
            + (Constants.Design.hairlineWidth * CGFloat(rows.count - 1))
            + self.sectionBottomPadding
    }
    private var processesHeight: CGFloat {
        let n = self.numberOfProcesses
        if n == 0 { return 0 }
        return self.sectionHeaderHeight
            + (Constants.Popup.processHeight * CGFloat(n))
            + self.sectionBottomPadding
    }

    private var downloadField: NSTextField? = nil
    private var uploadChipView: NSView? = nil
    private var uploadChipField: NSTextField? = nil
    private var latencyChipView: NSView? = nil
    private var latencyChipField: NSTextField? = nil

    private var peakField: NSTextField? = nil
    private var historyWindowField: NSTextField? = nil

    private var downloadColorView: NSView? = nil
    private var uploadColorView: NSView? = nil

    private var totalUploadLabel: LabelField? = nil
    private var totalUploadField: ValueField? = nil
    private var totalDownloadLabel: LabelField? = nil
    private var totalDownloadField: ValueField? = nil
    private var statusField: StatusBadgeView? = nil
    private var connectivityField: StatusBadgeView? = nil
    private var latencyField: ValueField? = nil
    private var jitterField: ValueField? = nil

    private var interfaceView: NSStackView? = nil
    private var interfaceField: ValueField? = nil
    private var interfaceStatusField: StatusBadgeView? = nil
    private var macAddressField: ValueField? = nil
    private var ssidField: ValueField? = nil
    private var standardField: ValueField? = nil
    private var channelField: ValueField? = nil
    private var ssidView: NSView? = nil

    private var interfaceDetailsState: Bool = false
    private var standardView: NSView? = nil
    private var channelView: NSView? = nil
    private var interfaceSpeedView: NSView? = nil
    private var interfaceSpeedField: ValueField? = nil
    private var dnsServersView: NSView? = nil
    private var dnsServersField: ValueField? = nil

    private var addressView: NSStackView? = nil
    private var localIPField: ValueField? = nil
    private var publicIPv4Field: ValueField? = nil
    private var publicIPv6Field: ValueField? = nil
    private var publicIPv4View: NSView? = nil
    private var publicIPv6View: NSView? = nil
    private var publicIPState: Bool = true
    private var emojiCCState: Bool = true

    private var processesView: NSView? = nil
    private var processes: ProcessesView? = nil
    private var footer: NSView? = nil

    private var chart: NetworkChartView? = nil
    private var reverseOrderState: Bool = false
    private var chartHistory: Int = 180
    private var chartScale: Scale = .none
    private var chartFixedScale: Int = 12
    private var chartFixedScaleSize: SizeUnit = .MB
    private var chartPrefSection: PreferencesSection? = nil
    private var connectivityChart: GridChartView? = nil

    private var processesInitialized: Bool = false

    private let usageCache = PopupCache<Network_Usage>()
    private let connectivityCache = PopupCache<Network_Connectivity?>()

    private var lastReset: Date = Date()
    private var latency: [Double] = []
    private var jitter: [Double] = []
    private var peakDownload: Int64 = 0

    private var base: DataSizeBase {
        DataSizeBase(rawValue: Store.shared.string(key: "\(self.title)_base", defaultValue: "byte")) ?? .byte
    }
    private var speedUnit: String {
        networkSpeedUnit(from: Store.shared.string(key: "\(self.title)_speedUnit", defaultValue: NetworkSpeedUnitAuto)).key
    }
    private var numberOfProcesses: Int {
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
    }

    private var downloadColorState: SColor = .secondBlue
    private var downloadColor: NSColor {
        var value = NSColor.systemBlue
        if let color = self.downloadColorState.additional as? NSColor {
            value = color
        }
        return value
    }
    private var uploadColorState: SColor = .secondRed
    private var uploadColor: NSColor {
        var value = NSColor.systemRed
        if let color = self.uploadColorState.additional as? NSColor {
            value = color
        }
        return value
    }

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.spacing = Constants.Design.space2
        self.orientation = .vertical

        self.downloadColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_downloadColor", defaultValue: self.downloadColorState.key))
        self.uploadColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_uploadColor", defaultValue: self.uploadColorState.key))
        self.reverseOrderState = Store.shared.bool(key: "\(self.title)_reverseOrder", defaultValue: self.reverseOrderState)
        self.chartHistory = Store.shared.int(key: "\(self.title)_chartHistory", defaultValue: self.chartHistory)
        self.chartScale = Scale.fromString(Store.shared.string(key: "\(self.title)_chartScale", defaultValue: self.chartScale.key))
        self.chartFixedScale = Store.shared.int(key: "\(self.title)_chartFixedScale", defaultValue: self.chartFixedScale)
        self.chartFixedScaleSize = SizeUnit.fromString(Store.shared.string(key: "\(self.title)_chartFixedScaleSize", defaultValue: self.chartFixedScaleSize.key))
        self.publicIPState = Store.shared.bool(key: "\(self.title)_publicIP", defaultValue: self.publicIPState)
        self.interfaceDetailsState = Store.shared.bool(key: "\(self.title)_interfaceDetails", defaultValue: self.interfaceDetailsState)
        self.emojiCCState = Store.shared.bool(key: "\(self.title)_emojiCC", defaultValue: self.emojiCCState)

        self.addArrangedSubview(self.initHero())
        self.addArrangedSubview(self.initChart())
        self.addArrangedSubview(self.initConnectivityChart())
        self.addArrangedSubview(self.initDetails())
        self.addArrangedSubview(self.initInterface())
        self.addArrangedSubview(self.initAddress())
        self.addArrangedSubview(self.initProcesses())

        if !self.publicIPState {
            self.addressView?.removeFromSuperview()
        }

        self.footer = self.footerView()
        self.addArrangedSubview(self.footer!)

        self.applySemanticColors()
        self.recalculateHeight()

        NotificationCenter.default.addObserver(self, selector: #selector(self.resetTotalNetworkUsageCallback), name: .resetTotalNetworkUsage, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .resetTotalNetworkUsage, object: nil)
    }

    public override func updateLayer() {
        self.applySemanticColors()
        self.chart?.display()
        self.connectivityChart?.display()
    }

    private func recalculateHeight() {
        var h: CGFloat = self.spacing * CGFloat(max(self.arrangedSubviews.count - 1, 0))
        self.arrangedSubviews.forEach { v in
            if let v = v as? NSStackView {
                let rows = v.arrangedSubviews
                h += v.edgeInsets.top + v.edgeInsets.bottom
                h += rows.map({ $0.bounds.height }).reduce(0, +)
                h += v.spacing * CGFloat(max(rows.count - 1, 0))
            } else {
                h += v.bounds.height
            }
        }
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }

    // MARK: - views

    private func initHero() -> NSView {
        let view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.heroHeight))
        view.heightAnchor.constraint(equalToConstant: self.heroHeight).isActive = true

        let big = NSTextField(labelWithAttributedString: self.speedString("0", unit: "KB/s"))
        big.frame = NSRect(x: self.heroSidePadding, y: 18, width: 200, height: 40)
        big.setAccessibilityLabel(localizedString("Downloading"))
        self.downloadField = big
        view.addSubview(big)

        let caption = NSTextField(labelWithString: localizedString("Downloading"))
        caption.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: self.heroSidePadding + 1, y: 4, width: 200, height: 13)
        view.addSubview(caption)

        let chips = NSStackView()
        chips.orientation = .vertical
        chips.alignment = .trailing
        chips.spacing = 5
        chips.frame = NSRect(x: self.frame.width - self.heroSidePadding - 160, y: 6, width: 160, height: 41)

        let uploadChip = self.makeChip()
        self.uploadChipView = uploadChip.0
        self.uploadChipField = uploadChip.1
        let latencyChip = self.makeChip()
        self.latencyChipView = latencyChip.0
        self.latencyChipField = latencyChip.1

        chips.addArrangedSubview(uploadChip.0)
        chips.addArrangedSubview(latencyChip.0)
        view.addSubview(chips)

        return view
    }

    private func speedString(_ value: String, unit: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ])
        text.append(NSAttributedString(string: " \(unit)", attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        return text
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

    private func initChart() -> NSView {
        let view = self.sectionView(localizedString("Usage history"), height: self.trendHeight)

        let chart = NetworkChartView(
            frame: NSRect(
                x: 8,
                y: self.sectionBottomPadding + self.trendMetaHeight + self.trendMetaGap,
                width: self.frame.width - 16,
                height: self.trendChartHeight
            ),
            num: self.chartHistory, reversedOrder: self.reverseOrderState, outColor: self.uploadColor, inColor: self.downloadColor,
            scale: self.chartScale,
            fixedScale: Double(self.chartFixedScaleSize.toBytes(self.chartFixedScale))
        )
        chart.setBase(self.base)
        chart.setSpeedUnit(self.speedUnit)
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
        if self.chartHistory >= 60 && self.chartHistory % 60 == 0 {
            return "\(localizedString("Last")) \(self.chartHistory/60) min"
        }
        return "\(localizedString("Last")) \(self.chartHistory) s"
    }

    private func initConnectivityChart() -> NSView {
        let view = self.sectionView(localizedString("Connectivity history"), height: self.connectivityHeight)

        let chart = GridChartView(
            frame: NSRect(
                x: 8,
                y: self.sectionBottomPadding,
                width: self.frame.width - 16,
                height: self.connectivityChartHeight
            ),
            grid: (30, 3)
        )
        self.connectivityChart = chart
        view.addSubview(chart)

        return view
    }

    private func initDetails() -> NSView {
        let button = PopupButton(toolTip: localizedString("Reset"), icon: "arrow.clockwise") { [weak self] in
            self?.resetTotalNetworkUsage()
        }
        let view = self.sectionView(localizedString("Details"), height: self.detailsHeight, button: button)
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
        let totalUpload = popupWithColorRow(container, color: self.uploadColor, title: "\(localizedString("Total upload")):", value: "0")
        nextRow()
        let totalDownload = popupWithColorRow(container, color: self.downloadColor, title: "\(localizedString("Total download")):", value: "0")

        self.uploadColorView = totalUpload.0
        self.totalUploadLabel = totalUpload.1
        self.totalUploadField = totalUpload.2

        self.downloadColorView = totalDownload.0
        self.totalDownloadLabel = totalDownload.1
        self.totalDownloadField = totalDownload.2

        nextRow()
        self.statusField = popupBadgeRow(container, title: "\(localizedString("Status")):").1
        nextRow()
        self.connectivityField = popupBadgeRow(container, title: "\(localizedString("Internet connection")):").1
        nextRow()
        self.latencyField = popupRow(container, title: "\(localizedString("Latency")):", value: "0 ms").1
        nextRow()
        self.jitterField = popupRow(container, title: "\(localizedString("Jitter")):", value: "0 ms").1

        [self.uploadColorView, self.downloadColorView].forEach {
            $0?.layer?.cornerRadius = 5
        }

        view.addSubview(container)

        return view
    }

    private func initInterface() -> NSView {
        let button = PopupButton(toolTip: localizedString("Details"), state: self.interfaceDetailsState) { [weak self] in
            self?.toggleInterfaceDetails()
        }
        let view = self.sectionStack(localizedString("Interface"), button: button)

        self.interfaceField = popupRow(view, title: "\(localizedString("Interface")):", value: localizedString("Unknown")).1
        self.interfaceStatusField = popupBadgeRow(view, title: "\(localizedString("Status")):").1
        self.macAddressField = popupRow(view, title: "\(localizedString("Physical address")):", value: localizedString("Unknown")).1
        self.macAddressField?.isSelectable = true

        let ssid = popupRow(view, title: "\(localizedString("Network")):", value: localizedString("Unknown"))
        let standard = popupRow(view, title: "\(localizedString("Standard")):", value: localizedString("Unavailable"))
        let channel = popupRow(view, title: "\(localizedString("Channel")):", value: localizedString("Unavailable"))
        let speed = popupRow(view, title: "\(localizedString("Speed")):", value: localizedString("Unknown"))

        self.ssidField = ssid.1
        self.standardField = standard.1
        self.channelField = channel.1
        self.interfaceSpeedField = speed.1

        self.ssidView = ssid.2
        self.standardView = standard.2
        self.channelView = channel.2
        self.interfaceSpeedView = speed.2

        if !self.interfaceDetailsState {
            self.standardView?.removeFromSuperview()
            self.channelView?.removeFromSuperview()
            self.interfaceSpeedView?.removeFromSuperview()
        }

        self.interfaceView = view
        return view
    }

    private func initAddress() -> NSView {
        let button = PopupButton(toolTip: localizedString("Refresh"), icon: "arrow.clockwise") { [weak self] in
            self?.refreshPublicIP()
        }
        let view = self.sectionStack(localizedString("Address"), button: button)

        self.localIPField = popupRow(view, title: "\(localizedString("Local IP")):", value: localizedString("Unknown")).1

        let ipV4 = popupRow(view, title: "\(localizedString("Public IP")):", value: localizedString("Unknown"))
        let ipV6 = popupRow(view, title: "\(localizedString("Public IP")):", value: localizedString("Unknown"))

        self.publicIPv4Field = ipV4.1
        self.publicIPv6Field = ipV6.1
        self.publicIPv4View = ipV4.2
        self.publicIPv6View = ipV6.2

        self.localIPField?.isSelectable = true
        self.publicIPv4Field?.isSelectable = true
        self.publicIPv6Field?.isSelectable = true

        if let valueView = self.publicIPv6Field {
            valueView.font = NSFont.systemFont(ofSize: 7, weight: .semibold)
            valueView.setFrameOrigin(NSPoint(x: valueView.frame.origin.x, y: -1))
        }

        ipV4.2.removeFromSuperview()
        ipV6.2.removeFromSuperview()

        self.addressView = view
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
            values: [(localizedString("Downloading"), self.downloadColor), (localizedString("Uploading"), self.uploadColor)],
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

    public override func appear() {
        self.replay(self.usageCache, render: self.renderUsage)
        self.replay(self.connectivityCache, render: self.renderConnectivity)
    }

    public override func disappear() {
        self.processes?.setLock(false)
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

    public func usageCallback(_ value: Network_Usage) {
        self.apply(value, to: self.usageCache, render: self.renderUsage)

        if let chart = self.chart {
            chart.setBase(self.base)
            chart.setSpeedUnit(self.speedUnit)
            chart.addValue(upload: Double(value.bandwidth.upload), download: Double(value.bandwidth.download))
        }
    }

    private func renderUsage(_ value: Network_Usage) {
        var resized = false

        let download = Units(bytes: value.bandwidth.download).getReadableTuple(base: self.base, unit: self.speedUnit)
        let upload = Units(bytes: value.bandwidth.upload).getReadableTuple(base: self.base, unit: self.speedUnit)

        self.downloadField?.attributedStringValue = self.speedString(download.0, unit: download.1)
        self.downloadField?.setAccessibilityLabel("\(localizedString("Downloading")): \(download.0) \(download.1)")

        self.uploadChipView?.isHidden = false
        self.uploadChipField?.attributedStringValue = self.chipString("↑ \(upload.0)", suffix: upload.1)
        self.uploadChipView?.toolTip = "\(localizedString("Uploading")): \(upload.0)\(upload.1)"

        if value.bandwidth.download > self.peakDownload {
            self.peakDownload = value.bandwidth.download
        }
        self.peakField?.stringValue = "\(localizedString("Peak")) ↓ \(Units(bytes: self.peakDownload).getReadableSpeed(base: self.base, unit: self.speedUnit))"

        self.totalUploadField?.stringValue = Units(bytes: value.total.upload).getReadableMemory()
        self.totalDownloadField?.stringValue = Units(bytes: value.total.download).getReadableMemory()

        let form = DateComponentsFormatter()
        form.maximumUnitCount = 2
        form.unitsStyle = .full
        form.allowedUnits = [.day, .hour, .minute]

        if let duration = form.string(from: self.lastReset, to: Date()) {
            self.totalUploadLabel?.toolTip = localizedString("Last reset", duration)
            self.totalDownloadLabel?.toolTip = localizedString("Last reset", duration)
        }

        if let interface = value.interface {
            self.interfaceField?.stringValue = "\(interface.displayName) (\(interface.BSDName)"
            if let cc = value.wifiDetails.countryCode {
                self.interfaceField?.stringValue += ", \(cc)"
            }
            self.interfaceField?.stringValue += ")"
            self.interfaceStatusField?.setStatus(interface.status)
            self.macAddressField?.stringValue = interface.address
            self.interfaceSpeedField?.stringValue = "\(Int(interface.transmitRate.rounded()))Mbps"
        } else {
            self.interfaceField?.stringValue = localizedString("Unknown")
            self.interfaceStatusField?.setStatus(nil)
            self.macAddressField?.stringValue = localizedString("Unknown")
            self.interfaceSpeedField?.stringValue = localizedString("Unknown")
        }

        if value.connectionType == .wifi {
            if let view = self.ssidView, view.superview == nil && value.wifiDetails.ssid != nil {
                self.interfaceView?.addArrangedSubview(view)
                resized = true
            }
            if self.interfaceDetailsState, let view = self.standardView, view.superview == nil && value.wifiDetails.standard != nil {
                self.interfaceView?.addArrangedSubview(view)
                resized = true
            }
            if self.interfaceDetailsState, let view = self.channelView, view.superview == nil && value.wifiDetails.channel != nil {
                self.interfaceView?.addArrangedSubview(view)
                resized = true
            }

            self.ssidField?.stringValue = value.wifiDetails.ssid ?? localizedString("Unknown")
            if let v = value.wifiDetails.RSSI {
                self.ssidField?.stringValue += " (\(v))"
            }
            self.standardField?.stringValue = value.wifiDetails.standard ?? localizedString("Unknown")
            self.channelField?.stringValue = value.wifiDetails.channel ?? localizedString("Unknown")

            var rssi = localizedString("Unknown")
            if let v = value.wifiDetails.RSSI {
                rssi = "\(v) dBm"
            }
            var noise = localizedString("Unknown")
            if let v = value.wifiDetails.noise {
                noise = "\(v) dBm"
            }

            let number = value.wifiDetails.channelNumber ?? localizedString("Unknown")
            let band = value.wifiDetails.channelBand ?? localizedString("Unknown")
            let width = value.wifiDetails.channelWidth ?? localizedString("Unknown")
            self.channelField?.toolTip = "RSSI: \(rssi)\nNoise: \(noise)\nChannel number: \(number)\nChannel band: \(band)\nChannel width: \(width)\n"
        } else {
            if self.ssidView?.superview != nil {
                self.ssidField?.stringValue = localizedString("Unavailable")
                self.ssidView?.removeFromSuperview()
                resized = true
            }
            if self.standardField?.superview != nil {
                self.standardField?.stringValue = localizedString("Unavailable")
                self.standardView?.removeFromSuperview()
                resized = true
            }
            if self.channelView?.superview != nil {
                self.channelField?.stringValue = localizedString("Unavailable")
                self.channelView?.removeFromSuperview()
                resized = true
            }
        }

        var privateIP = localizedString("Unknown")
        if let v4 = value.laddr.v4, !v4.isEmpty {
            privateIP = v4
        } else if let v6 = value.laddr.v6, !v6.isEmpty {
            privateIP = v6
        }
        if self.localIPField?.stringValue != privateIP {
            self.localIPField?.stringValue = privateIP
        }

        if let view = self.publicIPv4View {
            if let addr = value.raddr.v4 {
                if view.superview == nil {
                    self.addressView?.addArrangedSubview(view)
                    resized = true
                }
                var ip = addr
                if let cc = value.raddr.countryCode, !cc.isEmpty {
                    if self.emojiCCState, let flag = countryFlag(cc) {
                        ip += " \(flag)"
                    } else {
                        ip += " (\(cc))"
                    }
                    self.publicIPv4Field?.toolTip = cc
                }
                if self.publicIPv4Field?.stringValue != ip {
                    self.publicIPv4Field?.stringValue = ip
                }
            } else if view.superview != nil {
                view.removeFromSuperview()
                resized = true
                self.publicIPv4Field?.stringValue = localizedString("Unknown")
            }
        }

        if let view = self.publicIPv6View {
            if let addr = value.raddr.v6 {
                if view.superview == nil {
                    self.addressView?.addArrangedSubview(view)
                    resized = true
                }
                var ip = addr
                if let cc = value.raddr.countryCode {
                    if self.emojiCCState, let flag = countryFlag(cc) {
                        ip += " \(flag)"
                    } else {
                        ip += " (\(cc))"
                    }
                    self.publicIPv6Field?.toolTip = cc
                }
                if self.publicIPv6Field?.stringValue != ip {
                    self.publicIPv6Field?.stringValue = ip
                }
            } else if view.superview != nil {
                view.removeFromSuperview()
                resized = true
                self.publicIPv6Field?.stringValue = localizedString("Unknown")
            }
        }

        if self.interfaceDetailsState {
            if !value.dns.isEmpty {
                let servers = value.dns.joined(separator: "\n")

                if self.dnsServersField == nil || value.dns.count != self.dnsServersField?.stringValue.split(separator: "\n").count {
                    if let view = self.dnsServersView {
                        view.removeFromSuperview()
                    }
                    let view = popupRow(self.interfaceView, title: "\(localizedString("DNS Server")):", value: servers, multiline: true)
                    self.dnsServersField = view.1
                    self.dnsServersView = view.2
                    self.dnsServersField?.isSelectable = true
                }

                if self.dnsServersField?.stringValue != servers {
                    self.dnsServersField?.stringValue = servers
                }

                resized = true
            } else if let view = self.dnsServersView {
                view.removeFromSuperview()
                resized = true
            }
        }

        self.statusField?.setStatus(value.status)

        if resized {
            self.recalculateHeight()
        }

        self.chart?.display()
    }

    public func connectivityCallback(_ value: Network_Connectivity?) {
        if self.latency.count >= 90 {
            self.latency.remove(at: 0)
        }
        self.latency.append(value?.latency ?? 0)

        if self.jitter.count >= 90 {
            self.jitter.remove(at: 0)
        }
        self.jitter.append(value?.jitter ?? 0)

        self.apply(value, to: self.connectivityCache, render: self.renderConnectivity)

        if let value, let chart = self.connectivityChart {
            chart.addValue(value.status)
        }
    }

    private func renderConnectivity(_ value: Network_Connectivity?) {
        var latency = localizedString("Unknown")
        var jitter = localizedString("Unknown")

        if let v = value {
            if v.status && !self.latency.isEmpty {
                let average = (self.latency.reduce(0, +) / Double(self.latency.count)).rounded(toPlaces: 2)
                latency = "\(average) ms"

                self.latencyChipView?.isHidden = false
                self.latencyChipField?.attributedStringValue = self.chipString("\(average)", suffix: "ms")
                self.latencyChipView?.toolTip = "\(localizedString("Latency")): \(average) ms"
            }
            if v.status && !self.jitter.isEmpty {
                jitter = "\((self.jitter.reduce(0, +) / Double(self.jitter.count)).rounded(toPlaces: 2)) ms"
            }
        }
        self.latencyField?.stringValue = latency
        self.jitterField?.stringValue = jitter

        self.connectivityField?.setStatus(value?.status)
        self.connectivityChart?.display()
    }

    public func processCallback(_ list: [Network_Process]) {
        DispatchQueue.main.async(execute: {
            if !(self.window?.isVisible ?? false) && self.processesInitialized {
                return
            }
            let list = list.map{ $0 }
            if list.count != self.processes?.count { self.processes?.clear() }

            let maxTraffic = list.map({ $0.download + $0.upload }).max() ?? 0
            for i in 0..<list.count {
                let process = list[i]
                let upload = Units(bytes: Int64(process.upload)).getReadableSpeed(base: self.base, unit: self.speedUnit)
                let download = Units(bytes: Int64(process.download)).getReadableSpeed(base: self.base, unit: self.speedUnit)
                let share = maxTraffic > 0 ? Double(process.download + process.upload) / Double(maxTraffic) : 0
                self.processes?.set(i, process, [download, upload], share: share)
            }

            self.processesInitialized = true
        })
    }

    public func resetConnectivityView() {
        self.connectivityField?.setStatus(nil)
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
            PreferencesRow(localizedString("Color of download"), component: colorSelectView(
                action: #selector(self.toggleDownloadColor),
                items: SColor.allColors,
                selected: self.downloadColorState.key
            )),
            PreferencesRow(localizedString("Color of upload"), component: colorSelectView(
                action: #selector(self.toggleUploadColor),
                items: SColor.allColors,
                selected: self.uploadColorState.key
            ))
        ]))

        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Reverse order"), component: switchView(
                action: #selector(self.toggleReverseOrder),
                state: self.reverseOrderState
            ))
        ]))

        self.chartPrefSection = PreferencesSection([
            PreferencesRow(localizedString("Chart history"), component: selectView(
                action: #selector(self.togglechartHistory),
                items: LineChartHistory,
                selected: "\(self.chartHistory)"
            )),
            PreferencesRow(localizedString("Main chart scaling"), component: selectView(
                action: #selector(self.toggleChartScale),
                items: Scale.allCases,
                selected: self.chartScale.key
            )),
            PreferencesRow(localizedString("Scale value"), component: StepperInput(
                self.chartFixedScale, range: NSRange(location: 1, length: 1023),
                unit: self.chartFixedScaleSize.key, units: SizeUnit.allCases,
                callback: self.toggleFixedScale, unitCallback: self.toggleFixedScaleSize
            ))
        ])
        view.addArrangedSubview(self.chartPrefSection!)
        self.chartPrefSection?.setRowVisibility(2, newState: self.chartScale == .fixed)

        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Public IP"), component: switchView(
                action: #selector(self.togglePublicIP),
                state: self.publicIPState
            )),
            PreferencesRow(localizedString("Show country code instead of emoji"), component: switchView(
                action: #selector(self.toggleEmojiCC),
                state: !self.emojiCCState
            ))
        ]))

        return view
    }

    @objc private func toggleUploadColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.uploadColorState = SColor.fromString(key, defaultValue: self.uploadColorState)
        Store.shared.set(key: "\(self.title)_uploadColor", value: self.uploadColorState.key)
        if let color = self.uploadColorState.additional as? NSColor {
            self.processes?.setColor(1, color)
            self.uploadColorView?.layer?.backgroundColor = color.cgColor
            self.chart?.setColors(out: color)
        }
    }
    @objc private func toggleDownloadColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.downloadColorState = SColor.fromString(key, defaultValue: self.downloadColorState)
        Store.shared.set(key: "\(self.title)_downloadColor", value: self.downloadColorState.key)
        if let color = self.downloadColorState.additional as? NSColor {
            self.processes?.setColor(0, color)
            self.downloadColorView?.layer?.backgroundColor = color.cgColor
            self.chart?.setColors(in: color)
        }
    }
    @objc private func toggleReverseOrder(_ sender: NSControl) {
        self.reverseOrderState = controlState(sender)
        self.chart?.setReverseOrder(self.reverseOrderState)
        Store.shared.set(key: "\(self.title)_reverseOrder", value: self.reverseOrderState)
        self.display()
    }
    @objc private func togglechartHistory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.chartHistory = value
        Store.shared.set(key: "\(self.title)_chartHistory", value: value)
        self.chart?.reinit(self.chartHistory)
        self.historyWindowField?.stringValue = self.historyWindowString()
    }
    @objc private func toggleChartScale(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let value = Scale.allCases.first(where: { $0.key == key }) else { return }
        self.chartScale = value
        self.chart?.setScale(self.chartScale, Double(self.chartFixedScaleSize.toBytes(self.chartFixedScale)))
        self.chartPrefSection?.setRowVisibility(2, newState: self.chartScale == .fixed)
        Store.shared.set(key: "\(self.title)_chartScale", value: key)
        self.display()
    }
    @objc private func togglePublicIP(_ sender: NSControl) {
        self.publicIPState = controlState(sender)
        Store.shared.set(key: "\(self.title)_publicIP", value: self.publicIPState)

        DispatchQueue.main.async(execute: {
            if !self.publicIPState {
                self.addressView?.removeFromSuperview()
            } else if let view = self.addressView, let interface = self.interfaceView,
                      let index = self.arrangedSubviews.firstIndex(of: interface) {
                self.insertArrangedSubview(view, at: index + 1)
            }
            self.recalculateHeight()
        })
    }
    @objc private func toggleFixedScale(_ newValue: Int) {
        self.chart?.setScale(self.chartScale, Double(self.chartFixedScaleSize.toBytes(newValue)))
        Store.shared.set(key: "\(self.title)_chartFixedScale", value: newValue)
    }
    private func toggleFixedScaleSize(_ newValue: KeyValue_p) {
        guard let newUnit = newValue as? SizeUnit else { return }
        self.chartFixedScaleSize = newUnit
        Store.shared.set(key: "\(self.title)_chartFixedScaleSize", value: self.chartFixedScaleSize.key)
        self.display()
    }
    @objc private func toggleInterfaceDetails() {
        self.interfaceDetailsState = !self.interfaceDetailsState
        Store.shared.set(key: "\(self.title)_interfaceDetails", value: self.interfaceDetailsState)

        if !self.interfaceDetailsState {
            self.standardView?.removeFromSuperview()
            self.channelView?.removeFromSuperview()
            self.interfaceSpeedView?.removeFromSuperview()
            self.dnsServersView?.removeFromSuperview()
        } else {
            if let view = self.standardView, view.superview == nil && self.standardField?.stringValue != localizedString("Unavailable") {
                self.interfaceView?.addArrangedSubview(view)
            }
            if let view = self.channelView, view.superview == nil && self.channelField?.stringValue != localizedString("Unavailable") {
                self.interfaceView?.addArrangedSubview(view)
            }
            if let view = self.interfaceSpeedView, view.superview == nil {
                self.interfaceView?.addArrangedSubview(view)
            }
            if let view = self.dnsServersView, view.superview == nil {
                self.interfaceView?.addArrangedSubview(view)
            }
        }

        self.recalculateHeight()
    }
    @objc private func toggleEmojiCC(_ sender: NSControl) {
        self.emojiCCState = !controlState(sender)
        Store.shared.set(key: "\(self.title)_emojiCC", value: self.emojiCCState)
    }

    // MARK: - helpers

    @objc private func refreshPublicIP() {
        NotificationCenter.default.post(name: .refreshPublicIP, object: nil, userInfo: nil)
        self.localIPField?.stringValue = localizedString("Updating...")
        self.publicIPv4Field?.stringValue = localizedString("Updating...")
        self.publicIPv6Field?.stringValue = localizedString("Updating...")
    }

    @objc private func resetTotalNetworkUsage() {
        NotificationCenter.default.post(name: .resetTotalNetworkUsage, object: nil, userInfo: nil)
        self.totalUploadField?.stringValue = Units(bytes: 0).getReadableMemory()
        self.totalDownloadField?.stringValue = Units(bytes: 0).getReadableMemory()
        self.lastReset = Date()
    }

    @objc private func resetTotalNetworkUsageCallback() {
        self.lastReset = Date()
    }
}
