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
