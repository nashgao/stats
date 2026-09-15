//
//  AttentionAlerter.swift
//  Stats
//
//  Notification Center delivery for attention/critical transitions —
//  the watchdog that barks outside the panel. AttentionAlerter is the
//  pure decision (which alerts fire between two evaluator snapshots);
//  AttentionNotifier owns the side effects (setting, authorization,
//  UNUserNotificationCenter, QA logging). STATS_QA_ALERT=1 forces the
//  pipeline on in memory and logs the composed content for the smoke
//  test.
//

import Cocoa
import Kit
import UserNotifications

/// One user-facing alert. Equatable so tests can pin the exact output.
struct AlertContent: Equatable {
    let title: String
    let body: String
}

enum AttentionAlerter {
    /// Edge-triggered: an alert fires only when a (kind, module) pair
    /// ENTERS the attention set. While the pair stays in the set —
    /// including an escalation attention -> critical, which the panel
    /// glyph already surfaces — no new alert fires; it fires again
    /// only after the pair leaves the set and re-crosses.
    static func notifications(
        previous: [Attention],
        current: [Attention],
        enabled: Set<TelemetryMetric>
    ) -> [AlertContent] {
        let previousKeys = Set(previous.map({ Self.key(of: $0) }))
        return current
            .filter { !previousKeys.contains(Self.key(of: $0)) }
            .filter { enabled.contains(Self.metric(of: $0.kind)) }
            .map { Self.alert(for: $0) }
    }
    
    private static func key(of attention: Attention) -> String {
        "\(attention.kind.rawValue):\(attention.module)"
    }
    
    static func metric(of kind: Attention.Kind) -> TelemetryMetric {
        switch kind {
        case .fan: return .fan
        case .temperature: return .temperature
        case .memory: return .memory
        case .gpu: return .gpu
        case .battery: return .battery
        case .cpu: return .cpu
        }
    }
    
    static func alert(for attention: Attention) -> AlertContent {
        let level = attention.level == .critical ? "Critical" : "Attention"
        return AlertContent(
            title: "\(attention.module) — \(level)",
            body: "\(attention.label) — above \(Self.threshold(of: attention))"
        )
    }
    
    /// The threshold the metric crossed, formatted for the body. Kept
    /// next to the evaluator's Threshold constants so wording and values
    /// cannot drift apart.
    static func threshold(of attention: Attention) -> String {
        // Fraction thresholds (0...1) render as whole percentages; the
        // fan/temperature thresholds are already whole numbers.
        func percent(_ fraction: Double) -> String { "\(Int(fraction * 100))%" }
        switch attention.kind {
        case .fan:
            return attention.level == .critical ? "\(Int(AttentionEvaluator.Threshold.fanCriticalPercentage))%" : "\(Int(AttentionEvaluator.Threshold.fanPercentage))%"
        case .temperature:
            return attention.level == .critical ? "\(Int(AttentionEvaluator.Threshold.temperatureCriticalCelsius))°C" : "\(Int(AttentionEvaluator.Threshold.temperatureAttentionCelsius))°C"
        case .memory:
            return percent(attention.level == .critical ? AttentionEvaluator.Threshold.memoryCritical : AttentionEvaluator.Threshold.memoryAttention)
        case .gpu:
            return percent(attention.level == .critical ? AttentionEvaluator.Threshold.gpuCritical : AttentionEvaluator.Threshold.gpuAttention)
        case .battery:
            return "\(Int(AttentionEvaluator.Threshold.batteryDrainWatts))W"
        case .cpu:
            return percent(attention.level == .critical ? AttentionEvaluator.Threshold.cpuCritical : AttentionEvaluator.Threshold.cpuAttention)
        }
    }
}

/// Side-effect layer: setting gate, lazy UN authorization, delivery.
final class AttentionNotifier: NSObject {
    static let shared = AttentionNotifier()
    static let settingKey = "attention_alerts"
    
    /// QA knob: forces the pipeline on in memory (the smoke test runs
    /// against the shared defaults domain, which QA code must not write)
    /// and logs the composed notification content.
    static let qaEnabled = ProcessInfo.processInfo.environment["STATS_QA_ALERT"] == "1"
    
    private var authorizationRequested = false
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    /// The user-facing setting (default ON), forced on by the QA knob.
    static var alertsEnabled: Bool {
        self.qaEnabled || Store.shared.bool(key: self.settingKey, defaultValue: true)
    }
    
    /// Lazily request authorization the first time an alert actually
    /// fires while alerts are enabled — never on launch.
    static func requestAuthorizationIfNeeded() {
        guard self.alertsEnabled, !self.shared.authorizationRequested else { return }
        self.shared.authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func post(_ contents: [AlertContent]) {
        guard !contents.isEmpty else { return }
        NSLog("[Attention] notifier post ts=%.3f count=%d", Date().timeIntervalSince1970, contents.count)
        Self.requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        for content in contents {
            if Self.qaEnabled {
                NSLog("[QA] alert: %@ | %@", content.title, content.body)
            }
            let notification = UNMutableNotificationContent()
            notification.title = content.title
            notification.body = content.body
            notification.sound = .default
            let request = UNNotificationRequest(
                identifier: "attention.\(content.title)",
                content: notification,
                trigger: nil
            )
            center.add(request)
        }
    }
}

extension AttentionNotifier: UNUserNotificationCenterDelegate {
    /// Without this, macOS suppresses banners while Stats is the active
    /// app — exactly when the user is poking at the menu bar item.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
