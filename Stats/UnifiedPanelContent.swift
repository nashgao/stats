//
//  UnifiedPanelContent.swift
//  Stats
//
//  Design "E - Heroes + Grammar" for the unified panel (spec:
//  stats-unified-redesign.html, column E): a glass shell with a brand
//  header, three hero cards (CPU, GPU, RAM) that expand in place one at
//  a time, and four grammar rows (Disk, Network, Sensors, Battery).
//  Sections subscribe to the modules' existing reader data via
//  .unifiedPanelSample - the classic popups are untouched.
//

import Cocoa
import Kit
import CPU
import GPU
import RAM
import Disk
import Net
import Sensors
import Battery

// MARK: - perf instrumentation (env STATS_POPUP_PERF=1)
enum UnifiedPerf {
    static let enabled = ProcessInfo.processInfo.environment["STATS_POPUP_PERF"] == "1"
    private static var acc: [String: (ms: Double, n: Int, frames: Int)] = [:]
    
    static func measure(_ label: String, _ block: () -> Void) {
        guard self.enabled else { block(); return }
        let start = CFAbsoluteTimeGetCurrent()
        block()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        var e = self.acc[label] ?? (0, 0, 0)
        e.ms += ms
        e.n += 1
        self.acc[label] = e
    }
    
    static func frameSet(_ label: String) {
        guard self.enabled else { return }
        var e = self.acc[label] ?? (0, 0, 0)
        e.frames += 1
        self.acc[label] = e
    }
    
    static func tick() {
        guard self.enabled, !self.acc.isEmpty else { return }
        var line: [String] = []
        for (key, e) in self.acc.sorted(by: { $0.key < $1.key }) where e.n > 0 || e.frames > 0 {
            let avg = e.n > 0 ? e.ms / Double(e.n) : 0
            line.append(String(format: "%@ avg %.2fms n=%d frameSets=%d", key, avg, e.n, e.frames))
        }
        self.acc = [:]
        NSLog("[UnifiedPerf] %@", line.joined(separator: " | "))
    }
}

// MARK: - design tokens
//
// Extracted from stats-unified-redesign.html (column E). Light and dark
// are independently designed token sets, not inversions. Semantic label
// colors already match the mock's text/text-2/text-3 rgba values.
enum UnifiedTokens {
    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let pillRadius: CGFloat = 8
    static let chipRadius: CGFloat = 8
    static let contentMargin: CGFloat = 12
    
    static var isDark: Bool {
        switch NSAppearance.currentDrawing().name {
        case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
            return true
        default:
            return false
        }
    }
    
    private static func hex(_ value: UInt32, _ alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: alpha)
    }
    
    // surfaces (mock: --card / --card-border / --well / --hairline / --panel-border)
    static var card: NSColor { isDark ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 1, alpha: 0.82) }
    static var cardBorder: NSColor { isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.05) }
    static var well: NSColor { isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.05) }
    static var hairline: NSColor { isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.08) }
    static var panelBorder: NSColor { isDark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.07) }
    
    // status (mock: --ok / --amber-ink / --red-ink, with -soft / -border alphas)
    static var ok: NSColor { isDark ? hex(0x30d158) : hex(0x248a3d) }
    static var amberInk: NSColor { isDark ? hex(0xffb340) : hex(0x8a5200) }
    static var redInk: NSColor { isDark ? hex(0xff6961) : hex(0xc62828) }
    static var amberSoft: NSColor { .systemOrange.withAlphaComponent(isDark ? 0.15 : 0.18) }
    static var amberBorder: NSColor { .systemOrange.withAlphaComponent(isDark ? 0.38 : 0.45) }
    static var redSoft: NSColor { .systemRed.withAlphaComponent(isDark ? 0.16 : 0.13) }
    
    // mock: --shadow-card 0 1px 2px (dark .25 / light .06)
    static var cardShadowAlpha: CGFloat { isDark ? 0.25 : 0.06 }
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

// MARK: - sparkline

/// Thin single-hue sparkline: no axes, no fills, rounded joins.
private final class UnifiedSparklineView: NSView {
    enum Scale {
        case fixed // 0...100
        case auto  // padded min/max
    }
    
    var scale: Scale = .auto
    var strokeColor = NSColor.controlAccentColor {
        didSet { self.needsDisplay = true }
    }
    private var values: [Double] = []
    private let capacity = 30
    
    override var isOpaque: Bool { false }
    
    func add(_ value: Double) {
        self.values.append(value)
        if self.values.count > self.capacity {
            self.values.removeFirst(self.values.count - self.capacity)
        }
        self.needsDisplay = true
    }
    
    override func draw(_ rect: NSRect) {
        guard self.values.count > 1 else { return }
        let lo: Double
        let hi: Double
        switch self.scale {
        case .fixed:
            lo = 0
            hi = 100
        case .auto:
            let min = self.values.min() ?? 0
            let max = self.values.max() ?? 1
            let span = Swift.max(max - min, 1)
            lo = min - span * 0.25
            hi = max + span * 0.25
        }
        let path = NSBezierPath()
        let w = self.bounds.width
        let h = self.bounds.height
        for (i, value) in self.values.enumerated() {
            let x = CGFloat(i) / CGFloat(self.values.count - 1) * w
            // Non-flipped view inside a flipped row: higher values draw
            // toward the TOP of the band (100% up, nominal thermal low).
            let y = 2 + CGFloat((value - lo) / (hi - lo)) * (h - 5)
            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        self.strokeColor.setStroke()
        path.stroke()
    }
}

// MARK: - chrome helpers

private final class UnifiedFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private func unifiedLabel(_ string: String = "", font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) -> NSTextField {
    let field = NSTextField(labelWithString: string)
    field.font = font
    field.textColor = color
    field.alignment = alignment
    field.lineBreakMode = .byTruncatingTail
    return field
}

private func unifiedSymbol(_ name: String, scale: NSImage.SymbolScale = .medium) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(textStyle: .body, scale: scale))
}

private class UnifiedCardView: NSView {
    /// 0 quiet, 1 attention, 2 critical - tints the card background.
    var statusLevel: Int = 0
    
    override var isFlipped: Bool { true }
    
    override func updateLayer() {
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            switch self.statusLevel {
            case 1:
                self.layer?.backgroundColor = UnifiedTokens.amberSoft.cgColor
            case 2:
                self.layer?.backgroundColor = UnifiedTokens.redSoft.cgColor
            default:
                self.layer?.backgroundColor = UnifiedTokens.card.cgColor
            }
            self.layer?.borderColor = UnifiedTokens.cardBorder.cgColor
            self.layer?.shadowColor = NSColor(white: 0, alpha: UnifiedTokens.cardShadowAlpha).cgColor
        }
    }
    
    override func layout() {
        super.layout()
        // mock: --shadow-card, 0 1px 2px
        self.layer?.shadowOpacity = 1
        self.layer?.shadowOffset = NSSize(width: 0, height: -1)
        self.layer?.shadowRadius = 2
    }
}

private final class UnifiedHairline: NSView {
    override func updateLayer() {
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = UnifiedTokens.hairline.cgColor
        }
    }
}

/// Small rounded status chip (header verdict, island).
private final class UnifiedChipView: NSView {
    let textField = unifiedLabel(font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
    /// 0 quiet, 1 attention, 2 critical.
    var level: Int = 0
    
    override var isFlipped: Bool { true }
    
    init() {
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.cornerRadius = UnifiedTokens.chipRadius
        self.addSubview(self.textField)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            switch self.level {
            case 1:
                self.layer?.backgroundColor = UnifiedTokens.amberSoft.cgColor
            case 2:
                self.layer?.backgroundColor = UnifiedTokens.redSoft.cgColor
            default:
                self.layer?.backgroundColor = UnifiedTokens.well.cgColor
            }
        }
    }
    
    func setAttributed(_ value: NSAttributedString) {
        self.textField.attributedStringValue = value
        self.textField.sizeToFit()
        let size = self.textField.frame.size
        self.frame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y, width: size.width + 16, height: 20)
        self.textField.frame = NSRect(x: 8, y: 4, width: size.width, height: 13)
    }
}

/// Mini metric column: label, 4pt track + fill, value.
private final class UnifiedMiniMetric: NSView {
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
private final class UnifiedPillRow: NSView {
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
private final class UnifiedDetailRows: NSView {
    private var names: [NSTextField] = []
    private(set) var values: [NSTextField] = []
    
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
        return value
    }
    
    /// Fixed layout; returns the content height for detailHeight sizing.
    @discardableResult
    func layoutRows(width: CGFloat) -> CGFloat {
        var y: CGFloat = 0
        for index in 0..<self.names.count {
            self.names[index].frame = NSRect(x: 0, y: y + 1, width: 180, height: 14)
            self.values[index].frame = NSRect(x: width - 150, y: y + 1, width: 150, height: 14)
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
            self.values[index].isHidden = index >= count
        }
    }
    
    /// Updates a row's label (volume names arrive with the sample).
    func setName(_ index: Int, _ value: String) {
        guard index < self.names.count else { return }
        self.names[index].stringValue = value
    }
}

/// "Top processes" block: title + name/share-bar/value rows.
private final class UnifiedTopProcesses: NSView {
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

// MARK: - hero card

private final class UnifiedHeroCard: UnifiedCardView {
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
        self.addSubview(self.pillRow)
        self.addSubview(self.expandContainer)
        self.expandContainer.isHidden = true
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
    
    /// RAM capacity strip with soft bands at 70/90%.
    func installBullet() {
        let track = NSView()
        track.wantsLayer = true
        track.layer?.cornerRadius = 2
        track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
        let warn = NSView()
        warn.wantsLayer = true
        warn.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.25).cgColor
        let crit = NSView()
        crit.wantsLayer = true
        crit.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.25).cgColor
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

private final class UnifiedGrammarRow: NSView {
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
        self.layoutRow()
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
        // Value field sized to its actual text: the sparkline must end
        // before the TEXT (right-aligned), not before an arbitrary fixed
        // field width — at larger text sizes a fixed 88pt frame left the
        // sparkline running under the value and the chevron.
        let textWidth = (self.valueField.stringValue as NSString).size(withAttributes: [.font: self.valueField.font ?? NSFont.systemFont(ofSize: 12)]).width
        let valueWidth = max(ceil(textWidth) + 4, 44)
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

// MARK: - panel content

final class UnifiedPanelContent: NSView {
    var onLayoutChange: (() -> Void)?
    
    private let island = UnifiedCardView()
    private let islandGlyph = unifiedLabel("▲", font: .systemFont(ofSize: 13, weight: .semibold), color: .systemOrange)
    private let islandTitle = unifiedLabel(font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor)
    private let islandSubtitle = unifiedLabel(font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
    private let islandNote = unifiedLabel(font: .systemFont(ofSize: 10, weight: .regular), color: .systemOrange)
    private let islandDismiss = NSButton()
    private var islandDismissed: Bool = false
    private var islandResolvedUntil: Date? = nil
    private var lastAttentionKey: String = ""
    
    private let brandIcon = NSImageView()
    private let brandLabel = unifiedLabel("Stats", font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
    private let verdictChip = UnifiedChipView()
    
    private let cpuHero = UnifiedHeroCard(module: "CPU", icon: "cpu", detailHeight: 142)
    private let gpuHero = UnifiedHeroCard(module: "GPU", icon: "display", detailHeight: 36)
    private let ramHero = UnifiedHeroCard(module: "RAM", icon: "memorychip", detailHeight: 106)
    private let diskRow = UnifiedGrammarRow(module: "Disk", label: localizedString("Disk"), icon: "internaldrive", expandable: true)
    private let netRow = UnifiedGrammarRow(module: "Network", label: localizedString("Network"), icon: "arrow.up.arrow.down", expandable: true)
    private let sensorsRow = UnifiedGrammarRow(module: "Sensors", label: localizedString("Sensors"), icon: "thermometer.medium", expandable: true)
    private let thermalRow = UnifiedGrammarRow(module: "Thermal", label: localizedString("Thermal"), icon: "thermometer.low", expandable: true)
    private let batteryRow = UnifiedGrammarRow(module: "Battery", label: localizedString("Battery"), icon: "battery.75percent", expandable: true)
    
    private var expandedSection: String? = nil
    private var lastVerdictKey: String = ""
    private var lastContentFrame: NSRect = .zero
    private var lastFanAttention: Date? = nil
    /// Set when the user explicitly collapses the Sensors section; the
    /// fan-attention sticky must not fight an explicit collapse for the
    /// rest of the sticky window.
    private var sensorsUserCollapsed = false
    
    // latest samples
    private var cpuLoad: CPU_Load?
    private var cpuFreqValue: Double?
    private var cpuTempValue: Double?
    private var cpuAvg: CPU_AverageLoad?
    private var cpuTop: [TopProcess] = []
    private var gpuInfo: GPU_Info?
    private var ramUsage: RAM_Usage?
    private var ramTop: [TopProcess] = []
    private var sensorsList: Sensors_List?
    
    private var cpuDetail: NSView!
    private var gpuDetail: NSView!
    private var ramDetail: NSView!
    private var sensorsFansContainer: NSView!
    private var batteryDetailContainer: UnifiedFlippedView!
    private var batteryCyclesField: NSTextField?
    private var batteryHealthField: NSTextField?
    private var batteryConditionField: NSTextField?
    // expandable grammar-row details (Disk / Network / Thermal)
    private var diskDetail: UnifiedDetailRows!
    private var diskReadField: NSTextField?
    private var diskWriteField: NSTextField?
    private var diskVolumeFields: [NSTextField] = []
    private var netDetail: UnifiedDetailRows!
    private var netDownField: NSTextField?
    private var netUpField: NSTextField?
    private var netTotalInField: NSTextField?
    private var netTotalOutField: NSTextField?
    private var netInterfaceField: NSTextField?
    private var thermalDetail: UnifiedDetailRows!
    private var thermalStateField: NSTextField?
    private var thermalImpactField: NSTextField?
    
    override var isFlipped: Bool { true }
    
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        self.wantsLayer = true
        
        self.island.wantsLayer = true
        self.island.layer?.cornerRadius = UnifiedTokens.cardRadius
        self.island.layer?.borderWidth = 1
        self.island.addSubview(self.islandGlyph)
        self.island.addSubview(self.islandTitle)
        self.island.addSubview(self.islandSubtitle)
        self.island.addSubview(self.islandNote)
        self.islandDismiss.isBordered = false
        self.islandDismiss.title = "×"
        self.islandDismiss.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        self.islandDismiss.contentTintColor = .secondaryLabelColor
        self.islandDismiss.target = self
        self.islandDismiss.action = #selector(self.dismissIsland)
        self.island.addSubview(self.islandDismiss)
        self.island.isHidden = true
        self.islandDismiss.wantsLayer = true
        self.islandDismiss.layer?.cornerRadius = 10
        
        self.brandIcon.image = unifiedSymbol("chart.bar.fill", scale: .small)
        self.brandIcon.contentTintColor = .controlAccentColor
        self.addSubview(self.brandIcon)
        self.addSubview(self.brandLabel)
        self.addSubview(self.verdictChip)
        
        self.ramHero.installBullet()
        for hero in [self.cpuHero, self.gpuHero, self.ramHero] {
            self.addSubview(hero)
            hero.onToggle = { [weak self] in self?.toggleSection(hero.module) }
        }
        self.cpuDetail = self.buildCPUDetail()
        self.gpuDetail = self.buildGPUDetail()
        self.ramDetail = self.buildRAMDetail()
        self.cpuHero.expandContainer.addSubview(self.cpuDetail)
        self.gpuHero.expandContainer.addSubview(self.gpuDetail)
        self.ramHero.expandContainer.addSubview(self.ramDetail)
        
        for row in [self.diskRow, self.netRow, self.sensorsRow, self.thermalRow, self.batteryRow] {
            self.addSubview(row)
            row.onToggle = { [weak self] in self?.toggleSection(row.module) }
        }
        self.sensorsFansContainer = UnifiedFlippedView()
        self.sensorsRow.expandContainer.addSubview(self.sensorsFansContainer)
        self.sensorsRow.detailHeight = 150
        self.sensorsRow.layoutRow()
        
        // Battery health detail: cycles / health / condition rows in the
        // same label-left, value-right grammar as the fan temperature rows.
        self.batteryDetailContainer = UnifiedFlippedView()
        self.batteryRow.expandContainer.addSubview(self.batteryDetailContainer)
        self.batteryRow.detailHeight = 60
        self.batteryCyclesField = self.batteryDetailRow(localizedString("Cycles"))
        self.batteryHealthField = self.batteryDetailRow(localizedString("Health"))
        self.batteryConditionField = self.batteryDetailRow(localizedString("Condition"))
        self.layoutBatteryDetail()
        
        // Disk / Network / Thermal details: fixed-height grammar blocks
        // updated per tick. Row counts are fixed at build (volumes beyond
        // the live set are hidden, height reserved) so expanding is a
        // single layout pass.
        self.diskDetail = UnifiedDetailRows()
        self.diskRow.expandContainer.addSubview(self.diskDetail)
        self.diskRow.detailHeight = 90
        self.diskReadField = self.diskDetail.addRow(localizedString("Read"))
        self.diskWriteField = self.diskDetail.addRow(localizedString("Write"))
        self.diskReadField?.stringValue = "–"
        self.diskWriteField?.stringValue = "–"
        for _ in 0..<3 {
            let field = self.diskDetail.addRow("")
            field.stringValue = "–"
            self.diskVolumeFields.append(field)
        }
        self.diskDetail.setLiveRows(2)
        
        self.netDetail = UnifiedDetailRows()
        self.netRow.expandContainer.addSubview(self.netDetail)
        self.netRow.detailHeight = 90
        self.netDownField = self.netDetail.addRow(localizedString("Download"))
        self.netUpField = self.netDetail.addRow(localizedString("Upload"))
        self.netTotalInField = self.netDetail.addRow(localizedString("Total in (since open)"))
        self.netTotalOutField = self.netDetail.addRow(localizedString("Total out (since open)"))
        self.netInterfaceField = self.netDetail.addRow(localizedString("Interface"))
        for field in [self.netDownField, self.netUpField, self.netTotalInField, self.netTotalOutField, self.netInterfaceField] {
            field?.stringValue = "–"
        }
        
        self.thermalDetail = UnifiedDetailRows()
        self.thermalRow.expandContainer.addSubview(self.thermalDetail)
        self.thermalRow.detailHeight = 40
        self.thermalStateField = self.thermalDetail.addRow(localizedString("Thermal state"))
        self.thermalImpactField = self.thermalDetail.addRow(localizedString("Impact"))
        self.thermalStateField?.stringValue = "–"
        self.thermalImpactField?.stringValue = "–"
        self.thermalDetail.setLiveRows(2)
        
        self.verdictChip.setAttributed(Self.attributedVerdict(quiet: true))
        
        // Fixed-scale row charts: battery percentage (0...100) and the
        // thermal pressure level (normalized to the same range).
        self.batteryRow.spark.scale = .fixed
        self.thermalRow.spark.scale = .fixed
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.sample(_:)), name: .unifiedPanelSample, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.thermalStateChanged(_:)), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        self.updateThermalRow()
        
        self.relayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - layout
    
    @discardableResult
    func relayout() -> CGFloat {
        UnifiedPerf.measure("relayout") {
            self.relayoutInner()
        }
        return self.frame.height
    }
    
    private func relayoutInner() {
        let margin: CGFloat = UnifiedTokens.contentMargin
        let w = self.bounds.width
        let wasAtTop = self.bounds.minY < 8
        var y: CGFloat = margin
        
        let attentions = AttentionEvaluator.shared.attentions
        self.updateIsland(attentions: attentions, width: w - margin * 2)
        
        self.cpuHero.setStatus(level: Self.statusLevel(of: "CPU", in: attentions))
        self.gpuHero.setStatus(level: Self.statusLevel(of: "GPU", in: attentions))
        self.ramHero.setStatus(level: Self.statusLevel(of: "RAM", in: attentions))
        self.sensorsRow.setStatus(level: Self.statusLevel(of: "Sensors", in: attentions))
        self.batteryRow.setStatus(level: Self.statusLevel(of: "Battery", in: attentions))
        
        self.brandIcon.frame = NSRect(x: margin + 2, y: y + 3, width: 14, height: 14)
        self.brandLabel.frame = NSRect(x: margin + 20, y: y + 1, width: 120, height: 18)
        let level = attentions.map({ $0.level.rawValue }).max() ?? 0
        let verdictKey = attentions.isEmpty ? "quiet" : "alert-\(level)"
        if verdictKey != self.lastVerdictKey {
            self.lastVerdictKey = verdictKey
            self.verdictChip.level = level
            self.verdictChip.setAttributed(Self.attributedVerdict(quiet: attentions.isEmpty))
        }
        self.verdictChip.frame.origin = NSPoint(x: w - margin - self.verdictChip.frame.width, y: y)
        y += 30
        
        for hero in [self.cpuHero, self.gpuHero, self.ramHero] {
            hero.frame = NSRect(x: margin, y: y, width: w - margin * 2, height: hero.totalHeight)
            hero.layoutCard()
            if hero.module == "RAM" {
                hero.setBullet(self.ramUsage?.usage ?? 0)
            }
            y += hero.totalHeight + 8
        }
        y += 4
        
        // Fan attention surfaces the controls: the Sensors row expands for
        // the sticky window after a fan attention event. The sticky goes
        // through the shared expandedSection state (never a bare
        // setExpanded) so the header tap computes the toggle correctly,
        // and an explicit user collapse wins for the rest of the window —
        // otherwise a manual fan (held attention) re-opened the section
        // every tick and the panel could never collapse.
        if attentions.contains(where: { $0.kind == .fan }) {
            self.lastFanAttention = Date()
        }
        let fanSticky = self.lastFanAttention.map { Date().timeIntervalSince($0) < 6 } ?? false
        if !fanSticky {
            self.sensorsUserCollapsed = false
        }
        if fanSticky && !self.sensorsUserCollapsed && self.expandedSection == nil {
            self.expandedSection = "Sensors"
        }
        self.sensorsRow.setExpanded(self.expandedSection == "Sensors")
        
        for (index, row) in [self.diskRow, self.netRow, self.sensorsRow, self.thermalRow, self.batteryRow].enumerated() {
            row.frame = NSRect(x: margin, y: y, width: w - margin * 2, height: row.totalHeight)
            row.layoutRow()
            if index == 0 {
                // keep the hairline separator at the top of the rows block
            }
            y += row.totalHeight
        }
        self.updateThermalRow()
        self.layoutBatteryDetail()
        self.diskDetail.layoutRows(width: max(self.diskRow.expandContainer.bounds.width, 100))
        self.netDetail.layoutRows(width: max(self.netRow.expandContainer.bounds.width, 100))
        self.thermalDetail.layoutRows(width: max(self.thermalRow.expandContainer.bounds.width, 100))
        y += margin
        let newFrame = NSRect(x: 0, y: 0, width: w, height: max(y, 1))
        if newFrame != self.frame {
            if self.frame.height > 0, abs(newFrame.height - self.frame.height) > 1 {
                // name the sections driving a real height change — the
                // layout-jump forensics line (island flap, fan rebuild,
                // expand): which section grew or shrank
                let sections: [(String, CGFloat)] = [
                    ("CPU", self.cpuHero.totalHeight), ("GPU", self.gpuHero.totalHeight),
                    ("RAM", self.ramHero.totalHeight), ("Disk", self.diskRow.totalHeight),
                    ("Network", self.netRow.totalHeight), ("Sensors", self.sensorsRow.totalHeight),
                    ("Thermal", self.thermalRow.totalHeight), ("Battery", self.batteryRow.totalHeight)
                ]
                let dump = sections.map({ "\($0.0)=\($0.1)" }).joined(separator: " ")
                NSLog("[UnifiedPerf] content height changed %.0f -> %.0f island=%d %@",
                      self.frame.height, newFrame.height, self.island.isHidden ? 0 : 1, dump)
            }
            UnifiedPerf.frameSet("content")
            self.frame = newFrame
        }
        if wasAtTop {
            // Inserting/removing the island grows the document and AppKit
            // shifts the bounds to keep content stable; re-assert the top
            // asynchronously so that adjustment cannot override it.
            DispatchQueue.main.async {
                self.scroll(NSPoint(x: 0, y: 0))
            }
        }
    }
    
    private func toggleSection(_ module: String) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let heightBefore = self.frame.height
        let target = self.expandedSection == module ? nil : module
        self.expandedSection = target
        if module == "Sensors" {
            self.sensorsUserCollapsed = target == nil
        }
        for hero in [self.cpuHero, self.gpuHero, self.ramHero] {
            hero.setExpanded(hero.module == target)
        }
        self.sensorsRow.setExpanded(target == "Sensors")
        self.batteryRow.setExpanded(target == "Battery")
        self.diskRow.setExpanded(target == "Disk")
        self.netRow.setExpanded(target == "Network")
        self.thermalRow.setExpanded(target == "Thermal")
        self.relayout()
        NSLog("[UnifiedPerf] expand %@ latency=%.1fms content %.0f->%.0f detail=%.0f",
              module, (CFAbsoluteTimeGetCurrent() - t0) * 1000, heightBefore, self.frame.height,
              self.sensorsRow.detailHeight)
        self.onLayoutChange?()
    }
    
    /// Pinned-above-document space the island needs (0 when hidden).
    var islandSpace: CGFloat {
        self.island.isHidden ? 0 : 54
    }
    
    /// The island view is hosted by the panel above the scroll view.
    var islandView: NSView { self.island }
    
    func layoutIsland(width: CGFloat) {
        let margin = UnifiedTokens.contentMargin
        self.island.frame = NSRect(x: margin, y: 0, width: width - margin * 2, height: 46)
        self.islandGlyph.frame = NSRect(x: 12, y: 14, width: 16, height: 16)
        self.islandTitle.frame = NSRect(x: 34, y: 8, width: self.island.frame.width - 150, height: 15)
        self.islandSubtitle.frame = NSRect(x: 34, y: 25, width: self.island.frame.width - 150, height: 14)
        self.islandNote.frame = NSRect(x: self.island.frame.width - 96, y: 16, width: 56, height: 13)
        self.islandNote.alignment = .right
        self.islandDismiss.frame = NSRect(x: self.island.frame.width - 34, y: 12, width: 20, height: 20)
    }
    
    private func updateIsland(attentions: [Attention], width: CGFloat) {
        // Key on kind/module/level only — never on the label text, which
        // carries live values ("TCMb 94°C") and would re-arm the island
        // on every sample while a metric hovers near its threshold.
        let key = attentions.map({ "\($0.kind.rawValue)-\($0.module)-\($0.level.rawValue)" }).sorted().joined(separator: "|")
        if attentions.isEmpty {
            if !self.lastAttentionKey.isEmpty {
                // attentions just cleared: brief "back to nominal" note
                self.islandResolvedUntil = Date().addingTimeInterval(6)
            }
            self.lastAttentionKey = ""
            if let until = self.islandResolvedUntil, until > Date() {
                self.island.isHidden = false
                self.island.statusLevel = 0
                self.islandGlyph.stringValue = "✓"
                self.islandGlyph.textColor = UnifiedTokens.ok
                self.islandTitle.stringValue = localizedString("Back to nominal")
                self.islandTitle.textColor = .labelColor
                self.islandSubtitle.stringValue = ""
                self.islandNote.stringValue = ""
                self.islandDismiss.isHidden = true
            } else {
                self.island.isHidden = true
                self.islandResolvedUntil = nil
            }
            return
        }
        
        self.islandResolvedUntil = nil
        if key != self.lastAttentionKey {
            // a new attention set re-arms a previously dismissed island
            self.islandDismissed = false
            self.lastAttentionKey = key
        }
        self.island.isHidden = self.islandDismissed
        let level = attentions.map({ $0.level.rawValue }).max() ?? 1
        if self.island.statusLevel != level {
            self.island.statusLevel = level
            self.island.layer?.borderColor = UnifiedTokens.amberBorder.cgColor
        }
        self.islandGlyph.stringValue = "▲"
        self.islandGlyph.textColor = level == 2 ? UnifiedTokens.redInk : UnifiedTokens.amberInk
        self.islandTitle.stringValue = attentions.first?.label ?? ""
        self.islandTitle.textColor = level == 2 ? UnifiedTokens.redInk : UnifiedTokens.amberInk
        self.islandSubtitle.stringValue = Array(attentions.dropFirst()).map({ $0.label }).joined(separator: " · ")
        self.islandNote.stringValue = localizedString("auto-resolves")
        self.islandNote.textColor = UnifiedTokens.amberInk
        self.islandDismiss.isHidden = false
        self.islandDismiss.contentTintColor = .secondaryLabelColor
    }
    
    @objc private func dismissIsland() {
        self.islandDismissed = true
        self.relayout()
    }
    
    private static func statusLevel(of module: String, in attentions: [Attention]) -> Int {
        attentions.filter({ $0.module == module }).map({ $0.level.rawValue }).max() ?? 0
    }
    
    /// Harness QA (STATS_POPUP_EXPAND=<module>): expand a section at open.
    func expandSection(_ module: String) {
        if self.expandedSection != module {
            self.toggleSection(module)
        }
    }
    
    /// QA hook for the header-tap path.
    func simulateHeaderTap(_ module: String) {
        for row in [self.sensorsRow, self.batteryRow, self.diskRow, self.netRow, self.thermalRow] where row.module == module {
            row.simulateHeaderTap()
        }
    }
    
    /// QA accessor: whether any section is expanded (collapse assertion).
    var expandedSectionForQA: String? { self.expandedSection }
    
    /// Scroll offset so the named module's section sits near the top.
    func sectionOffset(for module: String) -> CGFloat? {
        for view in [self.cpuHero, self.gpuHero, self.ramHero, self.diskRow, self.netRow, self.sensorsRow, self.thermalRow, self.batteryRow] as [NSView] {
            if (view as? UnifiedHeroCard)?.module == module || (view as? UnifiedGrammarRow)?.module == module {
                return max(view.frame.origin.y - 8, 0)
            }
        }
        return nil
    }
    
    // MARK: - verdict
    
    private static func attributedVerdict(quiet: Bool) -> NSAttributedString {
        let value = NSMutableAttributedString()
        if quiet {
            value.append(NSAttributedString(string: "✓ ", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UnifiedTokens.ok
            ]))
            value.append(NSAttributedString(string: localizedString("All nominal"), attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        } else {
            value.append(NSAttributedString(string: "▲ ", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UnifiedTokens.amberInk
            ]))
            value.append(NSAttributedString(string: localizedString("Attention active"), attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UnifiedTokens.amberInk
            ]))
        }
        return value
    }
    
    // MARK: - detail builders
    
    private func buildCPUDetail() -> NSView {
        let view = UnifiedFlippedView()
        let container = UnifiedFlippedView()
        container.frame = NSRect(x: 0, y: 0, width: 324, height: 178)
        let system = UnifiedMiniMetric(label: localizedString("System"), value: "–", fraction: 0)
        let user = UnifiedMiniMetric(label: localizedString("User"), value: "–", fraction: 0)
        let idle = UnifiedMiniMetric(label: localizedString("Idle"), value: "–", fraction: 0, color: .tertiaryLabelColor)
        container.addSubview(system)
        container.addSubview(user)
        container.addSubview(idle)
        system.frame = NSRect(x: 0, y: 0, width: 100, height: 32)
        user.frame = NSRect(x: 112, y: 0, width: 100, height: 32)
        idle.frame = NSRect(x: 224, y: 0, width: 100, height: 32)
        system.identifier = NSUserInterfaceItemIdentifier("cpu.system")
        user.identifier = NSUserInterfaceItemIdentifier("cpu.user")
        idle.identifier = NSUserInterfaceItemIdentifier("cpu.idle")
        view.addSubview(container)
        container.frame = NSRect(x: 0, y: 0, width: 324, height: 32)
        let tops = UnifiedTopProcesses(title: localizedString("Top processes"),
                                       rows: [("", 0, ""), ("", 0, ""), ("", 0, ""), ("", 0, "")])
        tops.identifier = NSUserInterfaceItemIdentifier("cpu.tops")
        view.addSubview(tops)
        tops.frame = NSRect(x: 0, y: 40, width: 324, height: 132)
        return view
    }
    
    private func buildGPUDetail() -> NSView {
        let view = UnifiedFlippedView()
        let render = UnifiedMiniMetric(label: localizedString("Render"), value: "–", fraction: 0)
        let tiler = UnifiedMiniMetric(label: localizedString("Tiler"), value: "–", fraction: 0)
        let fps = UnifiedMiniMetric(label: localizedString("Frame rate"), value: "–", fraction: 0)
        render.identifier = NSUserInterfaceItemIdentifier("gpu.render")
        tiler.identifier = NSUserInterfaceItemIdentifier("gpu.tiler")
        fps.identifier = NSUserInterfaceItemIdentifier("gpu.fps")
        view.addSubview(render)
        view.addSubview(tiler)
        view.addSubview(fps)
        render.frame = NSRect(x: 0, y: 0, width: 100, height: 32)
        tiler.frame = NSRect(x: 112, y: 0, width: 100, height: 32)
        fps.frame = NSRect(x: 224, y: 0, width: 100, height: 32)
        view.frame = NSRect(x: 0, y: 0, width: 324, height: 32)
        return view
    }
    
    private func buildRAMDetail() -> NSView {
        let view = UnifiedFlippedView()
        let app = UnifiedMiniMetric(label: localizedString("App"), value: "–", fraction: 0)
        let wired = UnifiedMiniMetric(label: localizedString("Wired"), value: "–", fraction: 0)
        let compressed = UnifiedMiniMetric(label: localizedString("Compressed"), value: "–", fraction: 0)
        app.identifier = NSUserInterfaceItemIdentifier("ram.app")
        wired.identifier = NSUserInterfaceItemIdentifier("ram.wired")
        compressed.identifier = NSUserInterfaceItemIdentifier("ram.compressed")
        view.addSubview(app)
        view.addSubview(wired)
        view.addSubview(compressed)
        app.frame = NSRect(x: 0, y: 0, width: 100, height: 32)
        wired.frame = NSRect(x: 112, y: 0, width: 100, height: 32)
        compressed.frame = NSRect(x: 224, y: 0, width: 100, height: 32)
        let tops = UnifiedTopProcesses(title: localizedString("Top processes"),
                                       rows: [("", 0, ""), ("", 0, "")])
        tops.identifier = NSUserInterfaceItemIdentifier("ram.tops")
        view.addSubview(tops)
        tops.frame = NSRect(x: 0, y: 40, width: 324, height: 60)
        view.frame = NSRect(x: 0, y: 0, width: 324, height: 100)
        return view
    }
    
    // MARK: - samples
    
    @objc private func sample(_ notification: Notification) {
        guard let value = notification.object else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            UnifiedPerf.measure("handle") {
                self.handle(value, userInfo: notification.userInfo)
            }
        }
    }
    
    private func handle(_ value: Any, userInfo: [AnyHashable: Any]?) {
        switch value {
        case let load as CPU_Load:
            self.cpuLoad = load
            self.cpuHero.setValue(Int((load.totalUsage * 100).rounded()))
            self.cpuHero.spark.add(load.totalUsage * 100)
            let loadStr = self.cpuAvg.map { "\($0.load1.rounded(toPlaces: 1)) / \($0.load5.rounded(toPlaces: 1)) / \($0.load15.rounded(toPlaces: 1))" } ?? "–"
            let freqStr = self.cpuFreqValue.map { "\(($0/1000).rounded(toPlaces: 2)) GHz" } ?? "–"
            let tempStr = self.cpuTempValue.map { "\(Int($0))°C" } ?? "–"
            self.cpuHero.setPills([freqStr, tempStr, "load \(loadStr)"])
            self.updateMini("cpu.system", value: "\(Int((load.systemLoad * 100).rounded()))%", fraction: load.systemLoad)
            self.updateMini("cpu.user", value: "\(Int((load.userLoad * 100).rounded()))%", fraction: load.userLoad)
            self.updateMini("cpu.idle", value: "\(Int((load.idleLoad * 100).rounded()))%", fraction: load.idleLoad)
        case let freq as CPU_Frequency:
            self.cpuFreqValue = freq.value
        case let temp as Double:
            self.cpuTempValue = temp
        case let avg as CPU_AverageLoad:
            self.cpuAvg = avg
        case let procs as [TopProcess]:
            let module = userInfo?["module"] as? String ?? "CPU"
            if module == "RAM" {
                self.ramTop = procs
                let maxUsage = procs.map({ $0.usage }).max() ?? 0
                let rows = Array(procs.prefix(2)).map { proc in
                    (name: proc.name, share: maxUsage > 0 ? proc.usage / maxUsage : 0, value: Units(bytes: Int64(proc.usage)).getReadableMemory(style: .memory))
                }
                self.replaceTops("ram.tops", title: localizedString("Top processes"), rows: rows)
            } else {
                self.cpuTop = procs
                let maxUsage = procs.map({ $0.usage }).max() ?? 0
                let rows = Array(procs.prefix(4)).map { proc in
                    (name: proc.name, share: maxUsage > 0 ? proc.usage / maxUsage : 0, value: "\(Int(proc.usage.rounded()))%")
                }
                self.replaceTops("cpu.tops", title: localizedString("Top processes"), rows: rows)
            }
        case let gpu as GPU_Info:
            self.gpuInfo = gpu
            let usage = gpu.utilization ?? 0
            self.gpuHero.setValue(Int((usage * 100).rounded()))
            self.gpuHero.spark.add(usage * 100)
            let fps = gpu.fps.map { "\(Int($0)) FPS" } ?? "–"
            let render = gpu.renderUtilization.map { "\(Int(($0 * 100).rounded()))" } ?? "–"
            let tiler = gpu.tilerUtilization.map { "\(Int(($0 * 100).rounded()))" } ?? "–"
            self.gpuHero.setPills([fps, "render \(render)", "tiler \(tiler)"])
            self.updateMini("gpu.render", value: gpu.renderUtilization.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", fraction: gpu.renderUtilization ?? 0)
            self.updateMini("gpu.tiler", value: gpu.tilerUtilization.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", fraction: gpu.tilerUtilization ?? 0)
            self.updateMini("gpu.fps", value: gpu.fps.map { "\(Int($0))" } ?? "–", fraction: min((gpu.fps ?? 0) / 120, 1))
        case let ram as RAM_Usage:
            self.ramUsage = ram
            self.ramHero.setValue(Int((ram.usage * 100).rounded()))
            self.ramHero.spark.add(ram.usage * 100)
            let used = Units(bytes: Int64(ram.used)).getReadableMemory(style: .memory)
            let total = Units(bytes: Int64(ram.total)).getReadableMemory(style: .memory)
            let swap = Units(bytes: Int64(ram.swap.used)).getReadableMemory(style: .memory)
            self.ramHero.setPills(["\(used) of \(total)", ram.pressure.value.rawValue, "swap \(swap)"])
            self.ramHero.setBullet(ram.usage)
            let totalBytes = ram.total == 0 ? 1 : ram.total
            self.updateMini("ram.app", value: Units(bytes: Int64(ram.app)).getReadableMemory(style: .memory), fraction: ram.app / totalBytes)
            self.updateMini("ram.wired", value: Units(bytes: Int64(ram.wired)).getReadableMemory(style: .memory), fraction: ram.wired / totalBytes)
            self.updateMini("ram.compressed", value: Units(bytes: Int64(ram.compressed)).getReadableMemory(style: .memory), fraction: ram.compressed / totalBytes)
        case let disks as Disks:
            let drive = disks.array.first(where: { $0.root }) ?? disks.array.first
            guard let drive else { return }
            let total = Double(drive.activity.read + drive.activity.write)
            self.diskRow.valueField.stringValue = Units(bytes: Int64(total)).getReadableSpeed()
            self.diskRow.spark.add(total / 1024)
            self.diskReadField?.stringValue = Units(bytes: drive.activity.read).getReadableSpeed()
            self.diskWriteField?.stringValue = Units(bytes: drive.activity.write).getReadableSpeed()
            let volumes = disks.array.sorted { ($0.root ? 1 : 0) > ($1.root ? 1 : 0) }
            for (index, field) in self.diskVolumeFields.enumerated() {
                guard index < volumes.count else { continue }
                let volume = volumes[index]
                let used = volume.size - volume.free
                let title = volume.mediaName.isEmpty ? volume.BSDName : volume.mediaName
                self.diskDetail.setName(2 + index, title)
                field.stringValue = "\(Units(bytes: used).getReadableMemory(style: .memory)) of \(Units(bytes: volume.size).getReadableMemory(style: .memory))"
                field.toolTip = title
            }
            self.diskDetail.setLiveRows(min(2 + volumes.count, 5))
        case let net as Network_Usage:
            let down = Units(bytes: net.bandwidth.download).getReadableSpeed(omitUnits: true)
            let up = Units(bytes: net.bandwidth.upload).getReadableSpeed(omitUnits: true)
            self.netRow.valueField.stringValue = "\(down)↓ \(up)↑"
            self.netRow.spark.add(Double(net.bandwidth.download + net.bandwidth.upload) / 1024)
            self.netDownField?.stringValue = Units(bytes: net.bandwidth.download).getReadableSpeed()
            self.netUpField?.stringValue = Units(bytes: net.bandwidth.upload).getReadableSpeed()
            self.netTotalInField?.stringValue = Units(bytes: net.total.download).getReadableMemory(style: .memory)
            self.netTotalOutField?.stringValue = Units(bytes: net.total.upload).getReadableMemory(style: .memory)
            self.netInterfaceField?.stringValue = net.interface?.displayName ?? "–"
        case let sensors as Sensors_List:
            self.sensorsList = sensors
            let temps = sensors.sensors.filter({ $0.type == .temperature && $0.popupState && $0.value.isFinite })
            if let hottest = temps.max(by: { $0.value < $1.value }) {
                self.sensorsRow.valueField.stringValue = hottest.formattedValue
                self.sensorsRow.spark.add(hottest.value)
            }
            self.rebuildFans()
        case let battery as Battery_Usage:
            self.batteryRow.valueField.stringValue = "\(Int((abs(battery.level) * 100).rounded()))%"
            self.batteryRow.spark.add(abs(battery.level) * 100)
            self.batteryCyclesField?.stringValue = "\(battery.cycles)"
            self.batteryHealthField?.stringValue = "\(battery.health)% of design"
            self.batteryConditionField?.stringValue = localizedString(UnifiedInfoFormatters.batteryCondition(battery.health))
        default:
            break
        }
    }
    
    private func updateMini(_ identifier: String, value: String, fraction: Double) {
        for hero in [self.cpuHero, self.gpuHero, self.ramHero] {
            if let metric = hero.expandContainer.findView(withIdentifier: identifier) as? UnifiedMiniMetric {
                metric.set(value: value, fraction: fraction)
            }
        }
    }
    
    private func replaceTops(_ identifier: String, title: String, rows: [(name: String, share: Double, value: String)]) {
        for hero in [self.cpuHero, self.gpuHero, self.ramHero] {
            if let tops = hero.expandContainer.findView(withIdentifier: identifier) as? UnifiedTopProcesses {
                tops.update(rows: rows)
            }
        }
    }
    
    private var fanKeys: [String] = []
    private var fanHeights: [CGFloat] = []
    
    // MARK: - battery health detail
    
    private func batteryDetailRow(_ label: String) -> NSTextField {
        let name = unifiedLabel(label, font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        let value = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .labelColor, alignment: .right)
        name.identifier = NSUserInterfaceItemIdentifier("battery.detail")
        value.identifier = NSUserInterfaceItemIdentifier("battery.detail")
        self.batteryDetailContainer.addSubview(name)
        self.batteryDetailContainer.addSubview(value)
        return value
    }
    
    private func layoutBatteryDetail() {
        let width = max(self.batteryRow.expandContainer.bounds.width, 100)
        var y: CGFloat = 0
        for view in self.batteryDetailContainer.subviews where view.identifier?.rawValue == "battery.detail" {
            guard let field = view as? NSTextField else { continue }
            let isValue = field.alignment == .right
            field.frame = NSRect(x: isValue ? width - 100 : 0, y: y + 1, width: isValue ? 100 : 220, height: 14)
            if !isValue { y += 18 }
        }
        self.batteryDetailContainer.frame = NSRect(x: 0, y: 0, width: width, height: max(ceil(y), 30))
        self.batteryRow.detailHeight = max(ceil(y), 30)
    }
    
    // MARK: - thermal pressure row
    
    @objc private func thermalStateChanged(_ notification: Notification) {
        self.updateThermalRow()
    }
    
    private func updateThermalRow() {
        let state = ProcessInfo.processInfo.thermalState
        let name = localizedString(UnifiedInfoFormatters.thermalStateName(state))
        if self.thermalRow.valueField.stringValue != name {
            self.thermalRow.valueField.stringValue = name
        }
        self.thermalRow.setStatus(level: UnifiedInfoFormatters.thermalStatusLevel(state))
        // Step series of the pressure level, normalized to the fixed
        // 0...100 chart range: nominal sits at the bottom, a state change
        // jumps the line by a third of the height. Fed per tick (this
        // runs from every relayout) and on state-change notifications.
        self.thermalRow.spark.add(Double(state.rawValue) * 100.0 / 3.0)
        // Tint the stroke with the row's semantic state color.
        let stroke: NSColor
        switch state {
        case .fair: stroke = UnifiedTokens.amberInk
        case .serious, .critical: stroke = UnifiedTokens.redInk
        default: stroke = UnifiedTokens.ok
        }
        if self.thermalRow.spark.strokeColor != stroke {
            self.thermalRow.spark.strokeColor = stroke
        }
        // Detail rows: state word + plain-language impact, tinted per
        // state, updated in place.
        self.thermalStateField?.stringValue = name
        let impact = localizedString(UnifiedInfoFormatters.thermalStateDescription(state))
        self.thermalImpactField?.stringValue = impact
        self.thermalImpactField?.textColor = stroke
    }
    
    private func rebuildFans() {
        guard let sensors = self.sensorsList else { return }
        let fans = sensors.sensors.compactMap({ $0 as? Fan }).filter({ !$0.isComputed && $0.maxSpeed > 1 })
        let keys = fans.map({ $0.key }).sorted()
        if keys != self.fanKeys {
            self.fanKeys = keys
            for view in self.sensorsFansContainer.subviews {
                view.removeFromSuperview()
            }
            for fan in fans {
                // The module's own fan control: it sizes itself and reports
                // height changes through the callback.
                let fanView = FanView(fan, width: self.sensorsRow.expandContainer.bounds.width) { [weak self] in
                    self?.layoutFanContainer()
                    self?.relayout()
                    self?.onLayoutChange?()
                }
                self.sensorsFansContainer.addSubview(fanView)
            }
            // Measure synchronously so the expanded height is final in
            // the same pass — the previous async measure produced a
            // second layout (and a visible height jump) a beat later.
            self.sensorsFansContainer.layoutSubtreeIfNeeded()
            self.fanHeights = self.sensorsFansContainer.subviews
                .compactMap({ $0 as? FanView })
                .map({ max(ceil($0.frame.height), 64) })
        } else {
            // Same fan set: forward live values. The reader keeps sensor
            // order stable, so index pairing is exact — without this the
            // expanded card froze fan values at build time.
            let fanViews = self.sensorsFansContainer.subviews.compactMap({ $0 as? FanView })
            for (index, fanView) in fanViews.enumerated() where index < fans.count {
                fanView.update(fans[index])
            }
        }
        // Temperature rows: rebuilt each sample so values and ordering
        // (they sort by value) stay live under load.
        for view in self.sensorsFansContainer.subviews where view.identifier?.rawValue == "temp" {
            view.removeFromSuperview()
        }
        let temps = sensors.sensors
            .filter({ $0.type == .temperature && $0.popupState && $0.value.isFinite })
            .sorted(by: { $0.value > $1.value })
            .prefix(3)
        for temp in temps {
            let label = unifiedLabel(temp.name, font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
            let value = unifiedLabel(temp.formattedValue, font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .labelColor, alignment: .right)
            label.identifier = NSUserInterfaceItemIdentifier("temp")
            value.identifier = NSUserInterfaceItemIdentifier("temp")
            self.sensorsFansContainer.addSubview(label)
            self.sensorsFansContainer.addSubview(value)
        }
        self.layoutFanContainer()
        self.onLayoutChange?()
    }
    
    private func layoutFanContainer() {
        let width = max(self.sensorsRow.expandContainer.bounds.width, 100)
        var y: CGFloat = 0
        var index = 0
        for case let fanView as FanView in self.sensorsFansContainer.subviews {
            let height = index < self.fanHeights.count ? self.fanHeights[index] : max(ceil(fanView.frame.height), 64)
            fanView.frame = NSRect(x: 0, y: y, width: width, height: height)
            y += height + 6
            index += 1
        }
        for view in self.sensorsFansContainer.subviews where view.identifier?.rawValue == "temp" {
            if view is NSTextField, let field = view as? NSTextField {
                let isValue = field.alignment == .right
                field.frame = NSRect(x: isValue ? width - 100 : 0, y: y + 1, width: isValue ? 100 : 220, height: 14)
                if !isValue { y += 18 }
            }
        }
        let height = max(ceil(y), 30)
        self.sensorsFansContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
        self.sensorsRow.detailHeight = height
        self.sensorsRow.expandContainer.frame = NSRect(x: 8, y: 44, width: self.sensorsRow.bounds.width - 16, height: height)
    }
}

private extension UnifiedMiniMetric {
    func set(value: String, fraction: Double) {
        self.valueField.stringValue = value
        self.fill.frame = NSRect(x: 0, y: 28, width: 96 * CGFloat(min(max(fraction, 0), 1)), height: 4)
    }
}

private extension NSView {
    func findView(withIdentifier identifier: String) -> NSView? {
        if self.identifier?.rawValue == identifier {
            return self
        }
        for subview in self.subviews {
            if let found = subview.findView(withIdentifier: identifier) {
                return found
            }
        }
        return nil
    }
}
