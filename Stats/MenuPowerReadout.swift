//
//  MenuPowerReadout.swift
//  Stats
//
//  Source selection for the menu bar watts readout (the unified status
//  item's live power number). Extracted from UnifiedPopupController so
//  the hardware-boundary protocol is unit-testable: Tests/PanelInfo.swift
//  covers the state × key-availability matrix with a fake probe. See
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
