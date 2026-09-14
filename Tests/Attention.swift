//
//  Attention.swift
//  Tests
//
//  AttentionEvaluator threshold, escalation, and priority tests.
//  These pin the user-visible attention rules; the hottest-sensor
//  thresholds (TCMb idles 88-94C on the target machine) are intentional.
//

import XCTest
@testable import Kit
@testable import Stats

final class AttentionEvaluatorTests: XCTestCase {
    private func sample(_ metric: TelemetryMetric, _ value: Double, secondary: Double? = nil, power: Double? = nil) -> TelemetrySample {
        TelemetrySample(metric: metric, value: value, secondaryValue: secondary, power: power, displayValue: "\(value)", detail: "")
    }
    
    private func evaluate(_ samples: [TelemetryMetric: TelemetrySample]) -> [Attention] {
        AttentionEvaluator.evaluate(samples)
    }
    
    // MARK: - temperature (hottest sensor; TCMb-class)
    
    func testTemperatureAttentionBoundary() {
        XCTAssertTrue(evaluate([.temperature: sample(.temperature, 92.9)]).isEmpty)
        let at = evaluate([.temperature: sample(.temperature, 93.0)])
        XCTAssertEqual(at.count, 1)
        XCTAssertEqual(at[0].level, .attention)
        XCTAssertEqual(at[0].module, "Sensors")
        XCTAssertEqual(at[0].kind, .temperature)
    }
    
    func testTemperatureCriticalBoundary() {
        let below = evaluate([.temperature: sample(.temperature, 99.9)])
        XCTAssertEqual(below.first?.level, .attention)
        let at = evaluate([.temperature: sample(.temperature, 100.0)])
        XCTAssertEqual(at.first?.level, .critical)
    }
    
    func testTemperatureDeescalatesWhenCooling() {
        var attentions = evaluate([.temperature: sample(.temperature, 101)])
        XCTAssertEqual(attentions.first?.level, .critical)
        attentions = evaluate([.temperature: sample(.temperature, 94)])
        XCTAssertEqual(attentions.first?.level, .attention)
        attentions = evaluate([.temperature: sample(.temperature, 80)])
        XCTAssertTrue(attentions.isEmpty)
    }
    
    // MARK: - fan
    
    func testFanPercentageBoundary() {
        XCTAssertTrue(evaluate([.fan: sample(.fan, 0.79)]).isEmpty)
        let at = evaluate([.fan: sample(.fan, 0.80)])
        XCTAssertEqual(at.first?.level, .attention)
        XCTAssertEqual(at.first?.module, "Sensors")
        XCTAssertEqual(at.first?.kind, .fan)
    }
    
    func testFanCriticalBoundary() {
        XCTAssertEqual(evaluate([.fan: sample(.fan, 0.9499)]).first?.level, .attention)
        XCTAssertEqual(evaluate([.fan: sample(.fan, 0.95)]).first?.level, .critical)
    }
    
    func testManualModeAlwaysAttends() {
        // any manual fan is attention-worthy regardless of percentage
        let attentions = evaluate([.fan: sample(.fan, 0.10, secondary: 1)])
        XCTAssertEqual(attentions.first?.level, .attention)
        XCTAssertTrue(attentions.first?.label.contains("(manual)") ?? false)
        // automatic at the same percentage stays quiet
        XCTAssertTrue(evaluate([.fan: sample(.fan, 0.10, secondary: 0)]).isEmpty)
    }
    
    // MARK: - memory / gpu / cpu utilization
    
    func testMemoryBoundaries() {
        XCTAssertTrue(evaluate([.memory: sample(.memory, 0.89)]).isEmpty)
        XCTAssertEqual(evaluate([.memory: sample(.memory, 0.90)]).first?.level, .attention)
        XCTAssertEqual(evaluate([.memory: sample(.memory, 0.97)]).first?.level, .critical)
        XCTAssertEqual(evaluate([.memory: sample(.memory, 1.0)]).first?.module, "RAM")
    }
    
    func testGPUBoundaries() {
        XCTAssertTrue(evaluate([.gpu: sample(.gpu, 0.84)]).isEmpty)
        XCTAssertEqual(evaluate([.gpu: sample(.gpu, 0.85)]).first?.level, .attention)
        XCTAssertEqual(evaluate([.gpu: sample(.gpu, 0.97)]).first?.level, .critical)
    }
    
    func testCPUBoundaries() {
        XCTAssertTrue(evaluate([.cpu: sample(.cpu, 0.89)]).isEmpty)
        XCTAssertEqual(evaluate([.cpu: sample(.cpu, 0.90)]).first?.level, .attention)
        XCTAssertEqual(evaluate([.cpu: sample(.cpu, 0.98)]).first?.level, .critical)
        XCTAssertEqual(evaluate([.cpu: sample(.cpu, 0.90)]).first?.module, "CPU")
    }
    
    // MARK: - battery
    
    func testBatteryRequiresDischargeAndDrain() {
        // on AC (secondary 1): never an attention, whatever the watts
        XCTAssertTrue(evaluate([.battery: sample(.battery, 1.0, secondary: 1, power: 60)]).isEmpty)
        // on battery, drain just under 20W stays quiet
        XCTAssertTrue(evaluate([.battery: sample(.battery, 0.5, secondary: 0, power: -19.9)]).isEmpty)
        // discharging at >= 20W attends
        let attentions = evaluate([.battery: sample(.battery, 0.5, secondary: 0, power: -20.0)])
        XCTAssertEqual(attentions.count, 1)
        XCTAssertEqual(attentions.first?.kind, .battery)
        XCTAssertEqual(attentions.first?.module, "Battery")
    }
    
    // MARK: - composition: priority + escalation
    
    func testPriorityOrderFanFirst() {
        let attentions = evaluate([
            .cpu: sample(.cpu, 1.0),
            .temperature: sample(.temperature, 95),
            .fan: sample(.fan, 0.85),
            .memory: sample(.memory, 0.95)
        ])
        XCTAssertEqual(attentions.map({ $0.kind }), [.fan, .temperature, .memory, .cpu])
    }
    
    func testMultipleAttentionsAllReported() {
        let attentions = evaluate([
            .gpu: sample(.gpu, 0.9),
            .battery: sample(.battery, 0.5, secondary: 0, power: -30)
        ])
        XCTAssertEqual(attentions.map({ $0.kind }), [.gpu, .battery])
    }
    
    func testLabelsCarryModuleAndValue() {
        let ram = evaluate([.memory: sample(.memory, 0.92)])
        XCTAssertEqual(ram.first?.label, "RAM 0.92")
        let cpu = evaluate([.cpu: sample(.cpu, 0.95)])
        XCTAssertEqual(cpu.first?.label, "CPU 0.95")
        let temp = evaluate([.temperature: sample(.temperature, 94)])
        XCTAssertTrue(temp.first?.label.contains("94.0") ?? false)
    }
    
    func testEmptySamplesAreQuiet() {
        XCTAssertTrue(evaluate([:]).isEmpty)
    }
}
