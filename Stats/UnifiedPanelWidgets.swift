//
//  UnifiedPanelWidgets.swift
//  Stats
//
//  Self-contained detail widgets for the unified panel, split out of
//  UnifiedPanelContent to keep that file within the lint budget:
//  mini metrics, pills, grammar detail rows, and the top-processes
//  block. All frame-based, design-E grammar styling.
//

import Cocoa
import Kit

final class UnifiedMiniMetric: NSView {
    private let track = NSView()
    private let fill = NSView()
    private let valueField = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
    
    override var isFlipped: Bool { true }
    
    init(label: String, value: String, fraction: Double, color: NSColor? = nil) {
        super.init(frame: .zero)
        let labelField = unifiedLabel(label, font: .systemFont(ofSize: 10, weight: .regular), color: .tertiaryLabelColor)
        self.addSubview(labelField)
        self.addSubview(self.valueField)
        self.track.wantsLayer = true
        self.track.layer?.cornerRadius = 2
        self.fill.wantsLayer = true
        self.fill.layer?.cornerRadius = 2
        self.track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
        self.fill.layer?.backgroundColor = (color ?? .controlAccentColor).cgColor
        self.addSubview(self.track)
        self.addSubview(self.fill)
        labelField.frame = NSRect(x: 0, y: 0, width: 96, height: 12)
        self.valueField.frame = NSRect(x: 0, y: 14, width: 96, height: 12)
        self.valueField.stringValue = value
        self.track.frame = NSRect(x: 0, y: 28, width: 96, height: 4)
        self.fill.frame = NSRect(x: 0, y: 28, width: 96 * CGFloat(min(max(fraction, 0), 1)), height: 4)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Hero sub-metrics rendered as soft pills (well background, pill radius).
final class UnifiedPillRow: NSView {
    private var pills: [(view: NSView, label: NSTextField)] = []
    
    override var isFlipped: Bool { true }
    
    func setPills(_ texts: [String]) {
        while self.pills.count > texts.count {
            self.pills.removeLast().view.removeFromSuperview()
        }
        while self.pills.count < texts.count {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.cornerRadius = 6
            // monospaced digits: live values must not reflow the pills
            let label = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor)
            view.addSubview(label)
            self.addSubview(view)
            self.pills.append((view, label))
        }
        var changed = false
        for (index, text) in texts.enumerated() {
            let pill = self.pills[index]
            guard pill.label.stringValue != text else { continue }
            changed = true
            pill.label.stringValue = text
            pill.label.sizeToFit()
            pill.view.frame = NSRect(x: 0, y: 0, width: ceil(pill.label.frame.width) + 16, height: 18)
            pill.label.frame = NSRect(x: 8, y: 4, width: pill.label.frame.width, height: 11)
        }
        guard changed else { return }
        var x: CGFloat = 0
        for pill in self.pills {
            pill.view.frame.origin.x = x
            x += pill.view.frame.width + 6
        }
        self.frame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y, width: max(x - 6, 0), height: 18)
    }
}

/// Design-E grammar detail block: name/value row pairs with fixed
/// frames, shared by the expandable grammar rows (Disk, Network,
/// Thermal, Battery). Rows beyond the live data set are hidden, never
/// removed — the expanded height stays constant (one-pass expand).
final class UnifiedDetailRows: NSView {
    private var names: [NSTextField] = []
    private(set) var values: [NSTextField] = []
    private var customs: [NSView?] = []
    
    override var isFlipped: Bool { true }
    
    /// Adds a row; returns the value field for per-tick updates.
    @discardableResult
    func addRow(_ label: String) -> NSTextField {
        let name = unifiedLabel(label, font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        let value = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .labelColor, alignment: .right)
        self.addSubview(name)
        self.addSubview(value)
        self.names.append(name)
        self.values.append(value)
        self.customs.append(nil)
        return value
    }
    
    /// Adds a row whose value area hosts a custom view (the CPU
    /// per-core cluster); the row still occupies one fixed 18pt slot.
    func addCustomRow(_ label: String, custom: NSView) {
        let name = unifiedLabel(label, font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        self.addSubview(name)
        self.addSubview(custom)
        self.names.append(name)
        let placeholder = unifiedLabel(font: .systemFont(ofSize: 11), color: .labelColor)
        placeholder.isHidden = true
        self.values.append(placeholder)
        self.customs.append(custom)
    }
    
    /// Fixed layout; returns the content height for detailHeight sizing.
    @discardableResult
    func layoutRows(width: CGFloat) -> CGFloat {
        var y: CGFloat = 0
        for index in 0..<self.names.count {
            self.names[index].frame = NSRect(x: 0, y: y + 1, width: 180, height: 14)
            if let custom = self.customs[index] {
                custom.frame = NSRect(x: width - 150, y: y, width: 150, height: 16)
                self.values[index].isHidden = true
            } else {
                self.values[index].frame = NSRect(x: width - 150, y: y + 1, width: 150, height: 14)
            }
            y += 18
        }
        self.frame = NSRect(x: 0, y: 0, width: width, height: max(ceil(y), 30))
        return max(ceil(y), 30)
    }
    
    /// Shows the first `count` rows, hides the rest (reserved height is
    /// kept so the card does not change size).
    func setLiveRows(_ count: Int) {
        for index in 0..<self.names.count {
            self.names[index].isHidden = index >= count
            self.values[index].isHidden = index >= count || self.customs[index] != nil
            self.customs[index]?.isHidden = index >= count
        }
    }
    
    /// Hides or shows a single row after the live-prefix pass (e.g. the
    /// disk volume slots that have no volume to show).
    func setRowHidden(_ index: Int, hidden: Bool) {
        guard index < self.names.count else { return }
        self.names[index].isHidden = hidden
        self.values[index].isHidden = hidden || self.customs[index] != nil
        self.customs[index]?.isHidden = hidden
    }
    
    /// Updates a row's label (volume names arrive with the sample).
    func setName(_ index: Int, _ value: String) {
        guard index < self.names.count else { return }
        self.names[index].stringValue = value
    }
}

/// "Top processes" block: title + name/share-bar/value rows.
final class UnifiedTopProcesses: NSView {
    private struct Row {
        let name: NSTextField
        let value: NSTextField
        let track: NSView
        let fill: NSView
    }
    private var rows: [Row] = []
    
    override var isFlipped: Bool { true }
    
    init(title: String, rows: [(name: String, share: Double, value: String)]) {
        super.init(frame: .zero)
        let titleField = unifiedLabel(title.uppercased(), font: .systemFont(ofSize: 10, weight: .semibold), color: .tertiaryLabelColor)
        self.addSubview(titleField)
        titleField.frame = NSRect(x: 0, y: 0, width: 240, height: 12)
        var y: CGFloat = 16
        for _ in rows {
            let name = unifiedLabel(font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
            let value = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .labelColor, alignment: .right)
            let track = NSView()
            let fill = NSView()
            track.wantsLayer = true
            track.layer?.cornerRadius = 2
            track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
            fill.wantsLayer = true
            fill.layer?.cornerRadius = 2
            fill.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            self.addSubview(name)
            self.addSubview(track)
            self.addSubview(fill)
            self.addSubview(value)
            name.frame = NSRect(x: 0, y: y + 1, width: 110, height: 14)
            track.frame = NSRect(x: 114, y: y + 6, width: 130, height: 4)
            fill.frame = NSRect(x: 114, y: y + 6, width: 0, height: 4)
            value.frame = NSRect(x: 248, y: y + 1, width: 76, height: 14)
            self.rows.append(Row(name: name, value: value, track: track, fill: fill))
            y += 19
        }
        self.frame = NSRect(x: 0, y: 0, width: 324, height: y)
        self.update(rows: rows)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// In-place per-tick refresh: no view churn when the process set is
    /// stable. Rows without data are hidden — empty skeleton rows must
    /// never be visible.
    func update(rows: [(name: String, share: Double, value: String)]) {
        for index in 0..<self.rows.count {
            let view = self.rows[index]
            guard index < rows.count else {
                view.name.isHidden = true
                view.value.isHidden = true
                view.track.isHidden = true
                view.fill.isHidden = true
                continue
            }
            let row = rows[index]
            view.name.isHidden = false
            view.value.isHidden = false
            view.track.isHidden = false
            view.fill.isHidden = false
            if view.name.stringValue != row.name {
                view.name.stringValue = row.name
            }
            if view.value.stringValue != row.value {
                view.value.stringValue = row.value
            }
            let width = 130 * CGFloat(min(max(row.share, 0), 1))
            if abs(view.fill.frame.width - width) > 0.5 {
                view.fill.frame = NSRect(x: 114, y: view.fill.frame.origin.y, width: width, height: 4)
            }
        }
    }
}

extension UnifiedMiniMetric {
    func set(value: String, fraction: Double) {
        self.valueField.stringValue = value
        self.fill.frame = NSRect(x: 0, y: 28, width: 96 * CGFloat(min(max(fraction, 0), 1)), height: 4)
    }
}

/// Per-core utilization cluster for the CPU detail: one 3pt tick per
/// core, bottom-anchored fill, accent color, 1.5pt gaps. Views are
/// reused index-matched — no per-sample churn.
final class UnifiedCoreClusterView: NSView {
    private var ticks: [NSView] = []
    
    override var isFlipped: Bool { true }
    
    func update(_ values: [Double]) {
        while self.ticks.count < values.count {
            let tick = NSView()
            tick.wantsLayer = true
            tick.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            self.addSubview(tick)
            self.ticks.append(tick)
        }
        let tickWidth: CGFloat = 3
        let gap: CGFloat = 1.5
        let height = max(self.bounds.height, 10)
        for (index, value) in values.enumerated() {
            let tick = self.ticks[index]
            tick.isHidden = false
            let fill = max((height - 4) * CGFloat(min(max(value, 0), 1)), 1)
            tick.frame = NSRect(x: CGFloat(index) * (tickWidth + gap), y: height - 2 - fill, width: tickWidth, height: fill)
        }
        for index in values.count..<self.ticks.count {
            self.ticks[index].isHidden = true
        }
    }
}

/// CPU per-core detail row: the tick cluster left-packed in the value
/// area, "avg NN%" right-aligned beside it (per design-E grammar).
final class UnifiedCoreClusterRowView: NSView {
    let cluster = UnifiedCoreClusterView()
    private let avgField = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor, alignment: .right)
    
    override var isFlipped: Bool { true }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(self.cluster)
        self.addSubview(self.avgField)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        self.cluster.frame = NSRect(x: 0, y: 0, width: self.bounds.width - 56, height: self.bounds.height)
        self.avgField.frame = NSRect(x: self.bounds.width - 52, y: 1, width: 52, height: 14)
    }
    
    func update(_ values: [Double], avg: Double?) {
        self.cluster.update(values)
        self.avgField.stringValue = avg.map { String(format: "avg %d%%", Int(($0 * 100).rounded())) } ?? ""
    }
}

// MARK: - info formatters (pure; unit-tested in Tests/PanelInfo.swift)

enum UnifiedInfoFormatters {
    /// Battery condition wording from the reader's health percentage
    /// (health = maxCapacity / designedCapacity * 100).
    static func batteryCondition(_ health: Int) -> String {
        switch health {
        case 90...100: return "Normal"
        case 80..<90: return "Good"
        case 60..<80: return "Fair"
        default: return "Poor"
        }
    }
    
    /// ProcessInfo.ThermalState display names.
    static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    
    /// One-line plain-language impact per thermal state (detail row);
    /// kept short enough for the detail value column.
    static func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Thermals normal"
        case .fair: return "Slightly reduced"
        case .serious: return "Performance reduced"
        case .critical: return "Reduce load now"
        @unknown default: return "Thermal state unknown"
        }
    }
    
    /// part ÷ design as a whole percentage — the battery health bases
    /// (nominal health and full-charge capability).
    static func batteryPercent(_ part: Int, of design: Int) -> Int {
        guard design > 0 else { return 0 }
        return Int((Double(100 * part) / Double(design)).rounded(.toNearestOrEven))
    }
    
    /// Compact rate for the collapsed Network row: per-magnitude suffix
    /// ("18M", "5M", "0.4K") — the ↓/↑ arrows already imply per-second.
    /// Scaled like the Disk value (one decimal below 10, integer above).
    static func compactRate(_ bytesPerSecond: Int64) -> String {
        func format(_ value: Double) -> String {
            if value > 0 && value < 10 {
                return String(format: "%.1f", value)
            }
            return String(format: "%.0f", value)
        }
        let value = Double(bytesPerSecond)
        switch value {
        case ..<1_000_000:
            return "\(format(value / 1_000))K"
        case ..<1_000_000_000:
            return "\(format(value / 1_000_000))M"
        default:
            return "\(format(value / 1_000_000_000))G"
        }
    }
    
    /// "36.7 W (charging)" / "-12.4 W (battery)" / "0.0 W (adapter)" —
    /// the machine's draw with its power mode: battery-side flow when on
    /// battery (the same value the attention drain metric uses, so display
    /// and alerting agree), adapter draw (PDTR) when on AC since the
    /// battery flow alone reads ~0 there. Falls back to the battery flow
    /// if the adapter sensor is unavailable.
    static func batteryPowerText(batteryPower: Double, adapterPower: Double, onBattery: Bool, isCharging: Bool) -> String {
        let draw = onBattery ? abs(batteryPower) : (adapterPower > 0 ? adapterPower : abs(batteryPower))
        let magnitude = String(format: "%.1f", draw)
        if onBattery {
            return "-\(magnitude) W (battery)"
        }
        if isCharging {
            return "\(magnitude) W (charging)"
        }
        return "\(magnitude) W (adapter)"
    }
    
    /// "128W" / "9.5W" / "-57W" — compact watts for the unified menu bar
    /// title: integer at ≥10, one decimal below, sign only while draining
    /// (negative values arrive signed; AC draw is unsigned).
    static func menuWatts(_ power: Double) -> String {
        let value = abs(power)
        let formatted = value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return power < 0 ? "-\(formatted)W" : "\(formatted)W"
    }
    
    /// "83%" / "83% · 2:15" — collapsed battery-row value in the unified
    /// panel: the percentage plus the time estimate (minutes as h:mm)
    /// when one exists. The menu bar shows neither — they live here.
    static func batteryRowValue(level: Int, minutes: Int) -> String {
        guard minutes > 0 else { return "\(level)%" }
        return "\(level)% · \(self.clock(minutes))"
    }
    
    /// "2:15" on battery; "Time to full — 0:48" when charging;
    /// "Charging (limit 80%)" under optimized charging; "–" with no
    /// estimate.
    static func batteryTimeText(onBattery: Bool, isCharging: Bool, minutesToEmpty: Int, minutesToFull: Int, optimizedCharging: Bool) -> String {
        if onBattery {
            guard minutesToEmpty > 0 else { return "–" }
            return self.clock(minutesToEmpty)
        }
        if isCharging {
            if optimizedCharging {
                return "Charging (limit 80%)"
            }
            guard minutesToFull > 0 else { return "–" }
            return "Time to full — \(self.clock(minutesToFull))"
        }
        return "–"
    }
    
    /// minutes as h:mm.
    static func clock(_ minutes: Int) -> String {
        "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }
    
    /// Grammar-row status level (0/1/2) for a thermal state. Display
    /// tint only — thermal pressure is deliberately NOT wired into the
    /// attention evaluator.
    static func thermalStatusLevel(_ state: ProcessInfo.ThermalState) -> Int {
        switch state {
        case .fair: return 1
        case .serious, .critical: return 2
        default: return 0
        }
    }
}

// MARK: - hero card

final class UnifiedHeroCard: UnifiedCardView {
    let module: String
    let nameLabel = unifiedLabel(font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor)
    let valueField = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 26, weight: .semibold), color: .labelColor, alignment: .right)
    let pillRow = UnifiedPillRow()
    let chevron = NSButton()
    /// Always-visible utilization chart; utilization % history at a
    /// glance, fixed 0–100 scale like the grammar-row charts.
    let spark = UnifiedSparklineView()
    private var valuePercentage: Int = -1
    private var valueInk: NSColor = .labelColor
    private let iconView = NSImageView()
    private var bulletTrack: NSView?
    private var bulletBands: [NSView] = []
    private var bulletFill: NSView?
    var expanded: Bool = false
    var onToggle: (() -> Void)?
    /// Fixed-height detail content installed by the panel; hidden when collapsed.
    let expandContainer = UnifiedFlippedView()
    
    init(module: String, icon: String, detailHeight: CGFloat) {
        self.module = module
        self.detailHeight = detailHeight
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.cornerRadius = UnifiedTokens.cardRadius
        self.layer?.borderWidth = 1
        self.layer?.masksToBounds = false
        self.nameLabel.stringValue = module
        
        // macOS 12-safe fallback: newer symbols resolve nil on older
        // systems and the hero must never show a bare label.
        self.iconView.image = unifiedSymbol(icon) ?? unifiedSymbol("rectangle.on.rectangle")
        self.iconView.contentTintColor = .controlAccentColor
        self.addSubview(self.iconView)
        self.addSubview(self.nameLabel)
        self.addSubview(self.spark)
        self.addSubview(self.valueField)
        self.spark.scale = .fixed
        
        self.chevron.isBordered = false
        self.chevron.imageScaling = .scaleProportionallyDown
        self.chevron.image = unifiedSymbol("chevron.right", scale: .small)
        self.chevron.contentTintColor = .secondaryLabelColor
        self.chevron.target = self
        self.chevron.action = #selector(self.toggle)
        self.addSubview(self.chevron)
        // The whole header band toggles the hero — not just the chevron
        // (same convention as the grammar rows). Clicks on the chevron
        // itself and on the pill row are excluded.
        let tap = NSClickGestureRecognizer(target: self, action: #selector(self.headerTapped(_:)))
        self.addGestureRecognizer(tap)
        self.addSubview(self.pillRow)
        self.addSubview(self.expandContainer)
        self.expandContainer.isHidden = true
    }
    
    /// QA hook: drives the same toggle path as a header tap.
    func simulateHeaderTap() {
        self.onToggle?()
    }
    
    @objc private func headerTapped(_ recognizer: NSClickGestureRecognizer) {
        let point = recognizer.location(in: self)
        guard point.y <= 40 else { return }
        guard !self.chevron.frame.contains(point) else { return }
        self.onToggle?()
    }
    
    /// Big tabular number; the unit is demoted to 14pt secondary, per the mock.
    func setValue(_ percentage: Int, force: Bool = false) {
        guard force || percentage != self.valuePercentage else { return }
        self.valuePercentage = percentage
        let text = NSMutableAttributedString(string: "\(percentage)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: self.valueInk
        ])
        text.append(NSAttributedString(string: "%", attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        self.valueField.attributedStringValue = text
    }
    
    func setPills(_ texts: [String]) {
        self.pillRow.setPills(texts)
    }
    
    private let detailHeight: CGFloat
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func toggle() {
        self.onToggle?()
    }
    
    /// RAM capacity strip with neutral bands marking 70/90% capacity.
    /// Status hues (orange/red) are reserved for actual attention states —
    /// static warm bands read as a warning on a healthy system.
    func installBullet() {
        let track = NSView()
        track.wantsLayer = true
        track.layer?.cornerRadius = 2
        track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
        let warn = NSView()
        warn.wantsLayer = true
        warn.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        let crit = NSView()
        crit.wantsLayer = true
        crit.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 2
        fill.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        self.addSubview(track)
        self.addSubview(warn)
        self.addSubview(crit)
        self.addSubview(fill)
        self.bulletTrack = track
        self.bulletBands = [warn, crit]
        self.bulletFill = fill
    }
    
    func setBullet(_ fraction: Double) {
        guard let track = self.bulletTrack else { return }
        let x: CGFloat = 36
        let width = self.bounds.width - x - 12
        track.frame = NSRect(x: x, y: 66, width: width, height: 4)
        self.bulletBands[0].frame = NSRect(x: x + width * 0.7, y: 66, width: width * 0.2, height: 4)
        self.bulletBands[1].frame = NSRect(x: x + width * 0.9, y: 66, width: width * 0.1, height: 4)
        self.bulletFill?.frame = NSRect(x: x, y: 66, width: width * CGFloat(min(max(fraction, 0), 1)), height: 4)
    }
    
    func setExpanded(_ state: Bool) {
        self.expanded = state
        self.expandContainer.isHidden = !state
        self.chevron.image = unifiedSymbol(state ? "chevron.down" : "chevron.right", scale: .small)
        self.chevron.contentTintColor = .secondaryLabelColor
        let rotation: CGFloat = state ? .pi / 2 : 0
        self.chevron.wantsLayer = true
        if UnifiedMotion.enabled {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.toValue = rotation
            animation.duration = 0.09
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.chevron.layer?.add(animation, forKey: "rotate")
        }
        self.chevron.layer?.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
        self.layoutCard()
    }
    
    /// Redundant encoding for attention: tint plus ink, never hue alone.
    func setStatus(level: Int) {
        guard level != self.statusLevel else { return }
        self.statusLevel = level
        self.valueInk = level == 2 ? UnifiedTokens.redInk : (level == 1 ? UnifiedTokens.amberInk : .labelColor)
        self.setValue(self.valuePercentage, force: true)
        self.updateLayer()
    }
    
    var collapsedHeight: CGFloat {
        self.bulletTrack == nil ? 70 : 78
    }
    
    var totalHeight: CGFloat {
        self.collapsedHeight + (self.expanded ? self.detailHeight + 12 : 0)
    }
    
    func layoutCard() {
        let w = self.bounds.width
        self.iconView.frame = NSRect(x: 12, y: 14, width: 16, height: 16)
        self.nameLabel.frame = NSRect(x: 36, y: 13, width: 120, height: 18)
        self.valueField.frame = NSRect(x: w - 12 - 14 - 8 - 100, y: 8, width: 100, height: 30)
        self.chevron.frame = NSRect(x: w - 12 - 14, y: 15, width: 14, height: 14)
        self.spark.frame = NSRect(x: 80, y: 10, width: max(self.valueField.frame.origin.x - 8 - 80, 40), height: 26)
        self.pillRow.frame = NSRect(x: 36, y: 42, width: w - 48, height: 18)
        self.expandContainer.frame = NSRect(x: 12, y: self.collapsedHeight - 6, width: w - 24, height: self.detailHeight)
    }
}

// MARK: - grammar row

final class UnifiedGrammarRow: NSView {
    let module: String
    /// 0 quiet, 1 attention, 2 critical - tints the row background.
    var statusLevel: Int = 0
    
    override var isFlipped: Bool { true }
    let nameLabel = unifiedLabel(font: .systemFont(ofSize: 12, weight: .medium), color: .labelColor)
    let valueField = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold), color: .labelColor, alignment: .right)
    let glyphField = unifiedLabel("✓", font: .systemFont(ofSize: 10, weight: .semibold), color: .systemGreen, alignment: .center)
    let spark = UnifiedSparklineView()
    let chevron = NSButton()
    let expandContainer = UnifiedFlippedView()
    private let iconView = NSImageView()
    private let hairline = UnifiedHairline()
    var expanded: Bool = false
    var onToggle: (() -> Void)?
    var detailHeight: CGFloat = 0
    private let expandable: Bool
    
    init(module: String, label: String, icon: String, expandable: Bool) {
        self.module = module
        self.expandable = expandable
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.cornerRadius = 8
        self.iconView.image = unifiedSymbol(icon)
        self.iconView.contentTintColor = .controlAccentColor
        self.addSubview(self.iconView)
        self.nameLabel.stringValue = label
        self.addSubview(self.nameLabel)
        self.addSubview(self.spark)
        self.addSubview(self.valueField)
        self.addSubview(self.glyphField)
        self.addSubview(self.hairline)
        if expandable {
            self.chevron.isBordered = false
            self.chevron.imageScaling = .scaleProportionallyDown
            self.chevron.image = unifiedSymbol("chevron.right", scale: .small)
            self.chevron.contentTintColor = .secondaryLabelColor
            self.chevron.target = self
            self.chevron.action = #selector(self.toggle)
            self.addSubview(self.chevron)
            self.addSubview(self.expandContainer)
            self.expandContainer.isHidden = true
            // The whole header row toggles the section — not just the
            // 14pt chevron. Clicks in the detail area (fan sliders, mode
            // buttons) and on the chevron itself are excluded.
            let tap = NSClickGestureRecognizer(target: self, action: #selector(self.headerTapped(_:)))
            self.addGestureRecognizer(tap)
        }
    }
    
    /// QA hook: drives the exact same toggle path as a header tap.
    func simulateHeaderTap() {
        guard self.expandable else { return }
        self.onToggle?()
    }
    
    @objc private func headerTapped(_ recognizer: NSClickGestureRecognizer) {
        let point = recognizer.location(in: self)
        guard point.y <= 46 else { return }
        guard !self.chevron.frame.contains(point) else { return }
        self.onToggle?()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func toggle() {
        self.onToggle?()
    }
    
    func setExpanded(_ state: Bool) {
        guard state != self.expanded else { return }
        self.expanded = state
        self.expandContainer.isHidden = !state
        self.chevron.image = unifiedSymbol(state ? "chevron.down" : "chevron.right", scale: .small)
        self.chevron.contentTintColor = .secondaryLabelColor
        self.applyChevronRotation(state)
        self.layoutRow()
    }
    
    /// 0°→90° on expand (and back), 90ms layer transform — the native
    /// disclosure convention. Instant when motion is gated.
    private func applyChevronRotation(_ expanded: Bool) {
        let rotation: CGFloat = expanded ? .pi / 2 : 0
        self.chevron.wantsLayer = true
        if UnifiedMotion.enabled {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.toValue = rotation
            animation.duration = 0.09
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.chevron.layer?.add(animation, forKey: "rotate")
        }
        self.chevron.layer?.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
    }
    
    override func updateLayer() {
        guard self.wantsLayer else { return }
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            switch self.statusLevel {
            case 1:
                self.layer?.backgroundColor = UnifiedTokens.amberSoft.cgColor
            case 2:
                self.layer?.backgroundColor = UnifiedTokens.redSoft.cgColor
            default:
                self.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
    
    /// Redundant encoding for attention: tint plus glyph, never hue alone.
    func setStatus(level: Int) {
        guard level != self.statusLevel else { return }
        self.statusLevel = level
        if level == 0 {
            self.glyphField.stringValue = "✓"
            self.glyphField.textColor = UnifiedTokens.ok
        } else {
            self.glyphField.stringValue = "▲"
            self.glyphField.textColor = level == 2 ? UnifiedTokens.redInk : UnifiedTokens.amberInk
        }
        self.updateLayer()
    }
    
    var totalHeight: CGFloat {
        46 + (self.expanded ? self.detailHeight + 8 : 0)
    }
    
    func layoutRow() {
        let w = self.bounds.width
        self.hairline.frame = NSRect(x: 0, y: 0, width: w, height: 1)
        self.iconView.frame = NSRect(x: 4, y: 15, width: 16, height: 16)
        self.nameLabel.frame = NSRect(x: 26, y: 15, width: 70, height: 16)
        self.chevron.frame = NSRect(x: w - 4 - 14, y: 16, width: 14, height: 14)
        // Fixed-width value slot: the text is right-aligned inside it, so
        // changing values ("6.1K↓ 17K↑" ↔ "2.0K↓ 1.0K↑") resize nothing —
        // with a text-sized frame every tick moved the field and the
        // sparkline with it, which read as constant flicker.
        let valueWidth: CGFloat = 84
        self.valueField.frame = NSRect(x: w - 4 - 14 - 8 - valueWidth, y: 15, width: valueWidth, height: 16)
        // Status glyph placement: the chevron owns the trailing slot on
        // expandable rows, so the glyph (✓/▲) sits just LEFT of the value
        // in BOTH collapsed and expanded states — the two glyphs never
        // share a slot. Non-expandable rows keep the glyph in the
        // trailing slot.
        // Status glyph placement: the chevron owns the trailing slot on
        // expandable rows, so the glyph (✓/▲) sits just LEFT of the value
        // in BOTH collapsed and expanded states — the two glyphs never
        // share a slot. Non-expandable rows keep the glyph in the
        // trailing slot.
        let sparkX: CGFloat = 100
        let sparkEnd: CGFloat
        if self.expandable {
            self.glyphField.isHidden = false
            self.glyphField.frame = NSRect(x: self.valueField.frame.origin.x - 18, y: 16, width: 14, height: 14)
            sparkEnd = self.glyphField.frame.origin.x - 8
        } else {
            self.glyphField.isHidden = false
            self.glyphField.frame = NSRect(x: w - 4 - 14, y: 16, width: 14, height: 14)
            sparkEnd = self.valueField.frame.origin.x - 8
        }
        self.spark.frame = NSRect(x: sparkX, y: 9, width: max(sparkEnd - sparkX, 40), height: 28)
        self.expandContainer.frame = NSRect(x: 8, y: 50, width: w - 16, height: self.detailHeight)
    }
}

/// Standard system popover material with the mock's 16pt radius and
/// 1pt panel border (white 14% dark / black 7% light).
///
/// Top-origin coordinates for its chrome (scroll container, footer):
/// the panel is anchored at the menu bar and grows DOWNWARD, so the
/// band layout is expressed from the top.
private final class UnifiedPanelMaterialView: NSVisualEffectView {
    override var isFlipped: Bool { true }

    override func updateLayer() {
        super.updateLayer() // NSVisualEffectView draws the material here
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.borderColor = UnifiedTokens.panelBorder.cgColor
        }
    }
}

/// Manual clip container in place of NSScrollView: the panel window hugs
/// the menu bar and AppKit applies a variable safe-area content inset to
/// scroll views there, which no reset reliably defeats. Full control over
/// the offset also makes harness scroll knobs exact.
private final class UnifiedPopupScrollContainer: NSView {
    private weak var document: NSView?
    var offset: CGFloat = 0

    override var isFlipped: Bool { true }

    func host(_ document: NSView) {
        self.document = document
        self.addSubview(document)
    }

    var maxOffset: CGFloat {
        max((self.document?.frame.height ?? 0) - self.bounds.height, 0)
    }

    func scrollTo(_ value: CGFloat) {
        self.offset = min(max(value, 0), self.maxOffset)
        self.layoutContent()
    }

    func layoutContent() {
        guard let document = self.document else { return }
        document.frame = NSRect(x: 0, y: -self.offset, width: self.bounds.width, height: document.frame.height)
    }

    override func scrollWheel(with event: NSEvent) {
        self.scrollTo(self.offset + event.scrollingDeltaY)
    }
}

final class UnifiedPopupPanel: NSPanel, NSWindowDelegate {
    static let panelWidth: CGFloat = 380

    private let effectView = UnifiedPanelMaterialView()
    private let scrollContainer = UnifiedPopupScrollContainer()
    private let content = UnifiedPanelContent(width: panelWidth)
    private let footerBar = NSView()

    var contentHeight: CGFloat {
        self.content.frame.height
    }

    override var canBecomeKey: Bool { true }

    /// Every path that makes the panel vanish ends here. The compact
    /// caller stack (first non-system frames) names which one — the
    /// [UnifiedPanelTrace] lines around it (toggle decision, key/main and
    /// active transitions) pin down the real status-item click flow.
    override func orderOut(_ sender: Any?) {
        let appFrames = Thread.callStackSymbols
            .filter { frame in
                !frame.contains("AppKit") && !frame.contains("Foundation") &&
                !frame.contains("CoreFoundation") && !frame.contains("libswiftCore") &&
                !frame.contains("libsystem") && !frame.contains("HIToolbox") &&
                !frame.contains("SwiftUI") && !frame.contains("UIKitMacHelper")
            }
            .prefix(6)
        NSLog("[UnifiedPanelTrace] panel orderOut (was visible=%d) callers: %@",
              self.isVisible ? 1 : 0,
              appFrames.joined(separator: " <- "))
        super.orderOut(sender)
    }

    // MARK: - NSWindowDelegate (traced)

    func windowDidBecomeKey(_ notification: Notification) {
        NSLog("[UnifiedPanelTrace] panel didBecomeKey visible=%d", self.isVisible ? 1 : 0)
    }

    func windowDidResignKey(_ notification: Notification) {
        NSLog("[UnifiedPanelTrace] panel didResignKey visible=%d", self.isVisible ? 1 : 0)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        NSLog("[UnifiedPanelTrace] panel didBecomeMain visible=%d", self.isVisible ? 1 : 0)
    }

    func windowDidResignMain(_ notification: Notification) {
        NSLog("[UnifiedPanelTrace] panel didResignMain visible=%d", self.isVisible ? 1 : 0)
    }

    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)

        // Status-item popups live at NSStatusWindowLevel, not .normal:
        // the opening click activates Stats and the system bounces a
        // deactivate back (traced), and the moment Stats deactivates,
        // other apps' regular windows restack ABOVE a .normal-level
        // panel and bury it — the open-then-vanish flash. At .statusBar
        // the panel floats above app windows even while Stats is
        // inactive (same as the Wi-Fi/Battery popups). Activation on
        // open stays: it is what dismisses another app's open dropdown.
        self.level = .statusBar
        self.collectionBehavior = .moveToActiveSpace
        self.backgroundColor = .clear
        // NSPanel's default is true; with activation-on-open (show())
        // the menu-bar click flow bounces a deactivate right after the
        // opening click, and AppKit would order this panel out on it —
        // the open-then-instantly-vanish flash. Outside clicks close the
        // panel through explicit monitors in UnifiedPopupController
        // instead, which are immune to that transient bounce.
        self.hidesOnDeactivate = false
        // opaque + behindWindow material (the classic popup recipe): a
        // non-opaque panel inherits the desktop safe area and the scroll
        // view gets a variable top content inset that hides the header
        self.isOpaque = true
        self.hasShadow = true
        self.delegate = self

        let chrome = UnifiedPopupContentView(frame: NSRect(x: 0, y: 0, width: contentRect.width, height: contentRect.height))
        if ProcessInfo.processInfo.environment["STATS_POPUP_DEBUG_PAINT"] == "1" {
            chrome.wantsLayer = true
            chrome.layer?.backgroundColor = NSColor.systemPurple.cgColor
        }
        chrome.onEscape = { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
        }
        self.contentView = chrome

        self.effectView.material = .popover
        self.effectView.blendingMode = .behindWindow
        self.effectView.state = .active
        self.effectView.wantsLayer = true
        self.effectView.layer?.cornerRadius = UnifiedTokens.panelRadius
        self.effectView.layer?.borderWidth = 1
        self.effectView.layer?.masksToBounds = true
        self.effectView.frame = content.bounds
        self.effectView.autoresizingMask = [.width, .height]

        self.scrollContainer.wantsLayer = true
        self.scrollContainer.layer?.masksToBounds = true
        self.scrollContainer.frame = NSRect(x: 0, y: 0, width: contentRect.width, height: max(contentRect.height - 28, 60))
        self.scrollContainer.autoresizingMask = []
        self.scrollContainer.host(self.content)
        self.effectView.addSubview(self.scrollContainer)

        self.footerBar.frame = NSRect(x: 0, y: 0, width: contentRect.width, height: 28)
        self.footerBar.autoresizingMask = [.width]

        let separator = NSView(frame: NSRect(x: 12, y: 27, width: contentRect.width - 24, height: 1))
        separator.autoresizingMask = [.width]
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        self.footerBar.addSubview(separator)

        let activity = NSButton()
        activity.isBordered = false
        activity.attributedTitle = NSAttributedString(string: localizedString("Open Activity Monitor"), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor
        ])
        activity.target = self
        activity.action = #selector(self.openActivityMonitor)
        activity.sizeToFit()
        activity.frame = NSRect(x: 12, y: 3, width: activity.frame.width, height: 20)
        self.footerBar.addSubview(activity)

        let settings = NSButton()
        settings.isBordered = false
        settings.attributedTitle = NSAttributedString(string: localizedString("Settings"), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor
        ])
        settings.target = self
        settings.action = #selector(self.openSettings)
        settings.sizeToFit()

        // Quit is the destructive action and sits rightmost, red per macOS
        // convention; it terminates the app gracefully.
        let quit = NSButton()
        quit.isBordered = false
        quit.attributedTitle = NSAttributedString(string: localizedString("Quit Stats"), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.systemRed
        ])
        quit.target = self
        quit.action = #selector(self.quitApp)
        quit.sizeToFit()
        quit.frame = NSRect(x: contentRect.width - 12 - quit.frame.width, y: 3, width: quit.frame.width, height: 20)
        quit.autoresizingMask = [.minXMargin]
        self.footerBar.addSubview(quit)

        settings.frame = NSRect(x: quit.frame.origin.x - 8 - settings.frame.width, y: 3, width: settings.frame.width, height: 20)
        settings.autoresizingMask = [.minXMargin]
        self.footerBar.addSubview(settings)

        self.effectView.addSubview(self.footerBar)

        chrome.addSubview(self.effectView)

        // Content-layout changes (section expand, fan rebuild)
        // must resize the window immediately — previously this hook was
        // never assigned, so an expand rendered partially for up to a
        // second until the glyph timer happened to run syncSize.
        self.content.onLayoutChange = { [weak self] in
            guard let self, self.isVisible else { return }
            withoutImplicitAnimation {
                self.refreshContent()
                self.syncSize()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Total content size the panel needs: document + footer.
    var requiredContentSize: NSSize {
        NSSize(width: Self.panelWidth, height: self.content.frame.height + 28)
    }

    /// Resize the window so the document and footer fit without
    /// scrolling; the top edge stays put.
    func syncSize() {
        let needed = self.requiredContentSize
        let current = self.contentView?.frame.size ?? .zero
        let heightDelta = abs(needed.height - current.height)
        self.pendingContentHeight = needed.height
        guard needed.width != current.width || heightDelta >= 1.5 else {
            self.layoutChrome()
            return
        }
        if UnifiedMotion.enabled, self.anchorTopY != nil {
            // The spring drives the WINDOW FRAME ONLY, self-timed, with
            // every frame anchored to anchorTopY (the menu-bar anchor).
            // AppKit's own frame animation does not keep the visual top
            // fixed mid-flight on this window class, which broke the
            // panel invariant (content above the expansion point must
            // keep identical screen coordinates at every frame).
            self.frameAnimationFrom = current.height
            self.frameAnimationTo = needed.height
            self.frameAnimationStart = Date()
            if self.frameAnimator == nil {
                self.frameAnimator = Timer.scheduledTimer(withTimeInterval: 1.0 / 90, repeats: true) { [weak self] _ in
                    self?.stepFrameAnimation()
                }
            }
            self.layoutChrome()
            return
        }
        if UnifiedPerf.enabled {
            UnifiedPerf.frameSet("syncResize")
            NSLog("[UnifiedPerf] syncResize %.1f -> %.1f", current.height, needed.height)
        }
        let top = self.anchorTopY ?? self.frame.maxY
        self.setContentSize(needed)
        var frame = self.frame
        frame.origin.y = top - frame.height
        self.setFrameOrigin(frame.origin)
        // Re-pin against the FINAL height in the same pass — pinning
        // against the pre-resize height leaves the chrome mis-placed for
        // one visible frame (the "appears in the wrong spot, then jumps"
        // defect).
        self.layoutChrome()
    }

    /// Self-driven window-frame spring: each tick re-frames the window
    /// anchored to the menu-bar top, so the visual top NEVER moves while
    /// the bottom eases out with a slight overshoot.
    private var frameAnimator: Timer?
    private var frameAnimationStart: Date?
    private var frameAnimationFrom: CGFloat = 0
    private var frameAnimationTo: CGFloat = 0

    private func stepFrameAnimation() {
        guard let start = self.frameAnimationStart else { return }
        let progress = min(Date().timeIntervalSince(start) / 0.28, 1)
        let eased = Self.easeOutBack(progress)
        let height = self.frameAnimationFrom + (self.frameAnimationTo - self.frameAnimationFrom) * eased
        let top = self.anchorTopY ?? self.frame.maxY
        var frame = self.frame
        frame.origin.y = top - height
        frame.size.height = height
        self.setFrame(frame, display: true)
        if progress >= 1 {
            self.frameAnimator?.invalidate()
            self.frameAnimator = nil
            var finalFrame = self.frame
            finalFrame.origin.y = top - self.frameAnimationTo
            finalFrame.size.height = self.frameAnimationTo
            self.setFrame(finalFrame, display: true)
        }
    }

    /// Ease-out-back (~280ms, slight overshoot) — the AppKit spring feel.
    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.25
        let c3 = c1 + 1
        let t = x - 1
        return 1 + c3 * t * t * t + c1 * t * t
    }

    /// Entrance: contentView layer transform scale 0.92→1.0 (anchored at
    /// the top-center, i.e. the menu bar icon) + alpha 0→1, ~200ms
    /// ease-out. Applied AFTER makeKeyAndOrderFront; skipped entirely
    /// when any QA/capture knob is active.
    func playEntrance() {
        guard UnifiedMotion.enabled, let view = self.contentView, let layer = view.layer else { return }
        view.wantsLayer = true
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        layer.position = CGPoint(x: frame.midX, y: frame.maxY)
        layer.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        view.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = 1
        })
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DMakeScale(0.92, 0.92, 1)
        animation.toValue = CATransform3DIdentity
        animation.duration = 0.2
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "entrance")
        layer.transform = CATransform3DIdentity
    }

    /// Exit: reverse of the entrance, snappier (~140ms); orderOut runs in
    /// the completion. Skipped when motion is gated (instant orderOut).
    func animateExit(completion: @escaping () -> Void) {
        guard UnifiedMotion.enabled, let view = self.contentView, let layer = view.layer else {
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            view.animator().alphaValue = 0
        }, completionHandler: {
            view.alphaValue = 1
            layer.transform = CATransform3DIdentity
            completion()
        })
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = CATransform3DIdentity
        animation.toValue = CATransform3DMakeScale(0.94, 0.94, 1)
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(animation, forKey: "exit")
        layer.transform = CATransform3DMakeScale(0.94, 0.94, 1)
    }

    func debugFrames() {
        NSLog("[UnifiedPopup] window=%@ contentView=%@ effect=%@ container=%@",
              NSStringFromRect(self.frame),
              NSStringFromRect(self.contentView?.frame ?? .zero),
              NSStringFromRect(self.effectView.frame),
              NSStringFromRect(self.scrollContainer.frame))
    }

    func refreshContent() {
        // the window's content rect can carry system insets that autoresizing
        // does not track; pin the material to the full content view explicitly
        if let bounds = self.contentView?.bounds, self.effectView.frame != bounds {
            UnifiedPerf.frameSet("effect")
            self.effectView.frame = bounds
        }
        self.content.relayout()
        self.layoutChrome()
        self.scrollContainer.layoutContent()
    }

    /// The panel's anchor top (screen maxY), captured at show(). The
    /// window grows DOWNWARD from the menu bar, so every resize —
    /// immediate or animated — must be anchored to THIS value, not to
    /// self.frame.maxY (the model frame can differ from the on-screen
    /// presentation mid-animation, which moved the visual top).
    private var anchorTopY: CGFloat? = nil
    func setAnchorTop(_ value: CGFloat) { self.anchorTopY = value }

    /// Target content height for the scroll container/footer geometry.
    /// syncSize/show set this BEFORE the frame reaches it, so chrome
    /// settles at final geometry in the same pass while the spring
    /// animates the window frame (the scroll container's top edge is
    /// constant — only its height follows content; see layoutChrome).
    private var pendingContentHeight: CGFloat? = nil

    /// Panel geometry invariant: the window is anchored at the menu bar
    /// and grows DOWNWARD (syncSize preserves maxY in both the immediate
    /// and the spring paths). Therefore at EVERY frame of any resize —
    /// including the expand spring — the content above the expanding
    /// section (brand header and everything before the expansion point)
    /// keeps IDENTICAL screen coordinates; only content at or below the
    /// expansion point translates. Consequences:
    ///  - the scroll container's TOP edge is constant — only its HEIGHT
    ///    follows content;
    ///  - the footer is bottom-anchored (moves with the bottom edge).
    /// `height` is the TARGET content height (pendingContentHeight) so
    /// the scroll/footer settle at final geometry in the same pass.
    func layoutChrome() {
        let height = self.pendingContentHeight ?? self.contentView?.frame.height ?? 0
        let containerFrame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: max(height - 28, 60))
        if self.scrollContainer.frame != containerFrame {
            UnifiedPerf.frameSet("container")
            self.scrollContainer.frame = containerFrame
        }
        let footerFrame = NSRect(x: 0, y: height - 28, width: Self.panelWidth, height: 28)
        if self.footerBar.frame != footerFrame {
            self.footerBar.frame = footerFrame
        }
    }

    /// show() sizes the window itself — record its target so chrome
    /// pinning never reads a stale or animating frame.
    func setPendingContentHeight(_ value: CGFloat) { self.pendingContentHeight = value }
    /// QA hook: drive a section header tap (same path as the gesture).
    func simulateHeaderTap(_ module: String) { self.content.simulateHeaderTap(module) }
    var expandedSectionForQA: String? { self.content.expandedSectionForQA }
    /// QA hook: open the all-sensors popover (same path as the row tap).
    func openAllSensorsForQA() { self.content.openAllSensorsForQA() }
    /// QA hook: collapsed states "name=1" pairs for the restore probe.
    var collapsedStatesForQA: String { self.content.collapsedStatesForQA }

    func expandSection(_ module: String) {
        self.content.expandSection(module)
    }

    func sectionOffset(for module: String) -> CGFloat? {
        self.content.sectionOffset(for: module)
    }

    func scrollToSection(_ module: String) {
        guard let offset = self.sectionOffset(for: module) else { return }
        self.scrollToOffset(offset)
    }

    func scrollToTop() {
        self.scrollContainer.scrollTo(0)
    }

    func scrollToBottom() {
        self.scrollContainer.scrollTo(self.content.frame.height)
    }

    func scrollToOffset(_ offset: Double) {
        self.scrollContainer.scrollTo(offset)
    }

    @objc private func openActivityMonitor() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Settings"])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Harness QA (STATS_POPUP_CAPTURE=1): renders the panel content into a
    /// PNG on disk, so captures work even when the console is locked.
    /// STATS_POPUP_CAPTURE_CHROME=1 additionally renders the footer bar
    /// next to the content capture as "<path>-footer.png" — the footer
    /// lives in the panel chrome, outside the content view.
    func writeSelfCapture() {
        let content = self.content
        content.relayout()
        let size = content.bounds.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ) else { return }
        rep.size = size
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            // A plain setNeedsDisplay + cacheDisplay composites from layer
            // caches: views that never had a display pass (freshly built
            // rows, NSScrollView document content) come out blank. A
            // synchronous display() pass first makes captures faithful.
            content.display()
            content.cacheDisplay(in: content.bounds, to: rep)
        }
        guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
        let path = ProcessInfo.processInfo.environment["STATS_POPUP_CAPTURE_PATH"] ?? "/tmp/unified-panel-selfcapture.png"
        try? png.write(to: URL(fileURLWithPath: path))
        NSLog("[UnifiedPopup] self capture written to %@", path)
        if ProcessInfo.processInfo.environment["STATS_POPUP_CAPTURE_CHROME"] == "1" {
            self.writeChromeCapture(self.footerBar, path: "\(path)-footer.png")
        }
    }

    /// Renders one chrome view (footer) into its own PNG. Skips hidden
    /// views.
    private func writeChromeCapture(_ view: NSView, path: String) {
        let size = view.bounds.size
        guard !view.isHidden, size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              ) else { return }
        rep.size = size
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.display()
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        NSLog("[UnifiedPopup] chrome capture written to %@", path)
    }
}

private extension NSView {
    func setNeedsDisplayRecursively() {
        self.setNeedsDisplay(self.bounds)
        for subview in self.subviews {
            subview.setNeedsDisplayRecursively()
        }
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
