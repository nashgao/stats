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
    
    func testMenuBattery() {
        XCTAssertEqual(UnifiedInfoFormatters.menuBattery(level: 87, minutes: 135), "87% 2:15")
        XCTAssertEqual(UnifiedInfoFormatters.menuBattery(level: 100, minutes: 0), "100%")
        XCTAssertEqual(UnifiedInfoFormatters.menuBattery(level: 8, minutes: 9), "8% 0:09")
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
}
