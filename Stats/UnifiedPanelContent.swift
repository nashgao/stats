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
            let y = 2 + (1 - CGFloat((value - lo) / (hi - lo))) * (h - 5)
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
                self.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.16).cgColor
            case 2:
                self.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.16).cgColor
            default:
                self.layer?.backgroundColor = Constants.Design.surfaceGroup.withAlphaComponent(0.6).cgColor
            }
        }
    }
}

private final class UnifiedHairline: NSView {
    override func updateLayer() {
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        }
    }
}

/// Small rounded status chip (header verdict, island).
private final class UnifiedChipView: NSView {
    let textField = unifiedLabel(font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
    
    override var isFlipped: Bool { true }
    
    init() {
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.cornerRadius = 8
        self.addSubview(self.textField)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.12).cgColor
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

/// "Top processes" block: title + name/share-bar/value rows.
private final class UnifiedTopProcesses: NSView {
    override var isFlipped: Bool { true }
    
    init(title: String, rows: [(name: String, share: Double, value: String)]) {
        super.init(frame: .zero)
        let titleField = unifiedLabel(title.uppercased(), font: .systemFont(ofSize: 10, weight: .semibold), color: .tertiaryLabelColor)
        self.addSubview(titleField)
        titleField.frame = NSRect(x: 0, y: 0, width: 240, height: 12)
        var y: CGFloat = 16
        for row in rows {
            let name = unifiedLabel(row.name, font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
            let value = unifiedLabel(row.value, font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .labelColor, alignment: .right)
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
            fill.frame = NSRect(x: 114, y: y + 6, width: 130 * CGFloat(min(max(row.share, 0), 1)), height: 4)
            value.frame = NSRect(x: 248, y: y + 1, width: 76, height: 14)
            y += 19
        }
        self.frame = NSRect(x: 0, y: 0, width: 324, height: y)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - hero card

private final class UnifiedHeroCard: UnifiedCardView {
    let module: String
    let nameLabel = unifiedLabel(font: .systemFont(ofSize: 12, weight: .semibold), color: .labelColor)
    let valueField = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 26, weight: .semibold), color: .labelColor, alignment: .right)
    let subLabel = unifiedLabel(font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
    let chevron = NSButton()
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
        self.layer?.cornerRadius = 12
        self.nameLabel.stringValue = module
        
        self.iconView.image = unifiedSymbol(icon)
        self.iconView.contentTintColor = .controlAccentColor
        self.addSubview(self.iconView)
        self.addSubview(self.nameLabel)
        self.addSubview(self.valueField)
        
        self.chevron.isBordered = false
        self.chevron.imageScaling = .scaleProportionallyDown
        self.chevron.image = unifiedSymbol("chevron.right", scale: .small)
        self.chevron.contentTintColor = .secondaryLabelColor
        self.chevron.target = self
        self.chevron.action = #selector(self.toggle)
        self.addSubview(self.chevron)
        self.addSubview(self.subLabel)
        self.addSubview(self.expandContainer)
        self.expandContainer.isHidden = true
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
        track.frame = NSRect(x: x, y: 60, width: width, height: 4)
        self.bulletBands[0].frame = NSRect(x: x + width * 0.7, y: 60, width: width * 0.2, height: 4)
        self.bulletBands[1].frame = NSRect(x: x + width * 0.9, y: 60, width: width * 0.1, height: 4)
        self.bulletFill?.frame = NSRect(x: x, y: 60, width: width * CGFloat(min(max(fraction, 0), 1)), height: 4)
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
        self.statusLevel = level
        self.valueField.textColor = level == 2 ? .systemRed : (level == 1 ? .systemOrange : .labelColor)
        self.updateLayer()
    }
    
    var collapsedHeight: CGFloat {
        self.bulletTrack == nil ? 64 : 72
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
        self.subLabel.frame = NSRect(x: 36, y: 40, width: w - 48, height: 14)
        self.expandContainer.frame = NSRect(x: 12, y: self.collapsedHeight - 8, width: w - 24, height: self.detailHeight)
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
    
    init(module: String, label: String, icon: String, expandable: Bool) {
        self.module = module
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
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func toggle() {
        self.onToggle?()
    }
    
    func setExpanded(_ state: Bool) {
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
                self.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.12).cgColor
            case 2:
                self.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
            default:
                self.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
    
    /// Redundant encoding for attention: tint plus glyph, never hue alone.
    func setStatus(level: Int) {
        self.statusLevel = level
        if level == 0 {
            self.glyphField.stringValue = "✓"
            self.glyphField.textColor = .systemGreen
        } else {
            self.glyphField.stringValue = "▲"
            self.glyphField.textColor = level == 2 ? .systemRed : .systemOrange
        }
        self.updateLayer()
    }
    
    var totalHeight: CGFloat {
        40 + (self.expanded ? self.detailHeight + 8 : 0)
    }
    
    func layoutRow() {
        let w = self.bounds.width
        self.hairline.frame = NSRect(x: 0, y: 0, width: w, height: 1)
        self.iconView.frame = NSRect(x: 4, y: 12, width: 16, height: 16)
        self.nameLabel.frame = NSRect(x: 26, y: 12, width: 70, height: 16)
        self.glyphField.frame = NSRect(x: w - 4 - 14, y: 13, width: 14, height: 14)
        self.chevron.frame = NSRect(x: w - 4 - 14, y: 13, width: 14, height: 14)
        let valueWidth: CGFloat = 88
        self.valueField.frame = NSRect(x: w - 4 - 14 - 8 - valueWidth, y: 12, width: valueWidth, height: 16)
        let sparkX: CGFloat = 100
        let sparkEnd = self.valueField.frame.origin.x - 8
        self.spark.frame = NSRect(x: sparkX, y: 6, width: max(sparkEnd - sparkX, 40), height: 28)
        self.expandContainer.frame = NSRect(x: 8, y: 44, width: w - 16, height: self.detailHeight)
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
    private let gpuHero = UnifiedHeroCard(module: "GPU", icon: "gpu.card", detailHeight: 36)
    private let ramHero = UnifiedHeroCard(module: "RAM", icon: "memorychip", detailHeight: 106)
    private let diskRow = UnifiedGrammarRow(module: "Disk", label: localizedString("Disk"), icon: "internaldrive", expandable: false)
    private let netRow = UnifiedGrammarRow(module: "Network", label: localizedString("Network"), icon: "arrow.up.arrow.down", expandable: false)
    private let sensorsRow = UnifiedGrammarRow(module: "Sensors", label: localizedString("Sensors"), icon: "thermometer.medium", expandable: true)
    private let batteryRow = UnifiedGrammarRow(module: "Battery", label: localizedString("Battery"), icon: "battery.75percent", expandable: false)
    
    private var expandedSection: String? = nil
    
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
    
    override var isFlipped: Bool { true }
    
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        self.wantsLayer = true
        
        self.island.wantsLayer = true
        self.island.layer?.cornerRadius = 12
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
        self.addSubview(self.island)
        
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
        
        for row in [self.diskRow, self.netRow, self.sensorsRow, self.batteryRow] {
            self.addSubview(row)
            row.onToggle = { [weak self] in self?.toggleSection(row.module) }
        }
        self.sensorsFansContainer = UnifiedFlippedView()
        self.sensorsRow.expandContainer.addSubview(self.sensorsFansContainer)
        self.sensorsRow.detailHeight = 150
        self.sensorsRow.layoutRow()
        
        self.verdictChip.setAttributed(Self.attributedVerdict(quiet: true))
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.sample(_:)), name: .unifiedPanelSample, object: nil)
        
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
        let margin: CGFloat = Constants.Popup.margins
        let w = self.bounds.width
        let wasAtTop = self.bounds.minY < 8
        var y: CGFloat = margin
        
        let attentions = AttentionEvaluator.shared.attentions
        self.updateIsland(attentions: attentions, width: w - margin * 2)
        if !self.island.isHidden {
            self.island.frame = NSRect(x: margin, y: y, width: w - margin * 2, height: 46)
            self.islandGlyph.frame = NSRect(x: 12, y: 14, width: 16, height: 16)
            self.islandTitle.frame = NSRect(x: 34, y: 8, width: self.island.frame.width - 150, height: 15)
            self.islandSubtitle.frame = NSRect(x: 34, y: 25, width: self.island.frame.width - 150, height: 14)
            self.islandNote.frame = NSRect(x: self.island.frame.width - 96, y: 16, width: 56, height: 13)
            self.islandNote.alignment = .right
            self.islandDismiss.frame = NSRect(x: self.island.frame.width - 34, y: 12, width: 20, height: 20)
            y += 54
        }
        
        self.cpuHero.setStatus(level: Self.statusLevel(of: "CPU", in: attentions))
        self.gpuHero.setStatus(level: Self.statusLevel(of: "GPU", in: attentions))
        self.ramHero.setStatus(level: Self.statusLevel(of: "RAM", in: attentions))
        self.sensorsRow.setStatus(level: Self.statusLevel(of: "Sensors", in: attentions))
        self.batteryRow.setStatus(level: Self.statusLevel(of: "Battery", in: attentions))
        
        self.brandIcon.frame = NSRect(x: margin + 2, y: y + 3, width: 14, height: 14)
        self.brandLabel.frame = NSRect(x: margin + 20, y: y + 1, width: 120, height: 18)
        self.verdictChip.setAttributed(Self.attributedVerdict(quiet: AttentionEvaluator.shared.attentions.isEmpty))
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
        
        for (index, row) in [self.diskRow, self.netRow, self.sensorsRow, self.batteryRow].enumerated() {
            row.frame = NSRect(x: margin, y: y, width: w - margin * 2, height: row.totalHeight)
            row.layoutRow()
            if index == 0 {
                // keep the hairline separator at the top of the rows block
            }
            y += row.totalHeight
        }
        y += margin
        self.frame = NSRect(x: 0, y: 0, width: w, height: max(y, 1))
        if wasAtTop {
            // inserting/removing the island shifts content; keep the top pinned
            self.scroll(NSPoint(x: 0, y: 0))
        }
        return self.frame.height
    }
    
    private func toggleSection(_ module: String) {
        let target = self.expandedSection == module ? nil : module
        self.expandedSection = target
        for hero in [self.cpuHero, self.gpuHero, self.ramHero] {
            hero.setExpanded(hero.module == target)
        }
        self.sensorsRow.setExpanded(target == "Sensors")
        self.relayout()
        self.onLayoutChange?()
    }
    
    private func updateIsland(attentions: [Attention], width: CGFloat) {
        let key = attentions.map({ $0.label }).joined(separator: "|")
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
                self.islandGlyph.textColor = .systemGreen
                self.islandTitle.stringValue = localizedString("Back to nominal")
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
        self.island.statusLevel = level
        self.islandGlyph.stringValue = "▲"
        self.islandGlyph.textColor = level == 2 ? .systemRed : .systemOrange
        self.islandTitle.stringValue = attentions.first?.label ?? ""
        self.islandTitle.textColor = level == 2 ? .systemRed : .systemOrange
        self.islandSubtitle.stringValue = Array(attentions.dropFirst()).map({ $0.label }).joined(separator: " · ")
        self.islandNote.stringValue = localizedString("auto-resolves")
        self.islandDismiss.isHidden = false
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
    
    /// Scroll offset so the named module's section sits near the top.
    func sectionOffset(for module: String) -> CGFloat? {
        for view in [self.cpuHero, self.gpuHero, self.ramHero, self.diskRow, self.netRow, self.sensorsRow, self.batteryRow] as [NSView] {
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
                .foregroundColor: NSColor.systemGreen
            ]))
            value.append(NSAttributedString(string: localizedString("All nominal"), attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        } else {
            value.append(NSAttributedString(string: "▲ ", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.systemOrange
            ]))
            value.append(NSAttributedString(string: localizedString("Attention active"), attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.systemOrange
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
        let tops = UnifiedTopProcesses(title: localizedString("Top processes"), rows: [])
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
        let tops = UnifiedTopProcesses(title: localizedString("Top processes"), rows: [])
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
            self?.handle(value, userInfo: notification.userInfo)
        }
    }
    
    private func handle(_ value: Any, userInfo: [AnyHashable: Any]?) {
        switch value {
        case let load as CPU_Load:
            self.cpuLoad = load
            self.cpuHero.valueField.stringValue = "\(Int((load.totalUsage * 100).rounded()))%"
            let loadStr = self.cpuAvg.map { " · load \($0.load1.rounded(toPlaces: 1)) / \($0.load5.rounded(toPlaces: 1)) / \($0.load15.rounded(toPlaces: 1))" } ?? ""
            let freqStr = self.cpuFreqValue.map { "\(($0/1000).rounded(toPlaces: 2)) GHz" } ?? "–"
            let tempStr = self.cpuTempValue.map { "\(Int($0))°C" } ?? "–"
            self.cpuHero.subLabel.stringValue = "\(freqStr) · \(tempStr)\(loadStr)"
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
            self.gpuHero.valueField.stringValue = "\(Int((usage * 100).rounded()))%"
            let fps = gpu.fps.map { "\(Int($0)) FPS" } ?? "–"
            let render = gpu.renderUtilization.map { "\(Int(($0 * 100).rounded()))" } ?? "–"
            let tiler = gpu.tilerUtilization.map { "\(Int(($0 * 100).rounded()))" } ?? "–"
            self.gpuHero.subLabel.stringValue = "\(fps) · render \(render) · tiler \(tiler)"
            self.updateMini("gpu.render", value: gpu.renderUtilization.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", fraction: gpu.renderUtilization ?? 0)
            self.updateMini("gpu.tiler", value: gpu.tilerUtilization.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", fraction: gpu.tilerUtilization ?? 0)
            self.updateMini("gpu.fps", value: gpu.fps.map { "\(Int($0))" } ?? "–", fraction: min((gpu.fps ?? 0) / 120, 1))
        case let ram as RAM_Usage:
            self.ramUsage = ram
            self.ramHero.valueField.stringValue = "\(Int((ram.usage * 100).rounded()))%"
            let used = Units(bytes: Int64(ram.used)).getReadableMemory(style: .memory)
            let total = Units(bytes: Int64(ram.total)).getReadableMemory(style: .memory)
            let swap = Units(bytes: Int64(ram.swap.used)).getReadableMemory(style: .memory)
            self.ramHero.subLabel.stringValue = "\(used) of \(total) · \(ram.pressure.value.rawValue) pressure · swap \(swap)"
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
        case let net as Network_Usage:
            let down = Units(bytes: net.bandwidth.download).getReadableSpeed(omitUnits: true)
            let up = Units(bytes: net.bandwidth.upload).getReadableSpeed(omitUnits: true)
            self.netRow.valueField.stringValue = "\(down)↓ \(up)↑"
            self.netRow.spark.add(Double(net.bandwidth.download + net.bandwidth.upload) / 1024)
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
            self.batteryRow.spark.add(abs(battery.batteryPower))
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
            if let old = hero.expandContainer.findView(withIdentifier: identifier) {
                let frame = old.frame
                old.removeFromSuperview()
                let tops = UnifiedTopProcesses(title: title, rows: rows)
                tops.identifier = NSUserInterfaceItemIdentifier(identifier)
                hero.expandContainer.addSubview(tops)
                tops.frame = frame
            }
        }
    }
    
    private var fanKeys: [String] = []
    
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
                let fanView = FanView(fan, width: 316) { [weak self] in
                    self?.layoutFanContainer()
                    self?.relayout()
                    self?.onLayoutChange?()
                }
                self.sensorsFansContainer.addSubview(fanView)
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
        }
        self.layoutFanContainer()
        // FanViews size themselves after entering the hierarchy; re-stack once more.
        DispatchQueue.main.async { [weak self] in
            self?.layoutFanContainer()
            self?.relayout()
            self?.onLayoutChange?()
        }
    }
    
    private func layoutFanContainer() {
        let width = max(self.sensorsRow.expandContainer.bounds.width, 100)
        var y: CGFloat = 0
        for case let fanView as FanView in self.sensorsFansContainer.subviews {
            let height = max(fanView.frame.height, 64)
            fanView.frame = NSRect(x: 0, y: y, width: width, height: height)
            y += height + 6
        }
        for view in self.sensorsFansContainer.subviews where view.identifier?.rawValue == "temp" {
            if view is NSTextField, let field = view as? NSTextField {
                let isValue = field.alignment == .right
                field.frame = NSRect(x: isValue ? width - 100 : 0, y: y + 1, width: isValue ? 100 : 220, height: 14)
                if !isValue { y += 18 }
            }
        }
        let height = max(y, 30)
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
