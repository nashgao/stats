//
//  Alerts.swift
//  Tests
//
//  AttentionAlerter edge-trigger and formatting tests. These pin the
//  watchdog contract: alert on entry, never while the state persists,
//  alert again only after a clear and re-cross.
//

import XCTest
@testable import Kit
@testable import Stats

final class AttentionAlerterTests: XCTestCase {
    private let all: Set<TelemetryMetric> = [.fan, .temperature, .memory, .gpu, .battery, .cpu]
    
    private func attention(_ kind: Attention.Kind, module: String, level: Attention.Level, label: String) -> Attention {
        Attention(kind: kind, module: module, level: level, label: label)
    }
    
    // MARK: - edge triggering
    
    func testAlertFiresOnEntry() {
        let current = [attention(.temperature, module: "Sensors", level: .attention, label: "TCMb 94.0°C")]
        let alerts = AttentionAlerter.notifications(previous: [], current: current, enabled: self.all)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].title, "Sensors — Attention")
    }
    
    func testNoRepeatWhileStatePersists() {
        let previous = [attention(.temperature, module: "Sensors", level: .attention, label: "TCMb 94.0°C")]
        let current = [attention(.temperature, module: "Sensors", level: .attention, label: "TCMb 95.1°C")]
        XCTAssertTrue(AttentionAlerter.notifications(previous: previous, current: current, enabled: self.all).isEmpty)
    }
    
    func testEscalationDoesNotRefire() {
        // attention -> critical for the same metric is already in the set;
        // the panel glyph surfaces the escalation.
        let previous = [attention(.memory, module: "RAM", level: .attention, label: "RAM 92%")]
        let current = [attention(.memory, module: "RAM", level: .critical, label: "RAM 98%")]
        XCTAssertTrue(AttentionAlerter.notifications(previous: previous, current: current, enabled: self.all).isEmpty)
    }
    
    func testAlertsAgainAfterClearAndRecross() {
        let hot = [attention(.temperature, module: "Sensors", level: .attention, label: "TCMb 94.0°C")]
        XCTAssertEqual(AttentionAlerter.notifications(previous: [], current: hot, enabled: self.all).count, 1)
        XCTAssertTrue(AttentionAlerter.notifications(previous: hot, current: [], enabled: self.all).isEmpty)
        XCTAssertEqual(AttentionAlerter.notifications(previous: [], current: hot, enabled: self.all).count, 1)
    }
    
    func testClearingOneMetricKeepsOthersSuppressed() {
        // fan stays in state (no refire) while temperature clears; a new
        // temperature crossing must fire alongside the suppressed fan.
        let previous = [
            attention(.fan, module: "Sensors", level: .attention, label: "Fan #0 4,120 RPM"),
            attention(.temperature, module: "Sensors", level: .critical, label: "TCMb 101.0°C")
        ]
        let fanOnly = [attention(.fan, module: "Sensors", level: .attention, label: "Fan #0 4,300 RPM")]
        XCTAssertTrue(AttentionAlerter.notifications(previous: previous, current: fanOnly, enabled: self.all).isEmpty)
        let bothAgain = fanOnly + [attention(.temperature, module: "Sensors", level: .critical, label: "TCMb 102.0°C")]
        let alerts = AttentionAlerter.notifications(previous: fanOnly, current: bothAgain, enabled: self.all)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].title, "Sensors — Critical")
    }
    
    // MARK: - enablement
    
    func testDisabledSetSuppressesAll() {
        let current = [attention(.cpu, module: "CPU", level: .attention, label: "CPU 95%")]
        XCTAssertTrue(AttentionAlerter.notifications(previous: [], current: current, enabled: []).isEmpty)
    }
    
    func testDisabledMetricFilteredIndividually() {
        let current = [
            attention(.memory, module: "RAM", level: .attention, label: "RAM 92%"),
            attention(.cpu, module: "CPU", level: .attention, label: "CPU 95%")
        ]
        let alerts = AttentionAlerter.notifications(previous: [], current: current, enabled: [.cpu])
        XCTAssertEqual(alerts.map({ $0.title }), ["CPU — Attention"])
    }
    
    // MARK: - content formatting
    
    func testBodyCarriesValueAndThreshold() {
        let alerts = AttentionAlerter.notifications(
            previous: [],
            current: [attention(.memory, module: "RAM", level: .attention, label: "RAM 92%")],
            enabled: self.all
        )
        XCTAssertEqual(alerts[0].body, "RAM 92% — above 90%")
    }
    
    func testThresholdsPerKindAndLevel() {
        let cases: [(Attention.Kind, Attention.Level, String)] = [
            (.fan, .attention, "80%"), (.fan, .critical, "95%"),
            (.temperature, .attention, "93°C"), (.temperature, .critical, "100°C"),
            (.memory, .critical, "97%"),
            (.gpu, .attention, "85%"), (.gpu, .critical, "97%"),
            (.cpu, .attention, "90%"), (.cpu, .critical, "98%"),
            (.battery, .attention, "20W")
        ]
        for (kind, level, expected) in cases {
            let a = attention(kind, module: "M", level: level, label: "L")
            XCTAssertEqual(AttentionAlerter.threshold(of: a), expected, "\(kind) \(level)")
            XCTAssertTrue(AttentionAlerter.alert(for: a).body.hasSuffix("above \(expected)"))
        }
    }
    
    func testTitleUsesModuleAndLevel() {
        let critical = attention(.fan, module: "Sensors", level: .critical, label: "Fan #0 5,300 RPM")
        XCTAssertEqual(AttentionAlerter.alert(for: critical).title, "Sensors — Critical")
        let battery = attention(.battery, module: "Battery", level: .attention, label: "Battery 31W")
        XCTAssertEqual(AttentionAlerter.alert(for: battery).title, "Battery — Attention")
    }
    
    func testOrderFollowsCurrentPriority() {
        let current = [
            attention(.fan, module: "Sensors", level: .attention, label: "F"),
            attention(.temperature, module: "Sensors", level: .attention, label: "T"),
            attention(.cpu, module: "CPU", level: .critical, label: "C")
        ]
        let alerts = AttentionAlerter.notifications(previous: [], current: current, enabled: self.all)
        XCTAssertEqual(alerts.map({ $0.title }), ["Sensors — Attention", "Sensors — Attention", "CPU — Critical"])
    }
}
