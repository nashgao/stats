//
//  Dashboard.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 24/12/2020.
//  Using Swift 6.0.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

private extension TelemetryMetric {
    var title: String {
        switch self {
        case .cpu: return localizedString("CPU")
        case .memory: return localizedString("Memory")
        case .disk: return localizedString("Disk")
        case .network: return localizedString("Network")
        case .battery: return localizedString("Battery")
        case .temperature: return localizedString("Temperature")
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "arrow.up.arrow.down"
        case .battery: return "battery.75percent"
        case .temperature: return "thermometer.medium"
        }
    }
}

private enum TelemetryHealth: Int, Comparable {
    case waiting
    case nominal
    case unavailable
    case warning
    case critical

    static func < (lhs: TelemetryHealth, rhs: TelemetryHealth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .waiting: return localizedString("Waiting")
        case .nominal: return localizedString("Nominal")
        case .unavailable: return localizedString("Unavailable")
        case .warning: return localizedString("Elevated")
        case .critical: return localizedString("Critical")
        }
    }

    var color: NSColor {
        switch self {
        case .waiting, .unavailable: return Constants.Design.textSecondary
        case .nominal: return Constants.Design.statusHealthy
        case .warning: return Constants.Design.statusAttention
        case .critical: return Constants.Design.statusCritical
        }
    }
}

private func health(for sample: TelemetrySample) -> TelemetryHealth {
    guard sample.isAvailable else { return .unavailable }

    switch sample.metric {
    case .cpu:
        if sample.value >= 0.9 { return .critical }
        if sample.value >= 0.75 { return .warning }
    case .memory:
        if sample.value >= 0.95 { return .critical }
        if sample.value >= 0.8 { return .warning }
    case .disk:
        if sample.value >= 0.95 { return .critical }
        if sample.value >= 0.85 { return .warning }
    case .battery:
        if (sample.secondaryValue ?? 0) > 0 { return .nominal }
        if sample.value <= 0.1 { return .critical }
        if sample.value <= 0.2 { return .warning }
    case .temperature:
        if sample.value >= 95 { return .critical }
        if sample.value >= 80 { return .warning }
    case .network:
        break
    }

    return .nominal
}

private final class TelemetryTrendView: NSView {
    private let metric: TelemetryMetric
    private var values: [Double] = []

    init(metric: TelemetryMetric) {
        self.metric = metric
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func add(_ sample: TelemetrySample) {
        let value = sample.metric == .network
            ? sample.value + (sample.secondaryValue ?? 0)
            : sample.value
        self.values.append(max(value, 0))
        if self.values.count > 60 {
            self.values.removeFirst(self.values.count - 60)
        }
        self.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard self.values.count > 1 else { return }

        let graphRect = self.bounds.insetBy(dx: 0, dy: Constants.Design.space1)
        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: graphRect.minX, y: graphRect.midY))
        guide.line(to: NSPoint(x: graphRect.maxX, y: graphRect.midY))
        guide.lineWidth = Constants.Design.hairlineWidth
        Constants.Design.separatorSubtle.withAlphaComponent(Constants.Design.separatorOpacity).setStroke()
        guide.stroke()

        let maximum: Double
        switch self.metric {
        case .network:
            maximum = max(self.values.max() ?? 1, 1)
        case .temperature:
            maximum = 110
        default:
            maximum = 1
        }

        let path = NSBezierPath()
        for (index, value) in self.values.enumerated() {
            let progress = CGFloat(index) / CGFloat(self.values.count - 1)
            let normalized = min(max(value / maximum, 0), 1)
            let point = NSPoint(
                x: graphRect.minX + (graphRect.width * progress),
                y: graphRect.minY + (graphRect.height * CGFloat(normalized))
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.lineWidth = Constants.Design.trendLineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        Constants.Design.accentPrimary.setStroke()
        path.stroke()
    }
}

private final class TelemetryMetricCard: NSView {
    private let metric: TelemetryMetric
    private let valueField = TextView()
    private let detailField = TextView()
    private let statusField = TextView()
    private let trend: TelemetryTrendView

    init(metric: TelemetryMetric) {
        self.metric = metric
        self.trend = TelemetryTrendView(metric: metric)
        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.backgroundColor = Constants.Design.surfaceSecondary.cgColor
        self.layer?.cornerRadius = Constants.Design.sectionRadius
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.group)

        let icon = NSImageView(image: NSImage(
            systemSymbolName: metric.symbolName,
            accessibilityDescription: metric.title
        ) ?? NSImage())
        icon.contentTintColor = Constants.Design.textSecondary
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Constants.Design.bodyEmphasisFont.pointSize,
            weight: .medium
        )
        icon.widthAnchor.constraint(equalToConstant: Constants.Design.space5).isActive = true

        let titleField = TextView()
        titleField.font = Constants.Design.bodyEmphasisFont
        titleField.stringValue = metric.title

        self.statusField.font = Constants.Design.captionFont
        self.statusField.textColor = TelemetryHealth.waiting.color
        self.statusField.stringValue = TelemetryHealth.waiting.label
        self.statusField.alignment = .right

        let header = NSStackView(views: [icon, titleField, NSView(), self.statusField])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = Constants.Design.space1

        self.valueField.font = Constants.Design.metricValueFont
        self.valueField.stringValue = "—"
        self.detailField.font = Constants.Design.secondaryFont
        self.detailField.textColor = Constants.Design.textSecondary
        self.detailField.stringValue = localizedString("Waiting for data")
        self.detailField.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [header, self.valueField, self.detailField, self.trend])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = Constants.Design.space1
        stack.edgeInsets = NSEdgeInsets(
            top: Constants.Design.space3,
            left: Constants.Design.space4,
            bottom: Constants.Design.space3,
            right: Constants.Design.space4
        )
        self.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            header.widthAnchor.constraint(equalTo: self.widthAnchor, constant: -Constants.Design.space8),
            self.valueField.widthAnchor.constraint(equalTo: self.widthAnchor, constant: -Constants.Design.space8),
            self.detailField.widthAnchor.constraint(equalTo: self.widthAnchor, constant: -Constants.Design.space8),
            self.trend.widthAnchor.constraint(equalTo: self.widthAnchor, constant: -Constants.Design.space8),
            self.trend.heightAnchor.constraint(equalToConstant: Constants.Design.metricTrendHeight),
            self.heightAnchor.constraint(equalToConstant: Constants.Design.metricCardHeight),
            self.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.Design.metricCardMinimumWidth)
        ])

        self.setAccessibilityLabel("\(metric.title), \(localizedString("Waiting for data"))")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        self.layer?.backgroundColor = Constants.Design.surfaceSecondary.cgColor
    }

    func update(_ sample: TelemetrySample) {
        let currentHealth = health(for: sample)
        self.valueField.stringValue = sample.displayValue
        self.detailField.stringValue = sample.detail.isEmpty ? currentHealth.label : sample.detail
        self.detailField.toolTip = self.detailField.stringValue
        self.statusField.stringValue = currentHealth.label
        self.statusField.textColor = currentHealth.color
        self.trend.add(sample)
        self.setAccessibilityLabel(
            "\(self.metric.title), \(sample.displayValue), \(self.detailField.stringValue), \(currentHealth.label)"
        )
    }
}

private final class HealthRibbonItem: NSView {
    private let metric: TelemetryMetric
    private let valueField = TextView()
    private let statusField = TextView()

    init(metric: TelemetryMetric) {
        self.metric = metric
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.group)

        let icon = NSImageView(image: NSImage(
            systemSymbolName: metric.symbolName,
            accessibilityDescription: metric.title
        ) ?? NSImage())
        icon.contentTintColor = Constants.Design.textSecondary
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Constants.Design.captionFont.pointSize,
            weight: .medium
        )
        icon.widthAnchor.constraint(equalToConstant: Constants.Design.space4).isActive = true

        let titleField = TextView()
        titleField.font = Constants.Design.captionFont
        titleField.stringValue = metric.title
        titleField.lineBreakMode = .byTruncatingTail

        let titleRow = NSStackView(views: [icon, titleField])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = Constants.Design.space1

        self.valueField.font = Constants.Design.compactMetricValueFont
        self.valueField.stringValue = "—"
        self.statusField.font = Constants.Design.captionFont
        self.statusField.textColor = TelemetryHealth.waiting.color
        self.statusField.stringValue = TelemetryHealth.waiting.label

        let stack = NSStackView(views: [titleRow, self.valueField, self.statusField])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Constants.Design.space1
        self.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.heightAnchor.constraint(equalToConstant: Constants.Design.healthRibbonItemHeight)
        ])

        self.setAccessibilityLabel("\(metric.title), \(localizedString("Waiting for data"))")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ sample: TelemetrySample) {
        let currentHealth = health(for: sample)
        self.valueField.stringValue = sample.displayValue
        self.statusField.stringValue = currentHealth.label
        self.statusField.textColor = currentHealth.color
        self.setAccessibilityLabel(
            "\(self.metric.title), \(sample.displayValue), \(currentHealth.label)"
        )
    }
}

private final class HealthRibbon: NSView {
    private let metrics: [TelemetryMetric] = [.cpu, .memory, .disk, .network, .temperature, .battery]
    private var items: [TelemetryMetric: HealthRibbonItem] = [:]
    private var states: [TelemetryMetric: TelemetryHealth] = [:]

    var highestHealth: TelemetryHealth {
        self.states.values.max() ?? .waiting
    }

    var hasWaitingMetrics: Bool {
        self.states.count < self.metrics.count
    }

    init() {
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.backgroundColor = Constants.Design.surfaceSecondary.cgColor
        self.layer?.cornerRadius = Constants.Design.sectionRadius

        var rows: [[NSView]] = [[], []]
        for (index, metric) in self.metrics.enumerated() {
            let item = HealthRibbonItem(metric: metric)
            self.items[metric] = item
            rows[index / Constants.Design.healthRibbonColumns].append(item)
        }

        let grid = NSGridView(views: rows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.columnSpacing = Constants.Design.space4
        grid.rowSpacing = Constants.Design.space2
        grid.xPlacement = .fill
        grid.yPlacement = .center
        for index in 0..<grid.numberOfColumns {
            grid.column(at: index).xPlacement = .fill
        }
        for index in 0..<grid.numberOfRows {
            grid.row(at: index).height = Constants.Design.healthRibbonItemHeight
        }
        if let firstItem = self.items[self.metrics[0]] {
            for metric in self.metrics.dropFirst() {
                self.items[metric]?.widthAnchor.constraint(equalTo: firstItem.widthAnchor).isActive = true
            }
        }
        self.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: Constants.Design.space3),
            grid.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -Constants.Design.space3),
            grid.topAnchor.constraint(equalTo: self.topAnchor, constant: Constants.Design.space2),
            grid.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -Constants.Design.space2),
            self.heightAnchor.constraint(equalToConstant: Constants.Design.healthRibbonHeight)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        self.layer?.backgroundColor = Constants.Design.surfaceSecondary.cgColor
    }

    func update(_ sample: TelemetrySample) {
        guard let item = self.items[sample.metric] else { return }
        item.update(sample)
        self.states[sample.metric] = health(for: sample)
    }
}

class Dashboard: NSStackView {
    private let headlineField = TextView()
    private let healthStatusField = TextView()
    private let lastUpdateField = TextView()
    private let uptimeSummaryField = TextView()
    private let uptimeField = TextView()
    private let healthRibbon = HealthRibbon()
    private let cpuCard = TelemetryMetricCard(metric: .cpu)
    private let memoryCard = TelemetryMetricCard(metric: .memory)
    private let diskCard = TelemetryMetricCard(metric: .disk)
    private let networkCard = TelemetryMetricCard(metric: .network)
    private let temperatureCard = TelemetryMetricCard(metric: .temperature)
    private let batteryCard = TelemetryMetricCard(metric: .battery)
    private let cardsContainer = NSStackView()
    private let detailsButton = NSButton()
    private let hardwareSection = NSStackView()
    private var samples: [TelemetryMetric: TelemetrySample] = [:]
    internal private(set) var cardColumnCount = 0

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()

    init() {
        super.init(frame: .zero)
        self.orientation = .vertical
        self.alignment = .width

        let scrollView = ScrollableStackView(orientation: .vertical)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.stackView.alignment = .width
        scrollView.stackView.edgeInsets = NSEdgeInsets(
            top: Constants.Design.space3,
            left: Constants.Design.space4,
            bottom: Constants.Design.space4,
            right: Constants.Design.space4
        )
        scrollView.stackView.spacing = Constants.Design.space3
        func addContent(_ view: NSView) {
            view.translatesAutoresizingMaskIntoConstraints = false
            scrollView.stackView.addArrangedSubview(view)
            view.widthAnchor.constraint(
                equalTo: scrollView.stackView.widthAnchor,
                constant: -Constants.Design.space8
            ).isActive = true
        }

        addContent(self.heroView())

        let healthTitle = self.sectionTitle(
            localizedString("Live system health"),
            subtitle: localizedString("Current state from the same readers that power the menu bar")
        )
        addContent(healthTitle)
        addContent(self.healthRibbon)

        addContent(self.sectionTitle(localizedString("Live activity")))
        self.configureCardsContainer()
        addContent(self.cardsContainer)

        self.configureHardwareSection()
        addContent(self.detailsButton)
        addContent(self.hardwareSection)

        self.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
        self.updateUptime()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(receiveTelemetry),
            name: .telemetrySample,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowOpens),
            name: .openModuleSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowOpens),
            name: .toggleSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(moduleStateChanged),
            name: .toggleModule,
            object: nil
        )
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        self.adapt(to: self.bounds.width)
    }

    internal func adapt(to contentWidth: CGFloat) {
        let columns = contentWidth >= Constants.Design.dashboardThreeColumnMinimumWidth
            ? 3
            : (contentWidth >= Constants.Design.dashboardTwoColumnMinimumWidth ? 2 : 1)
        self.updateCardLayout(columns: columns)
    }

    private func heroView() -> NSView {
        let deviceImage = NSImageView(image: SystemKit.shared.device.model.icon)
        deviceImage.imageScaling = .scaleProportionallyDown
        deviceImage.widthAnchor.constraint(equalToConstant: Constants.Design.deviceIconSize).isActive = true
        deviceImage.heightAnchor.constraint(equalToConstant: Constants.Design.deviceIconSize).isActive = true

        self.headlineField.font = Constants.Design.healthHeadlineFont
        self.headlineField.stringValue = localizedString("System health")
        self.healthStatusField.font = Constants.Design.bodyEmphasisFont
        self.healthStatusField.textColor = Constants.Design.textSecondary
        self.healthStatusField.stringValue = localizedString("Waiting for live samples")

        let osName = SystemKit.shared.device.os?.name ?? localizedString("Unknown")
        let osVersion = SystemKit.shared.device.os?.version.getFullVersion() ?? ""
        let identityField = TextView()
        identityField.font = Constants.Design.secondaryFont
        identityField.textColor = Constants.Design.textSecondary
        identityField.stringValue = "\(SystemKit.shared.device.model.name) · macOS \(osName) \(osVersion)"
        identityField.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [self.headlineField, self.healthStatusField, identityField])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = Constants.Design.space1

        self.uptimeSummaryField.font = Constants.Design.secondaryEmphasisFont
        self.uptimeSummaryField.alignment = .right
        self.lastUpdateField.font = Constants.Design.captionRegularFont
        self.lastUpdateField.textColor = Constants.Design.textSecondary
        self.lastUpdateField.alignment = .right
        self.lastUpdateField.stringValue = localizedString("No live sample yet")

        let timing = NSStackView(views: [self.uptimeSummaryField, self.lastUpdateField])
        timing.orientation = .vertical
        timing.alignment = .trailing
        timing.spacing = Constants.Design.space1

        let view = NSStackView(views: [deviceImage, labels, NSView(), timing])
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = Constants.Design.space3
        view.edgeInsets = NSEdgeInsets(
            top: Constants.Design.space2,
            left: 0,
            bottom: Constants.Design.space2,
            right: 0
        )
        return view
    }

    private func sectionTitle(_ title: String, subtitle: String? = nil) -> NSView {
        let titleField = TextView()
        titleField.font = Constants.Design.sectionTitleFont
        titleField.stringValue = title

        guard let subtitle else { return titleField }
        let subtitleField = TextView()
        subtitleField.font = Constants.Design.captionRegularFont
        subtitleField.textColor = Constants.Design.textSecondary
        subtitleField.stringValue = subtitle
        let stack = NSStackView(views: [titleField, subtitleField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Constants.Design.space1
        return stack
    }

    private var metricCards: [TelemetryMetricCard] {
        [
            self.cpuCard,
            self.memoryCard,
            self.diskCard,
            self.networkCard,
            self.temperatureCard,
            self.batteryCard
        ]
    }

    private func configureCardsContainer() {
        self.cardsContainer.orientation = .vertical
        self.cardsContainer.alignment = .width
        self.cardsContainer.spacing = Constants.Design.space3
        self.updateCardLayout(columns: 1)
    }

    private func updateCardLayout(columns: Int) {
        guard columns != self.cardColumnCount else { return }
        self.cardColumnCount = columns

        for card in self.metricCards {
            if let stack = card.superview as? NSStackView {
                stack.removeArrangedSubview(card)
            }
            card.removeFromSuperview()
        }
        for row in self.cardsContainer.arrangedSubviews {
            self.cardsContainer.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        for start in stride(from: 0, to: self.metricCards.count, by: columns) {
            let end = min(start + columns, self.metricCards.count)
            let row = NSStackView(views: Array(self.metricCards[start..<end]))
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.alignment = .top
            row.spacing = Constants.Design.space3
            self.cardsContainer.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: self.cardsContainer.widthAnchor).isActive = true
        }
    }

    private func configureHardwareSection() {
        self.detailsButton.title = localizedString("Hardware details")
        self.detailsButton.bezelStyle = .inline
        self.detailsButton.setButtonType(.pushOnPushOff)
        self.detailsButton.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: localizedString("Collapsed")
        )
        self.detailsButton.imagePosition = .imageLeading
        self.detailsButton.font = Constants.Design.bodyEmphasisFont
        self.detailsButton.alignment = .left
        self.detailsButton.target = self
        self.detailsButton.action = #selector(toggleHardwareDetails)
        self.detailsButton.focusRingType = .default
        self.detailsButton.setAccessibilityLabel(localizedString("Hardware details"))
        self.detailsButton.setAccessibilityValue(localizedString("Collapsed"))
        self.detailsButton.heightAnchor.constraint(equalToConstant: Constants.Design.minimumControlSize).isActive = true

        self.uptimeField.font = Constants.Design.bodyFont
        self.uptimeField.alignment = .right

        self.hardwareSection.orientation = .vertical
        self.hardwareSection.alignment = .width
        self.hardwareSection.spacing = Constants.Design.space3
        self.hardwareSection.addArrangedSubview(PreferencesSection([
            PreferencesRow(
                localizedString("Processor"),
                component: textView(self.processorValue, alignment: .right)
            ),
            PreferencesRow(
                localizedString("Memory"),
                component: textView(self.memoryValue, alignment: .right)
            ),
            PreferencesRow(
                localizedString("Graphics"),
                component: textView(self.graphicsValue, alignment: .right)
            ),
            PreferencesRow(
                localizedString("Disks"),
                component: textView(self.disksValue, alignment: .right)
            ),
            PreferencesRow(
                localizedString("Display"),
                component: textView(self.displaysValue, alignment: .right)
            )
        ]))
        self.hardwareSection.addArrangedSubview(PreferencesSection([
            PreferencesRow(
                localizedString("Model identifier"),
                component: textView(SystemKit.shared.device.model.id)
            ),
            PreferencesRow(
                localizedString("Production year"),
                component: textView("\(SystemKit.shared.device.model.year)")
            ),
            PreferencesRow(
                localizedString("Serial number"),
                component: textView(SystemKit.shared.device.serialNumber ?? localizedString("Unknown"))
            ),
            PreferencesRow(localizedString("Uptime"), component: self.uptimeField)
        ]))
        self.hardwareSection.isHidden = true
    }

    @objc private func toggleHardwareDetails() {
        let expanded = self.detailsButton.state == .on
        self.hardwareSection.isHidden = !expanded
        self.detailsButton.image = NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: localizedString(expanded ? "Expanded" : "Collapsed")
        )
        self.detailsButton.setAccessibilityValue(localizedString(expanded ? "Expanded" : "Collapsed"))
        self.window?.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func receiveTelemetry(_ notification: Notification) {
        guard let sample = notification.object as? TelemetrySample else { return }
        if Thread.isMainThread {
            self.apply(sample)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.apply(sample)
            }
        }
    }

    private func apply(_ sample: TelemetrySample) {
        self.samples[sample.metric] = sample
        self.healthRibbon.update(sample)
        switch sample.metric {
        case .cpu: self.cpuCard.update(sample)
        case .memory: self.memoryCard.update(sample)
        case .disk: self.diskCard.update(sample)
        case .network: self.networkCard.update(sample)
        case .battery: self.batteryCard.update(sample)
        case .temperature: self.temperatureCard.update(sample)
        }
        self.lastUpdateField.stringValue = "\(localizedString("Updated")) \(self.timeFormatter.string(from: sample.timestamp))"
        self.updateOverallHealth()
    }

    private func updateOverallHealth() {
        let currentHealth = self.healthRibbon.highestHealth
        if self.healthRibbon.hasWaitingMetrics && currentHealth <= .nominal {
            self.healthStatusField.textColor = Constants.Design.textSecondary
            self.healthStatusField.stringValue = localizedString("Live metrics updating")
        } else {
            self.healthStatusField.textColor = currentHealth.color
            switch currentHealth {
            case .waiting:
                self.healthStatusField.stringValue = localizedString("Waiting for live samples")
            case .nominal:
                self.healthStatusField.stringValue = localizedString("All monitored systems nominal")
            case .unavailable:
                self.healthStatusField.stringValue = localizedString("Some live metrics are unavailable")
            case .warning:
                self.healthStatusField.stringValue = localizedString("One or more metrics need attention")
            case .critical:
                self.healthStatusField.stringValue = localizedString("Critical system pressure detected")
            }
        }
        self.headlineField.setAccessibilityLabel(
            "\(localizedString("System health")), \(self.healthStatusField.stringValue)"
        )
    }

    private func updateUptime() {
        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .hour, .minute]

        let uptime: String
        if let bootDate = SystemKit.shared.device.bootDate,
           let duration = formatter.string(from: bootDate, to: Date()) {
            uptime = duration
        } else {
            uptime = localizedString("Unknown")
        }
        self.uptimeField.stringValue = uptime
        self.uptimeSummaryField.stringValue = "\(localizedString("Uptime")) · \(uptime)"
    }

    @objc private func windowOpens(_ notification: Notification) {
        guard let moduleName = notification.userInfo?["module"] as? String,
              moduleName == "Dashboard" || moduleName == "Combined modules" else { return }
        self.updateUptime()
        self.reconcileModuleAvailability()
    }

    @objc private func moduleStateChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.reconcileModuleAvailability()
        }
    }

    private func reconcileModuleAvailability() {
        let mapping: [(metric: TelemetryMetric, module: String)] = [
            (.cpu, "CPU"),
            (.memory, "RAM"),
            (.disk, "Disk"),
            (.network, "Network"),
            (.battery, "Battery"),
            (.temperature, "Sensors")
        ]
        for item in mapping {
            guard let module = modules.first(where: { $0.config.name == item.module }),
                  !module.enabled || !module.available else { continue }
            self.apply(TelemetrySample(
                metric: item.metric,
                value: 0,
                displayValue: "—",
                detail: localizedString(module.available ? "Module disabled" : "Module unavailable"),
                isAvailable: false
            ))
        }
    }

    private var processorValue: String {
        guard let cpu = SystemKit.shared.device.info.cpu else {
            return localizedString("Unknown")
        }
        var details: [String] = []
        if let cores = cpu.physicalCores {
            details.append(localizedString("Number of cores", "\(cores)"))
        }
        if let threads = cpu.logicalCores {
            details.append(localizedString("Number of threads", "\(threads)"))
        }
        return [cpu.name, details.joined(separator: ", ")]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private var memoryValue: String {
        guard let dimms = SystemKit.shared.device.info.ram?.dimms else {
            return localizedString("Unknown")
        }
        return dimms.map { dimm in
            [dimm.size, dimm.speed, dimm.type]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private var graphicsValue: String {
        guard let gpus = SystemKit.shared.device.info.gpu else {
            return localizedString("Unknown")
        }
        return gpus.map { gpu in
            var value = gpu.name ?? localizedString("Unknown")
            if let cores = gpu.cores {
                value += " (\(localizedString("Number of cores", "\(cores)")))"
            } else if let vram = gpu.vram {
                value += " (\(vram))"
            }
            return value
        }.joined(separator: "\n")
    }

    private var disksValue: String {
        guard let disks = SystemKit.shared.device.info.disk else {
            return localizedString("Unknown")
        }
        return disks.map { disk in
            var value = disk.name ?? localizedString("Unknown")
            if let size = disk.size {
                value += " (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))"
            }
            return value
        }.joined(separator: "\n")
    }

    private var displaysValue: String {
        guard let displays = SystemKit.shared.device.display else {
            return localizedString("Unknown")
        }
        return displays.map { display in
            var value = display.name ?? localizedString("Unknown")
            var details: [String] = []
            if let resolution = display.resolution {
                details.append("\(Int(resolution.width))×\(Int(resolution.height))")
            }
            if let refreshRate = display.refreshRate {
                details.append("\(Int(refreshRate.rounded())) Hz")
            }
            if !details.isEmpty {
                value += "\n\(details.joined(separator: ", "))"
            }
            return value
        }.joined(separator: "\n")
    }
}
