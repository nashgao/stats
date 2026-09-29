//
//  PanelInfo.swift
//  Tests
//
//  Pure formatter tests for the panel's info rows: battery condition
//  wording from the reader health percentage, thermal pressure
//  state names + row status levels, and the all-sensors popover filter.
//

import XCTest
@testable import Kit
@testable import Sensors
@testable import Stats

final class PanelInfoTests: XCTestCase {
    // MARK: - battery condition
    
    func testBatteryConditionBands() {
        XCTAssertEqual(UnifiedInfoFormatters.batteryCondition(100), "Normal")
        XCTAssertEqual(UnifiedInfoFormatters.batteryCondition(90), "Normal")
        XCTAssertEqual(UnifiedInfoFormatters.batteryCondition(89), "Good")
        XCTAssertEqual(UnifiedInfoFormatters.batteryCondition(80), "Good")
        XCTAssertEqual(UnifiedInfoFormatters.batteryCondition(79), "Fair")
        XCTAssertEqual(UnifiedInfoFormatters.batteryCondition(60), "Fair")
        XCTAssertEqual(UnifiedInfoFormatters.batteryCondition(59), "Poor")
        XCTAssertEqual(UnifiedInfoFormatters.batteryCondition(0), "Poor")
    }
    
    // MARK: - thermal state
    
    func testThermalStateNames() {
        XCTAssertEqual(UnifiedInfoFormatters.thermalStateName(.nominal), "Nominal")
        XCTAssertEqual(UnifiedInfoFormatters.thermalStateName(.fair), "Fair")
        XCTAssertEqual(UnifiedInfoFormatters.thermalStateName(.serious), "Serious")
        XCTAssertEqual(UnifiedInfoFormatters.thermalStateName(.critical), "Critical")
    }
    
    func testThermalStatusLevels() {
        // nominal is the only fully-quiet state; serious and critical
        // share the red tint on the row
        XCTAssertEqual(UnifiedInfoFormatters.thermalStatusLevel(.nominal), 0)
        XCTAssertEqual(UnifiedInfoFormatters.thermalStatusLevel(.fair), 1)
        XCTAssertEqual(UnifiedInfoFormatters.thermalStatusLevel(.serious), 2)
        XCTAssertEqual(UnifiedInfoFormatters.thermalStatusLevel(.critical), 2)
    }
    
    func testThermalStateDescriptions() {
        // short enough for the detail value column
        for state: ProcessInfo.ThermalState in [.nominal, .fair, .serious, .critical] {
            let text = UnifiedInfoFormatters.thermalStateDescription(state)
            XCTAssertFalse(text.isEmpty)
            XCTAssertLessThanOrEqual(text.count, 22, "\(state) description too long")
        }
    }
    
    // MARK: - battery health bases
    
    func testBatteryPercent() {
        XCTAssertEqual(UnifiedInfoFormatters.batteryPercent(8588, of: 8588), 100)
        XCTAssertEqual(UnifiedInfoFormatters.batteryPercent(8113, of: 8588), 94)
        XCTAssertEqual(UnifiedInfoFormatters.batteryPercent(7789, of: 8588), 91)
        XCTAssertEqual(UnifiedInfoFormatters.batteryPercent(90, of: 100), 90)
        XCTAssertEqual(UnifiedInfoFormatters.batteryPercent(0, of: 100), 0)
        XCTAssertEqual(UnifiedInfoFormatters.batteryPercent(100, of: 0), 0)
        // toNearestOrEven rounding, matching the reader's health basis
        XCTAssertEqual(UnifiedInfoFormatters.batteryPercent(999, of: 1000), 100)
    }
    
    // MARK: - compact network rate
    
    func testCompactRate() {
        XCTAssertEqual(UnifiedInfoFormatters.compactRate(0), "0K")
        XCTAssertEqual(UnifiedInfoFormatters.compactRate(400), "0.4K")
        XCTAssertEqual(UnifiedInfoFormatters.compactRate(9_500), "9.5K")
        XCTAssertEqual(UnifiedInfoFormatters.compactRate(18_000_000), "18M")
        XCTAssertEqual(UnifiedInfoFormatters.compactRate(5_500_000), "5.5M")
        XCTAssertEqual(UnifiedInfoFormatters.compactRate(2_500_000_000), "2.5G")
        XCTAssertEqual(UnifiedInfoFormatters.compactRate(18_000_000_000), "18G")
    }
    
    // MARK: - battery power and time
    
    func testBatteryPowerText() {
        // on battery: battery-side flow, signed by the mode
        XCTAssertEqual(UnifiedInfoFormatters.batteryPowerText(batteryPower: -12.4, adapterPower: 0, onBattery: true, isCharging: false), "-12.4 W (battery)")
        // unsigned reader values get their sign from the mode
        XCTAssertEqual(UnifiedInfoFormatters.batteryPowerText(batteryPower: 12.4, adapterPower: 0, onBattery: true, isCharging: false), "-12.4 W (battery)")
        // on AC: adapter draw, not the ~0 battery flow
        XCTAssertEqual(UnifiedInfoFormatters.batteryPowerText(batteryPower: 0.5, adapterPower: 41.2, onBattery: false, isCharging: true), "41.2 W (charging)")
        XCTAssertEqual(UnifiedInfoFormatters.batteryPowerText(batteryPower: 0.04, adapterPower: 23.0, onBattery: false, isCharging: false), "23.0 W (adapter)")
        // adapter sensor unavailable: fall back to the battery flow
        XCTAssertEqual(UnifiedInfoFormatters.batteryPowerText(batteryPower: 0.04, adapterPower: 0, onBattery: false, isCharging: false), "0.0 W (adapter)")
    }
    
    func testMenuWatts() {
        XCTAssertEqual(UnifiedInfoFormatters.menuWatts(128.46), "128W")
        XCTAssertEqual(UnifiedInfoFormatters.menuWatts(9.54), "9.5W")
        XCTAssertEqual(UnifiedInfoFormatters.menuWatts(0.04), "0.0W")
        XCTAssertEqual(UnifiedInfoFormatters.menuWatts(-57.14), "-57W")
        XCTAssertEqual(UnifiedInfoFormatters.menuWatts(-9.54), "-9.5W")
    }

    func testBatteryRowValue() {
        XCTAssertEqual(UnifiedInfoFormatters.batteryRowValue(level: 83, minutes: 214), "83% · 3:34")
        XCTAssertEqual(UnifiedInfoFormatters.batteryRowValue(level: 100, minutes: 0), "100%")
        XCTAssertEqual(UnifiedInfoFormatters.batteryRowValue(level: 8, minutes: 9), "8% · 0:09")
    }
    
    // MARK: - all-sensors popover filter
    
    private func sensor(_ key: String, _ name: String, _ value: Double) -> Sensor {
        var s = Sensor(key: key, name: name, group: .unknown, type: .temperature, platforms: [])
        s.value = value
        return s
    }
    
    func testSensorsAllFilter() {
        let list: [String: Sensor_p] = [
            "Ta01": self.sensor("Ta01", "Palm rest", 33),
            "TCMb": self.sensor("TCMb", "Memory bank", 71),
            "TVD0": self.sensor("TVD0", "GPU die", 69)
        ]
        // empty query: everything, hot-first
        XCTAssertEqual(SensorsAllPopover.filteredKeys(list, query: ""), ["TCMb", "TVD0", "Ta01"])
        // case-insensitive name match
        XCTAssertEqual(SensorsAllPopover.filteredKeys(list, query: "palm"), ["Ta01"])
        // key match
        XCTAssertEqual(SensorsAllPopover.filteredKeys(list, query: "tvd"), ["TVD0"])
        // no match
        XCTAssertEqual(SensorsAllPopover.filteredKeys(list, query: "ssd"), [])
    }
    
    func testBatteryTimeText() {
        XCTAssertEqual(UnifiedInfoFormatters.batteryTimeText(onBattery: true, isCharging: false, minutesToEmpty: 135, minutesToFull: 0, optimizedCharging: false), "2:15")
        XCTAssertEqual(UnifiedInfoFormatters.batteryTimeText(onBattery: true, isCharging: false, minutesToEmpty: 0, minutesToFull: 0, optimizedCharging: false), "–")
        XCTAssertEqual(UnifiedInfoFormatters.batteryTimeText(onBattery: false, isCharging: true, minutesToEmpty: 0, minutesToFull: 48, optimizedCharging: false), "Time to full — 0:48")
        XCTAssertEqual(UnifiedInfoFormatters.batteryTimeText(onBattery: false, isCharging: true, minutesToEmpty: 0, minutesToFull: 48, optimizedCharging: true), "Charging (limit 80%)")
        XCTAssertEqual(UnifiedInfoFormatters.batteryTimeText(onBattery: false, isCharging: false, minutesToEmpty: 0, minutesToFull: 0, optimizedCharging: false), "–")
    }
    
    func testClock() {
        XCTAssertEqual(UnifiedInfoFormatters.clock(0), "0:00")
        XCTAssertEqual(UnifiedInfoFormatters.clock(9), "0:09")
        XCTAssertEqual(UnifiedInfoFormatters.clock(135), "2:15")
        XCTAssertEqual(UnifiedInfoFormatters.clock(1440), "24:00")
    }

    // MARK: - menu power readout

    private struct FakePowerProbe: MenuPowerProbing {
        var values: [String: Double]
        var battery = false
        var charging = false
        func smc(_ key: String) -> Double? { self.values[key] }
        func onBattery() -> Bool { self.battery }
        func chargingOnAC() -> Bool { self.charging }
    }

    /// The state × key-availability matrix the stuck-readout regressions
    /// rode through: each cell pins the source table in Stats/UnifiedPopup.swift.
    func testMenuPowerReadoutMatrix() {
        // on battery: PPBR drain, as a magnitude
        var probe = FakePowerProbe(values: ["PPBR": -42.5, "PDTR": 84.4], battery: true)
        XCTAssertEqual(MenuPowerReadout(probe: probe).watts(), 42.5)
        // on battery, PPBR missing: no readout at all
        probe = FakePowerProbe(values: ["PDTR": 84.4], battery: true)
        XCTAssertNil(MenuPowerReadout(probe: probe).watts())
        // AC, not charging: PDTR is the total system draw
        probe = FakePowerProbe(values: ["PPBR": 1.5, "PDTR": 30.2])
        XCTAssertEqual(MenuPowerReadout(probe: probe).watts(), 30.2)
        // AC, not charging, PDTR absent: PPBR fallback (magnitude)
        probe = FakePowerProbe(values: ["PPBR": 1.5])
        XCTAssertEqual(MenuPowerReadout(probe: probe).watts(), 1.5)
        // AC, not charging, PDTR zero (not > 0): same fallback
        probe = FakePowerProbe(values: ["PPBR": 1.5, "PDTR": 0])
        XCTAssertEqual(MenuPowerReadout(probe: probe).watts(), 1.5)
        // AC, charging: si10 (live SoC power) wins over the pinned PDTR
        probe = FakePowerProbe(values: ["PPBR": 0.9, "PDTR": 84.4, "si10": 27.3], charging: true)
        XCTAssertEqual(MenuPowerReadout(probe: probe).watts(), 27.3)
        // AC, charging, si10 missing: PDTR fallback
        probe = FakePowerProbe(values: ["PPBR": 0.9, "PDTR": 84.4], charging: true)
        XCTAssertEqual(MenuPowerReadout(probe: probe).watts(), 84.4)
        // AC, charging, si10 non-positive: PDTR fallback
        probe = FakePowerProbe(values: ["PPBR": 0.9, "PDTR": 84.4, "si10": 0], charging: true)
        XCTAssertEqual(MenuPowerReadout(probe: probe).watts(), 84.4)
    }

    // MARK: - menu readout composer

    private func readoutInput(
        watts: Double? = 49.4,
        level: Double? = 0.67,
        minutes: Int? = 152,
        onBattery: Bool = true
    ) -> MenuReadoutComposer.Input {
        MenuReadoutComposer.Input(
            watts: watts,
            batteryLevel: level,
            timeToEmptyMinutes: minutes,
            isBatteryPowered: onBattery
        )
    }

    /// The preset × input-availability matrix for the selectable menu-bar
    /// readout: which segments each preset composes, and which drop out
    /// when an input is missing.
    func testMenuReadoutComposerMatrix() {
        let full = self.readoutInput()
        // every preset at full inputs
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .off, input: full), [])
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .watts, input: full), ["49W"])
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .battery, input: full), ["67%"])
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .wattsBattery, input: full), ["49W", "67%"])
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .batteryTime, input: full), ["67%", "2:32"])
        // joined title uses the " · " separator
        XCTAssertEqual(MenuReadoutComposer.title(preset: .wattsBattery, input: full), "49W · 67%")
        XCTAssertEqual(MenuReadoutComposer.title(preset: .batteryTime, input: full), "67% · 2:32")

        // watts missing: watts-only preset yields nothing; mixed preset
        // keeps its battery segment
        let noWatts = self.readoutInput(watts: nil)
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .watts, input: noWatts), [])
        XCTAssertEqual(MenuReadoutComposer.title(preset: .watts, input: noWatts), "")
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .wattsBattery, input: noWatts), ["67%"])

        // level missing: percent segment drops everywhere, including the
        // whole battery_time preset (percent is its anchor)
        let noLevel = self.readoutInput(level: nil)
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .battery, input: noLevel), [])
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .wattsBattery, input: noLevel), ["49W"])
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .batteryTime, input: noLevel), [])

        // battery_time on AC: percent only, even with an estimate present
        let onAC = self.readoutInput(onBattery: false)
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .batteryTime, input: onAC), ["67%"])
        // on battery, the time segment needs minutes > 0
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .batteryTime, input: self.readoutInput(minutes: 0)), ["67%"])
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .batteryTime, input: self.readoutInput(minutes: nil)), ["67%"])
        // time formatting is h:mm
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .batteryTime, input: self.readoutInput(minutes: 9)), ["67%", "0:09"])
        // percent rounds, not truncates (0.67 * 100 is 66.999... as a Double)
        XCTAssertEqual(MenuReadoutComposer.segments(preset: .battery, input: self.readoutInput(level: 0.995)), ["100%"])
    }

    /// Read-through migration from the legacy watts boolean. The tests run
    /// inside the Stats test host, so the real Store domain is snapshotted
    /// and restored around the mutations.
    func testMenuReadoutSelectionMigration() {
        let key = MenuReadoutSelection.storeKey
        let legacyKey = MenuReadoutSelection.legacyPowerKey
        let hadNew = Store.shared.exist(key: key)
        let oldNew = Store.shared.string(key: key, defaultValue: "")
        let hadLegacy = Store.shared.exist(key: legacyKey)
        let oldLegacy = Store.shared.bool(key: legacyKey, defaultValue: false)
        defer {
            if hadNew { Store.shared.set(key: key, value: oldNew) } else { Store.shared.remove(key) }
            if hadLegacy { Store.shared.set(key: legacyKey, value: oldLegacy) } else { Store.shared.remove(legacyKey) }
        }

        // default: nothing set -> off
        Store.shared.remove(key)
        Store.shared.remove(legacyKey)
        XCTAssertEqual(MenuReadoutSelection.current(), .off)

        // legacy boolean on, new key absent -> watts
        Store.shared.set(key: legacyKey, value: true)
        XCTAssertEqual(MenuReadoutSelection.current(), .watts)

        // a valid new key wins over the legacy boolean
        Store.shared.set(key: key, value: "battery")
        XCTAssertEqual(MenuReadoutSelection.current(), .battery)

        // every stored preset name parses
        Store.shared.set(key: key, value: "off")
        XCTAssertEqual(MenuReadoutSelection.current(), .off)
        Store.shared.set(key: key, value: "watts")
        XCTAssertEqual(MenuReadoutSelection.current(), .watts)
        Store.shared.set(key: key, value: "watts_battery")
        XCTAssertEqual(MenuReadoutSelection.current(), .wattsBattery)
        Store.shared.set(key: key, value: "battery_time")
        XCTAssertEqual(MenuReadoutSelection.current(), .batteryTime)

        // unknown value falls through to the legacy boolean, then off
        Store.shared.set(key: key, value: "bogus")
        XCTAssertEqual(MenuReadoutSelection.current(), .watts)
        Store.shared.remove(legacyKey)
        XCTAssertEqual(MenuReadoutSelection.current(), .off)
    }

    // MARK: - menu readout element set

    /// Read-through migration chain for the DIS-1 element set: a
    /// non-empty elements key wins (unknown members skipped, which can
    /// yield an empty set); an empty stored value falls through to the
    /// MEN-1 preset mapping; below that the legacy watts boolean;
    /// default is the empty set.
    func testMenuReadoutElementsMigration() {
        let key = MenuReadoutElements.storeKey
        let presetKey = MenuReadoutSelection.storeKey
        let legacyKey = MenuReadoutSelection.legacyPowerKey
        let hadElements = Store.shared.exist(key: key)
        let oldElements = Store.shared.string(key: key, defaultValue: "")
        let hadPreset = Store.shared.exist(key: presetKey)
        let oldPreset = Store.shared.string(key: presetKey, defaultValue: "")
        let hadLegacy = Store.shared.exist(key: legacyKey)
        let oldLegacy = Store.shared.bool(key: legacyKey, defaultValue: false)
        defer {
            if hadElements { Store.shared.set(key: key, value: oldElements) } else { Store.shared.remove(key) }
            if hadPreset { Store.shared.set(key: presetKey, value: oldPreset) } else { Store.shared.remove(presetKey) }
            if hadLegacy { Store.shared.set(key: legacyKey, value: oldLegacy) } else { Store.shared.remove(legacyKey) }
        }

        // default: nothing set -> empty set
        Store.shared.remove(key)
        Store.shared.remove(presetKey)
        Store.shared.remove(legacyKey)
        XCTAssertEqual(MenuReadoutElements.current(), [])

        // legacy boolean on, nothing else -> watts
        Store.shared.set(key: legacyKey, value: true)
        XCTAssertEqual(MenuReadoutElements.current(), [.watts])

        // every preset maps to its element subset
        Store.shared.set(key: presetKey, value: "off")
        XCTAssertEqual(MenuReadoutElements.current(), [])
        Store.shared.set(key: presetKey, value: "watts")
        XCTAssertEqual(MenuReadoutElements.current(), [.watts])
        Store.shared.set(key: presetKey, value: "battery")
        XCTAssertEqual(MenuReadoutElements.current(), [.battery])
        Store.shared.set(key: presetKey, value: "watts_battery")
        XCTAssertEqual(MenuReadoutElements.current(), [.watts, .battery])
        Store.shared.set(key: presetKey, value: "battery_time")
        XCTAssertEqual(MenuReadoutElements.current(), [.battery, .time])

        // a non-empty elements key wins over the preset key and legacy bool
        Store.shared.set(key: key, value: "battery,time")
        XCTAssertEqual(MenuReadoutElements.current(), [.battery, .time])

        // unknown members are skipped, not fatal
        Store.shared.set(key: key, value: "watts,bogus,battery")
        XCTAssertEqual(MenuReadoutElements.current(), [.watts, .battery])

        // an all-unknown non-empty value is an empty set — it does NOT
        // fall through to the preset key
        Store.shared.set(key: key, value: "bogus")
        XCTAssertEqual(MenuReadoutElements.current(), [])

        // an empty stored value falls through, NOT an empty set
        Store.shared.set(key: key, value: "")
        Store.shared.set(key: presetKey, value: "battery")
        XCTAssertEqual(MenuReadoutElements.current(), [.battery])
    }

    /// The structural cap lives at the write boundary: more than two
    /// elements are truncated, duplicates collapse without consuming a
    /// slot, and the stored form is the comma-separated raw values.
    func testMenuReadoutElementsCap() {
        let key = MenuReadoutElements.storeKey
        let hadElements = Store.shared.exist(key: key)
        let oldElements = Store.shared.string(key: key, defaultValue: "")
        defer {
            if hadElements { Store.shared.set(key: key, value: oldElements) } else { Store.shared.remove(key) }
        }

        MenuReadoutElements.save([.watts, .battery, .time])
        XCTAssertEqual(Store.shared.string(key: key, defaultValue: ""), "watts,battery")
        XCTAssertEqual(MenuReadoutElements.current(), [.watts, .battery])

        // duplicates collapse without consuming a slot
        MenuReadoutElements.save([.battery, .battery, .time])
        XCTAssertEqual(Store.shared.string(key: key, defaultValue: ""), "battery,time")
        XCTAssertEqual(MenuReadoutElements.current(), [.battery, .time])

        // a single element round-trips
        MenuReadoutElements.save([.time])
        XCTAssertEqual(Store.shared.string(key: key, defaultValue: ""), "time")
        XCTAssertEqual(MenuReadoutElements.current(), [.time])

        // the empty set persists as "" — which reads back as fall-through
        MenuReadoutElements.save([])
        XCTAssertEqual(Store.shared.string(key: key, defaultValue: "unset"), "")
    }

    /// Layout only changes the separator: " · " horizontal, newline
    /// stacked. AC-collapse and nil-omission hold per segment in both
    /// layouts, and single-element sets render identically.
    func testMenuReadoutComposerLayout() {
        let full = self.readoutInput()

        let wattsBattery = MenuReadoutComposer.segments(elements: [.watts, .battery], input: full)
        XCTAssertEqual(MenuReadoutComposer.title(segments: wattsBattery, layout: .horizontal), "49W · 67%")
        XCTAssertEqual(MenuReadoutComposer.title(segments: wattsBattery, layout: .stacked), "49W\n67%")

        let batteryTime = MenuReadoutComposer.segments(elements: [.battery, .time], input: full)
        XCTAssertEqual(MenuReadoutComposer.title(segments: batteryTime, layout: .horizontal), "67% · 2:32")
        XCTAssertEqual(MenuReadoutComposer.title(segments: batteryTime, layout: .stacked), "67%\n2:32")

        // single-element sets render identically in both layouts
        let wattsOnly = MenuReadoutComposer.segments(elements: [.watts], input: full)
        XCTAssertEqual(MenuReadoutComposer.title(segments: wattsOnly, layout: .horizontal), "49W")
        XCTAssertEqual(MenuReadoutComposer.title(segments: wattsOnly, layout: .stacked), "49W")

        // AC-collapse: the time segment drops on AC in both layouts
        let onAC = MenuReadoutComposer.segments(elements: [.battery, .time], input: self.readoutInput(onBattery: false))
        XCTAssertEqual(MenuReadoutComposer.title(segments: onAC, layout: .horizontal), "67%")
        XCTAssertEqual(MenuReadoutComposer.title(segments: onAC, layout: .stacked), "67%")

        // nil-omission per segment: missing watts drops only its segment
        let noWatts = MenuReadoutComposer.segments(elements: [.watts, .battery], input: self.readoutInput(watts: nil))
        XCTAssertEqual(MenuReadoutComposer.title(segments: noWatts, layout: .horizontal), "67%")
        XCTAssertEqual(MenuReadoutComposer.title(segments: noWatts, layout: .stacked), "67%")

        // the elements+layout convenience wrapper agrees
        XCTAssertEqual(
            MenuReadoutComposer.title(elements: [.watts, .battery], input: full, layout: .stacked),
            "49W\n67%"
        )
    }
}
