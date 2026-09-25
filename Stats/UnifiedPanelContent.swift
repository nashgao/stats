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

// MARK: - panel content

final class UnifiedPanelContent: NSView {
    var onLayoutChange: (() -> Void)?
    
    private let brandIcon = NSImageView()
    private let brandLabel = unifiedLabel("Stats", font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
    private let verdictChip = UnifiedChipView()
    
    let cpuHero = UnifiedHeroCard(module: "CPU", icon: "cpu", detailHeight: 178)
    let gpuHero = UnifiedHeroCard(module: "GPU", icon: "display", detailHeight: 36)
    let ramHero = UnifiedHeroCard(module: "RAM", icon: "memorychip", detailHeight: 160)
    let diskRow = UnifiedGrammarRow(module: "Disk", label: localizedString("Disk"), icon: "internaldrive", expandable: true)
    let netRow = UnifiedGrammarRow(module: "Network", label: localizedString("Network"), icon: "arrow.up.arrow.down", expandable: true)
    let sensorsRow = UnifiedGrammarRow(module: "Sensors", label: localizedString("Sensors"), icon: "thermometer.medium", expandable: true)
    let thermalRow = UnifiedGrammarRow(module: "Thermal", label: localizedString("Thermal"), icon: "thermometer.low", expandable: true)
    let batteryRow = UnifiedGrammarRow(module: "Battery", label: localizedString("Battery"), icon: "battery.75percent", expandable: true)
    
    private var expandedSection: String? = nil
    private var lastVerdictKey: String = ""
    private var lastContentFrame: NSRect = .zero
    private var lastFanAttention: Date? = nil
    /// Set by ANY explicit section toggle (the user is driving); the
    /// fan-attention sticky must not auto-open Sensors for the rest of
    /// the sticky window. Resets when the window expires, so the next
    /// attention episode can surface the controls again.
    private var sensorsStickySuppressed = false
    
    // latest samples
    var cpuLoad: CPU_Load?
    var cpuFreqValue: Double?
    var cpuTempValue: Double?
    var cpuAvg: CPU_AverageLoad?
    var cpuTop: [TopProcess] = []
    var gpuInfo: GPU_Info?
    var ramUsage: RAM_Usage?
    var ramTop: [TopProcess] = []
    var sensorsList: Sensors_List?
    
    private var cpuDetail: NSView!
    private var gpuDetail: NSView!
    private var ramDetail: NSView!
    var sensorsFansContainer: NSView!
    var batteryDetailContainer: UnifiedFlippedView!
    var batteryCyclesField: NSTextField?
    var batteryHealthField: NSTextField?
    var batteryFullChargeField: NSTextField?
    var batteryConditionField: NSTextField?
    var batteryPowerField: NSTextField?
    var batteryTimeField: NSTextField?
    // expandable grammar-row details (Disk / Network / Thermal)
    var diskDetail: UnifiedDetailRows!
    var diskReadField: NSTextField?
    var diskWriteField: NSTextField?
    var diskVolumeFields: [NSTextField] = []
    var netDetail: UnifiedDetailRows!
    var netDownField: NSTextField?
    var netUpField: NSTextField?
    var netTotalInField: NSTextField?
    var netTotalOutField: NSTextField?
    var netInterfaceField: NSTextField?
    var netAddressField: NSTextField?
    var thermalDetail: UnifiedDetailRows!
    var thermalStateField: NSTextField?
    var thermalImpactField: NSTextField?
    // CPU/RAM hero detail extras
    var ramDetailRows: UnifiedDetailRows!
    var ramWiredField: NSTextField?
    var ramAppField: NSTextField?
    var ramCompressedField: NSTextField?
    var cpuCoresRowE: UnifiedCoreClusterRowView?
    var cpuCoresRowP: UnifiedCoreClusterRowView?
    private var cpuCoresRows: UnifiedDetailRows?
    var corePartition: (efficiency: [Int], performance: [Int])?
    
    override var isFlipped: Bool { true }
    
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        self.wantsLayer = true
        
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
        
        // CPU per-core clusters (Efficiency / Performance rows): one 3pt
        // tick per core, bottom-anchored fill; fixed 18pt slots.
        self.cpuCoresRowE = UnifiedCoreClusterRowView(frame: .zero)
        self.cpuCoresRowP = UnifiedCoreClusterRowView(frame: .zero)
        let cpuRows = UnifiedDetailRows()
        cpuRows.addCustomRow(localizedString("Efficiency"), custom: self.cpuCoresRowE!)
        cpuRows.addCustomRow(localizedString("Performance"), custom: self.cpuCoresRowP!)
        self.cpuDetail.addSubview(cpuRows)
        self.cpuCoresRows = cpuRows
        
        // RAM breakdown rows (Wired / App / Compressed in GB).
        self.ramDetailRows = UnifiedDetailRows()
        self.ramWiredField = self.ramDetailRows.addRow(localizedString("Wired"))
        self.ramAppField = self.ramDetailRows.addRow(localizedString("App"))
        self.ramCompressedField = self.ramDetailRows.addRow(localizedString("Compressed"))
        for field in [self.ramWiredField, self.ramAppField, self.ramCompressedField] {
            field?.stringValue = "–"
        }
        self.ramDetail.addSubview(self.ramDetailRows)
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
        self.showAllButton.isBordered = false
        self.showAllButton.contentTintColor = .secondaryLabelColor
        self.showAllButton.target = self
        self.showAllButton.action = #selector(self.openAllSensors)
        self.sensorsFansContainer.addSubview(self.showAllButton)
        
        // Battery health detail: cycles / nominal health / full-charge
        // capability / condition, plus live power and time estimates,
        // in the same label-left, value-right grammar as the fan rows.
        // Both health bases are shown (stabilized nominal and momentary
        // full-charge) so neither number looks wrong against external
        // tools.
        self.batteryDetailContainer = UnifiedFlippedView()
        self.batteryRow.expandContainer.addSubview(self.batteryDetailContainer)
        self.batteryRow.detailHeight = 108
        self.batteryCyclesField = self.batteryDetailRow(localizedString("Cycles"))
        self.batteryHealthField = self.batteryDetailRow(localizedString("Health (nominal)"))
        self.batteryFullChargeField = self.batteryDetailRow(localizedString("Full charge"))
        self.batteryConditionField = self.batteryDetailRow(localizedString("Condition"))
        self.batteryPowerField = self.batteryDetailRow(localizedString("Power"))
        self.batteryTimeField = self.batteryDetailRow(localizedString("Time remaining"))
        self.batteryPowerField?.stringValue = "–"
        self.batteryTimeField?.stringValue = "–"
        self.layoutBatteryDetail()
        
        // Disk / Network / Thermal details: fixed-height grammar blocks
        // updated per tick. Row counts are fixed at build (volume slots
        // without a volume are hidden individually, height reserved) so
        // expanding is a single layout pass.
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
        self.diskDetail.setLiveRows(5)
        
        self.netDetail = UnifiedDetailRows()
        self.netRow.expandContainer.addSubview(self.netDetail)
        self.netRow.detailHeight = 108
        self.netDownField = self.netDetail.addRow(localizedString("Download"))
        self.netUpField = self.netDetail.addRow(localizedString("Upload"))
        self.netTotalInField = self.netDetail.addRow(localizedString("Total in (since open)"))
        self.netTotalOutField = self.netDetail.addRow(localizedString("Total out (since open)"))
        self.netInterfaceField = self.netDetail.addRow(localizedString("Interface"))
        self.netAddressField = self.netDetail.addRow(localizedString("Address"))
        for field in [self.netDownField, self.netUpField, self.netTotalInField, self.netTotalOutField, self.netInterfaceField, self.netAddressField] {
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
        
        // The panel mounts after the module readers start, so the battery
        // reader's initial (and DB-restored) broadcast is posted before
        // the observer above exists; unlike the timer-driven readers, the
        // battery reader re-broadcasts only on IOPS changes. Replay the
        // cached sample so the Battery card populates immediately.
        if let battery = modules.first(where: { $0 is Battery }) as? Battery,
           let usage = battery.lastKnownUsage {
            self.sample(Notification(name: .unifiedPanelSample, object: usage))
        }
        
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
            self.sensorsStickySuppressed = false
        }
        if fanSticky && !self.sensorsStickySuppressed && self.expandedSection == nil {
            NSLog("[UnifiedPanelTrace] sticky auto-expanding Sensors (attention episode, nothing expanded)")
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
        self.cpuCoresRows?.layoutRows(width: max(self.cpuHero.expandContainer.bounds.width, 100))
        self.cpuCoresRows?.frame.origin = NSPoint(x: 0, y: 136)
        self.ramDetailRows.layoutRows(width: max(self.ramHero.expandContainer.bounds.width, 100))
        self.ramDetailRows.frame.origin = NSPoint(x: 0, y: 98)
        y += margin
        let newFrame = NSRect(x: 0, y: 0, width: w, height: max(y, 1))
        if newFrame != self.frame {
            if self.frame.height > 0, abs(newFrame.height - self.frame.height) > 1 {
                // name the sections driving a real height change — the
                // layout-jump forensics line (fan rebuild, expand): which
                // section grew or shrank
                let sections: [(String, CGFloat)] = [
                    ("CPU", self.cpuHero.totalHeight), ("GPU", self.gpuHero.totalHeight),
                    ("RAM", self.ramHero.totalHeight), ("Disk", self.diskRow.totalHeight),
                    ("Network", self.netRow.totalHeight), ("Sensors", self.sensorsRow.totalHeight),
                    ("Thermal", self.thermalRow.totalHeight), ("Battery", self.batteryRow.totalHeight)
                ]
                let dump = sections.map({ "\($0.0)=\($0.1)" }).joined(separator: " ")
                NSLog("[UnifiedPerf] content height changed %.0f -> %.0f %@",
                      self.frame.height, newFrame.height, dump)
            }
            UnifiedPerf.frameSet("content")
            self.frame = newFrame
        }
        if wasAtTop {
            // A document resize grows/shrinks the content and AppKit
            // shifts the bounds to keep content stable; re-assert the top
            // asynchronously so that adjustment cannot override it.
            DispatchQueue.main.async {
                self.scroll(NSPoint(x: 0, y: 0))
            }
        }
    }
    
    private func toggleSection(_ module: String, source: String = "user") {
        let t0 = CFAbsoluteTimeGetCurrent()
        let heightBefore = self.frame.height
        let target = self.expandedSection == module ? nil : module
        self.expandedSection = target
        NSLog("[UnifiedPanelTrace] toggleSection %@ source=%@ target=%@ fanSticky=%d suppressed=%d",
              module, source, target ?? "none",
              self.lastFanAttention.map({ Date().timeIntervalSince($0) < 6 }) ?? false ? 1 : 0,
              self.sensorsStickySuppressed ? 1 : 0)
        // Any explicit toggle stands the sticky down for the episode: the
        // user is driving. In particular, collapsing the active section
        // must leave NONE expanded — never auto-reopen a section the user
        // switched away from (A → B → collapse-B must not restore A).
        self.sensorsStickySuppressed = true
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
    
    private static func statusLevel(of module: String, in attentions: [Attention]) -> Int {
        attentions.filter({ $0.module == module }).map({ $0.level.rawValue }).max() ?? 0
    }
    
    /// Harness QA (STATS_POPUP_EXPAND=<module>): expand a section at open.
    func expandSection(_ module: String) {
        if self.expandedSection != module {
            self.toggleSection(module, source: "route")
        }
    }
    
    /// QA hook for the header-tap path.
    func simulateHeaderTap(_ module: String) {
        for row in [self.sensorsRow, self.batteryRow, self.diskRow, self.netRow, self.thermalRow] where row.module == module {
            row.simulateHeaderTap()
        }
        for hero in [self.cpuHero, self.gpuHero, self.ramHero] where hero.module == module {
            hero.simulateHeaderTap()
        }
    }
    
    /// QA accessor: whether any section is expanded (collapse assertion).
    var expandedSectionForQA: String? { self.expandedSection }
    /// QA hook: "name=1" pairs, 1 = collapsed (restore probe).
    var collapsedStatesForQA: String {
        let rows: [(String, Bool)] = [
            ("Sensors", !self.sensorsRow.expanded),
            ("CPU", !self.cpuHero.expanded),
            ("GPU", !self.gpuHero.expanded),
            ("RAM", !self.ramHero.expanded),
            ("Battery", !self.batteryRow.expanded),
            ("Disk", !self.diskRow.expanded),
            ("Network", !self.netRow.expanded),
            ("Thermal", !self.thermalRow.expanded)
        ]
        return rows.map({ "\($0.0)=\($0.1 ? 1 : 0)" }).joined(separator: " ")
    }
    
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
    
    var fanKeys: [String] = []
    var fanHeights: [CGFloat] = []
    /// Option B temperature detail: current visible member keys (hot
    /// first), the latest sample per key, and the live row views. Rows
    /// update values in place; the view order only changes when the
    /// membership actually changes (with a deadband, so a single-sample
    /// swap at the boundary doesn't reshuffle the list).
    var tempKeys: [String] = []
    var latestTemps: [String: Sensor_p] = [:]
    var tempRows: [(key: String, name: NSTextField, value: NSTextField)] = []
    var totalTempCount = 0
    let tempDeadband: Double = 0.5
    let showAllButton = NSButton()
    
    /// Explicit (label, value) pairs — never derive pairing from subview
    /// enumeration order; that z-order dependence shifted every value one
    /// row up (Cycles empty, health showing the cycle count, …).
    var batteryDetailRows: [(name: NSTextField, value: NSTextField)] = []

}
