//
//  PanelInfo.swift
//  Tests
//
//  Pure formatter tests for the panel's info rows: battery condition
//  wording from the reader health percentage, and thermal pressure
//  state names + row status levels.
//

import XCTest
@testable import Kit
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
        XCTAssertEqual(UnifiedInfoFormatters.batteryPowerText(power: 36.74, onBattery: false, isCharging: true), "36.7 W (charging)")
        XCTAssertEqual(UnifiedInfoFormatters.batteryPowerText(power: -12.4, onBattery: true, isCharging: false), "-12.4 W (battery)")
        XCTAssertEqual(UnifiedInfoFormatters.batteryPowerText(power: 0.04, onBattery: false, isCharging: false), "0.0 W (adapter)")
        // unsigned reader values get their sign from the mode
        XCTAssertEqual(UnifiedInfoFormatters.batteryPowerText(power: 12.4, onBattery: true, isCharging: false), "-12.4 W (battery)")
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
