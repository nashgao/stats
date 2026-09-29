//
//  MenuPowerReadout.swift
//  Stats
//
//  Source selection and title composition for the menu bar power
//  readout (the unified status item's live numbers). Extracted from
//  UnifiedPopupController so the hardware boundary and the composition
//  rules are unit-testable: Tests/PanelInfo.swift covers the
//  state × key-availability matrix with a fake probe. See
//  AGENTS.md "Live-metric readouts" for why each source is trusted (all
//  verified live by step-response against a CPU load).
//

import Foundation
import Kit
import IOKit.ps

/// Hardware boundary for the menu watts readout. MenuPowerReadout is
/// pure over this protocol; unit tests inject fakes to cover the
/// state × key-availability matrix that the stuck-readout regressions
/// (84 W pinned delivery, garbage PPBR on AC) rode through.
protocol MenuPowerProbing {
    func smc(_ key: String) -> Double?
    func onBattery() -> Bool
    func chargingOnAC() -> Bool
}

/// Live probe: SMC power keys plus the IOPS power-source state.
struct LiveMenuPowerProbe: MenuPowerProbing {
    func smc(_ key: String) -> Double? { Kit.SMC.shared.getValue(key) }

    func onBattery() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        // Any entry on battery wins — the last-entry-wins loop reported
        // "AC Power" whenever a UPS or second source trailed the list.
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps).takeUnretainedValue() as? [String: Any] {
                if (desc[kIOPSPowerSourceStateKey] as? String ?? "AC Power") == "Battery Power" {
                    return true
                }
            }
        }
        return false
    }

    /// Charging active (not the "not charging" / optimized-charging hold
    /// states, where PDTR is live). STATS_QA_WATTS_CHARGING=1 forces true
    /// so the smoke test can exercise the si10 branch without waiting
    /// for a real charge session; `[QA] watts raw:` keeps the true state
    /// visible.
    func chargingOnAC() -> Bool {
        if ProcessInfo.processInfo.environment["STATS_QA_WATTS_CHARGING"] == "1" {
            return true
        }
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps).takeUnretainedValue() as? [String: Any],
               desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
               desc[kIOPSPowerSourceStateKey] as? String == "AC Power",
               desc[kIOPSIsChargingKey] as? Bool == true {
                return true
            }
        }
        return false
    }
}

/// Source table (all verified live by step-response against a CPU load,
/// 2026-09-25):
/// - on battery: PPBR drain rate;
/// - on AC, not charging: PDTR, which is the total system draw;
/// - on AC, charging: si10 SoC power — the adapter sits at its delivery
///   limit then and the charge current absorbs every load change, so
///   PDTR pins at a constant (the "stuck at 84 W" reports).
/// PPBR reads ~0.6-4 (garbage) on AC, which is why it is never used
/// there; nil only when no SMC power keys respond. Returned as a
/// magnitude: the menu bar shows no sign.
struct MenuPowerReadout {
    let probe: MenuPowerProbing

    func watts() -> Double? {
        let batteryPower = self.probe.smc("PPBR")
        let adapterPower = self.probe.smc("PDTR")
        if self.probe.onBattery() {
            return batteryPower.map(abs)
        }
        if let adapterPower, adapterPower > 0 {
            if self.probe.chargingOnAC(), let soc = self.probe.smc("si10"), soc > 0 {
                return soc
            }
            return adapterPower
        }
        return batteryPower.map(abs)
    }
}

/// Selectable menu-bar readout presets for the unified status item
/// (MEN-1): which live quantities the 1s tick composes into the title.
enum MenuReadoutPreset: String {
    case off
    case watts
    case battery
    case wattsBattery = "watts_battery"
    case batteryTime = "battery_time"
}

/// Storage boundary for the preset: the Store key, the legacy boolean it
/// replaces, and the read-through migration between them. Read-through
/// means nothing writes the legacy key back — when the new key is absent
/// but `unified_widget_power` is true, the preset is watts; once the new
/// key holds a valid value it wins over the legacy boolean.
enum MenuReadoutSelection {
    static let storeKey = "unified_menu_readout"
    static let legacyPowerKey = "unified_widget_power"

    static func current() -> MenuReadoutPreset {
        let stored = Store.shared.string(key: self.storeKey, defaultValue: "")
        if let preset = MenuReadoutPreset(rawValue: stored) {
            return preset
        }
        if Store.shared.bool(key: self.legacyPowerKey, defaultValue: false) {
            return .watts
        }
        return .off
    }
}

/// A single composable quantity in the menu-bar readout (DIS-1). The
/// declaration order is the display order: watts, then battery, then time.
enum MenuReadoutElement: String {
    case watts
    case battery
    case time
}

/// Storage boundary for the element set (DIS-1): comma-separated raw
/// values in a string key — the same idiom Kit/module/widget.swift uses
/// for widget lists. The structural cap (at most two elements) is
/// enforced only at the write boundary: the menu bar item is one or two
/// segments wide, and the stacked layout renders one segment per line.
/// Reads migrate read-through: a non-empty elements key wins, even when
/// every member is unknown (unknown members are skipped, which can yield
/// an empty set); an empty stored value falls through to the MEN-1
/// preset key, below that to the legacy watts boolean, and defaults to
/// the empty set.
enum MenuReadoutElements {
    static let storeKey = "unified_menu_readout_elements"

    /// The MEN-1 presets are exactly the subsets the old composer
    /// supported; the preset mapping in the migration chain runs through
    /// this table.
    static func elements(for preset: MenuReadoutPreset) -> [MenuReadoutElement] {
        switch preset {
        case .off: return []
        case .watts: return [.watts]
        case .battery: return [.battery]
        case .wattsBattery: return [.watts, .battery]
        case .batteryTime: return [.battery, .time]
        }
    }

    /// Write boundary: dedup, keep at most the first two, store the
    /// comma-separated raw values.
    static func save(_ elements: [MenuReadoutElement]) {
        var kept: [MenuReadoutElement] = []
        for element in elements where !kept.contains(element) {
            kept.append(element)
            if kept.count == 2 { break }
        }
        Store.shared.set(key: self.storeKey, value: kept.map { $0.rawValue }.joined(separator: ","))
    }

    static func current() -> [MenuReadoutElement] {
        let stored = Store.shared.string(key: self.storeKey, defaultValue: "")
        if !stored.isEmpty {
            return stored.split(separator: ",").compactMap { MenuReadoutElement(rawValue: String($0)) }
        }
        return self.elements(for: MenuReadoutSelection.current())
    }
}

/// Layout for the composed readout (DIS-1): segments joined on one line,
/// or stacked one per line. A new capability — no migration; horizontal
/// is the default and matches the MEN-1 rendering.
enum MenuReadoutLayout: String {
    case horizontal
    case stacked
}

enum MenuReadoutLayoutSelection {
    static let storeKey = "unified_menu_readout_layout"

    static func current() -> MenuReadoutLayout {
        let stored = Store.shared.string(key: self.storeKey, defaultValue: MenuReadoutLayout.horizontal.rawValue)
        return MenuReadoutLayout(rawValue: stored) ?? .horizontal
    }
}

/// Pure composer for the menu-bar readout (MEN-1, generalized by DIS-1):
/// element subset + live inputs -> title segments, no I/O. The
/// status-item tick gathers the inputs (watts via MenuPowerReadout;
/// battery values via Battery.lastKnownUsage — the same sample the
/// unified panel's Battery row renders) and this struct decides which
/// segments exist. A segment whose input is missing drops out; the
/// element order defines the segment order. The subset is structurally
/// capped at two (MenuReadoutElements.save) — horizontal renders them
/// " · "-joined on one line, stacked newline-joined on two; no segments
/// at all renders as the glyph-only item.
struct MenuReadoutComposer {
    struct Input {
        var watts: Double?
        var batteryLevel: Double?
        var timeToEmptyMinutes: Int?
        var isBatteryPowered: Bool
    }

    /// Title segments for an element subset. Missing inputs drop their
    /// segment; the time segment additionally requires battery power
    /// with a positive estimate (it collapses on AC).
    static func segments(elements: [MenuReadoutElement], input: Input) -> [String] {
        let percent = input.batteryLevel.map { self.percent($0) }
        return elements.compactMap { element in
            switch element {
            case .watts:
                return input.watts.map { UnifiedInfoFormatters.menuWatts($0) }
            case .battery:
                return percent
            case .time:
                guard input.isBatteryPowered, let minutes = input.timeToEmptyMinutes, minutes > 0 else { return nil }
                return UnifiedInfoFormatters.clock(minutes)
            }
        }
    }

    /// Title segments for a preset — the MEN-1 API, still exercised by
    /// Settings until DIS-2. Every preset except battery_time composes
    /// exactly its element subset; battery_time keeps its original
    /// anchored shape (percent required, otherwise no segments) which
    /// the generalized rule would relax.
    static func segments(preset: MenuReadoutPreset, input: Input) -> [String] {
        switch preset {
        case .off:
            return []
        case .batteryTime:
            guard let percent = input.batteryLevel.map({ self.percent($0) }) else { return [] }
            var segments = [percent]
            if input.isBatteryPowered, let minutes = input.timeToEmptyMinutes, minutes > 0 {
                segments.append(UnifiedInfoFormatters.clock(minutes))
            }
            return segments
        case .watts, .battery, .wattsBattery:
            return self.segments(elements: MenuReadoutElements.elements(for: preset), input: input)
        }
    }

    /// Joined title from segments: " · " horizontal, newline stacked;
    /// "" when no segment exists.
    static func title(segments: [String], layout: MenuReadoutLayout) -> String {
        switch layout {
        case .horizontal:
            return segments.joined(separator: " · ")
        case .stacked:
            return segments.joined(separator: "\n")
        }
    }

    /// Joined title for an element subset at a layout.
    static func title(elements: [MenuReadoutElement], input: Input, layout: MenuReadoutLayout) -> String {
        self.title(segments: self.segments(elements: elements, input: input), layout: layout)
    }

    /// Joined title for a preset, horizontal layout — the MEN-1 shape.
    static func title(preset: MenuReadoutPreset, input: Input) -> String {
        self.segments(preset: preset, input: input).joined(separator: " · ")
    }

    /// 0...1 -> "67%". Rounded, not truncated: Int(0.67 * 100) is 66 —
    /// the classic float trap — and Battery's own telemetry rounds.
    static func percent(_ level: Double) -> String {
        "\(Int((min(max(level, 0), 1) * 100).rounded()))%"
    }
}

/// Field-report bundle for "the watts number looks wrong" reports:
/// power state, fresh SMC key reads, and the recent composed readout —
/// the data needed to classify stuck / pinned / garbage without a
/// debugging session. UnifiedPopupController records every distinct
/// composed value; Settings' "Copy diagnostics" button puts this
/// snapshot on the pasteboard.
enum PowerDiagnostics {
    static private(set) var recentSamples: [(date: Date, watts: String)] = []

    static func record(watts: String) {
        if let last = self.recentSamples.last, last.watts == watts { return }
        self.recentSamples.append((Date(), watts))
        if self.recentSamples.count > 12 {
            self.recentSamples.removeFirst(self.recentSamples.count - 12)
        }
    }

    static func snapshot() -> String {
        var lines: [String] = []
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        lines.append("Stats \(version) (build \(build))")
        let probe = LiveMenuPowerProbe()
        lines.append("onBattery: \(probe.onBattery())")
        lines.append("chargingOnAC: \(probe.chargingOnAC())")
        for key in ["PPBR", "PDTR", "si10"] {
            lines.append("SMC \(key): \(probe.smc(key).map { String($0) } ?? "unreadable")")
        }
        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss"
        if self.recentSamples.isEmpty {
            lines.append("menu watts samples: none (readout off, or no ticks since launch)")
        } else {
            lines.append("menu watts samples (newest last):")
            for sample in self.recentSamples {
                lines.append("  \(time.string(from: sample.date)) \(sample.watts)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
