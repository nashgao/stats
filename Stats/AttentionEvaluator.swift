//
//  AttentionEvaluator.swift
//  Stats
//
//  Shared stress/attention engine for the adaptive menu bar glyph and the
//  unified popup attention routing. Consumes the existing TelemetrySample
//  notifications posted by the module readers; every threshold lives here
//  and only here.
//

import Cocoa
import Kit

struct Attention: Equatable {
    enum Kind: String {
        case fan, temperature, memory, gpu, battery, cpu
    }
    enum Level: Int {
        case attention = 1
        case critical
    }
    
    let kind: Kind
    let module: String
    let level: Level
    let label: String
}

final class AttentionEvaluator {
    static let shared = AttentionEvaluator()
    
    enum Threshold {
        static let fanPercentage: Double = 80
        static let fanCriticalPercentage: Double = 95
        static let temperatureAttentionCelsius: Double = 93
        static let temperatureCriticalCelsius: Double = 100
        static let memoryAttention: Double = 0.90
        static let memoryCritical: Double = 0.97
        static let gpuAttention: Double = 0.85
        static let gpuCritical: Double = 0.97
        static let cpuAttention: Double = 0.90
        static let cpuCritical: Double = 0.98
        static let batteryDrainWatts: Double = 20
    }
    
    private(set) var attentions: [Attention] {
        get { self.queue.sync { self._attentions } }
        set { self.queue.sync { self._attentions = newValue } }
    }
    private var _attentions: [Attention] = []
    private var samples: [TelemetryMetric: TelemetrySample] = [:]
    /// Per-metric hysteresis state: metrics currently IN attention, with
    /// the attention that put them there. Entering happens at the up
    /// thresholds (AttentionEvaluator.evaluate); leaving only happens
    /// below the up threshold minus a deadband, so a value hovering at a
    /// boundary (TCMb idles 88–94°C across the 93°C line) cannot flap
    /// the attention set — and the panel layout — every sample.
    private var levels: [TelemetryMetric: Attention] = [:]
    /// Reader threads post telemetry samples concurrently with the main
    /// thread; all state is serialized here.
    private let queue = DispatchQueue(label: "eu.exelban.Stats.AttentionEvaluator")
    
    /// First attention in priority order (fan, temperature, memory, gpu,
    /// battery, cpu); nil when the system is quiet.
    var primary: Attention? {
        self.queue.sync { self._attentions.first }
    }
    
    func attention(for module: String) -> Attention? {
        self.queue.sync { self._attentions.first(where: { $0.module == module }) }
    }
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.sample(_:)),
            name: .telemetrySample,
            object: nil
        )
    }
    
    @objc private func sample(_ notification: Notification) {
        guard let sample = notification.object as? TelemetrySample else { return }
        self.queue.async {
            self.samples[sample.metric] = sample
            let snapshot = Self.evaluate(self.samples)
            let next = Self.applyHysteresis(snapshot, samples: self.samples, levels: &self.levels)
            if next != self._attentions {
                let previous = self._attentions
                self._attentions = next
                NSLog(
                    "[Attention] %@ (ts=%.3f)",
                    next.isEmpty ? "quiet" : next.map({ "\($0.label) [\($0.level == .critical ? "critical" : "attention")]" }).joined(separator: " · "),
                    Date().timeIntervalSince1970
                )
                let enabled: Set<TelemetryMetric> = AttentionNotifier.alertsEnabled ? Set([.fan, .temperature, .memory, .gpu, .battery, .cpu]) : []
                AttentionNotifier.shared.post(AttentionAlerter.notifications(previous: previous, current: next, enabled: enabled))
            }
        }
    }

    /// The exit threshold for a metric at the given level: BELOW this
    /// value the level is released (strictly below, mirroring the
    /// enter-at-or-above up thresholds). Deadband is ~1.5 points
    /// (fractions for the percent metrics), 2.5°C for temperature —
    /// wide enough to absorb idle-boundary hovering, narrow enough to
    /// release promptly on a real recovery.
    static func exitThreshold(for kind: Attention.Kind, level: Attention.Level) -> Double {
        switch kind {
        case .fan:
            return level == .critical ? 0.935 : 0.785
        case .temperature:
            return level == .critical ? 97.5 : 90.5
        case .memory:
            return level == .critical ? 0.955 : 0.885
        case .gpu:
            return level == .critical ? 0.955 : 0.835
        case .battery:
            return 18.5
        case .cpu:
            return level == .critical ? 0.965 : 0.885
        }
    }

    /// Deadband filter over the per-sample snapshot evaluation.
    /// Escalation is immediate; de-escalation and clearing require the
    /// metric's current value to drop strictly below the exit threshold
    /// for its held level. `levels` is the held state (mutated).
    static func applyHysteresis(
        _ snapshot: [Attention],
        samples: [TelemetryMetric: TelemetrySample],
        levels: inout [TelemetryMetric: Attention]
    ) -> [Attention] {
        var emitted: [Attention] = []
        var handled: Set<TelemetryMetric> = []
        for candidate in snapshot {
            let metric = AttentionAlerter.metric(of: candidate.kind)
            handled.insert(metric)
            if let held = levels[metric] {
                if candidate.level.rawValue > held.level.rawValue {
                    // escalation: immediate
                    levels[metric] = candidate
                    emitted.append(candidate)
                } else if candidate.level == held.level {
                    // refresh the label, keep the level
                    levels[metric] = candidate
                    emitted.append(candidate)
                } else {
                    // de-escalation or clear: only below the exit threshold
                    let value = Self.hysteresisValue(of: metric, in: samples)
                    if let value, value < Self.exitThreshold(for: candidate.kind, level: held.level) {
                        if candidate.level == .attention {
                            // de-escalate: hold at attention, refresh label
                            let relaxed = Attention(kind: candidate.kind, module: candidate.module, level: .attention, label: candidate.label)
                            levels[metric] = relaxed
                            emitted.append(relaxed)
                        } else {
                            levels.removeValue(forKey: metric)
                        }
                    } else {
                        emitted.append(held)
                    }
                }
            } else {
                levels[metric] = candidate
                emitted.append(candidate)
            }
        }
        // Metrics held in attention that the snapshot no longer flags:
        // exit when their live value dropped below the exit threshold;
        // keep emitting when their reader went silent (missing sample).
        var toRemove: [TelemetryMetric] = []
        for (metric, held) in levels where !handled.contains(metric) {
            guard samples[metric] != nil else {
                emitted.append(held)
                continue
            }
            if let value = Self.hysteresisValue(of: metric, in: samples),
               value < Self.exitThreshold(for: held.kind, level: held.level) {
                toRemove.append(metric)
            } else {
                emitted.append(held)
            }
        }
        for metric in toRemove {
            levels.removeValue(forKey: metric)
        }
        return emitted
    }

    /// The value a metric's exit threshold compares against: battery
    /// drains compare on watts while discharging and 0 on AC (attention
    /// must clear when the machine is plugged in, whatever the watts);
    /// everything else compares on its sample value.
    private static func hysteresisValue(of metric: TelemetryMetric, in samples: [TelemetryMetric: TelemetrySample]) -> Double? {
        guard let sample = samples[metric] else { return nil }
        if metric == .battery {
            return (sample.secondaryValue ?? 1) == 0 ? abs(sample.power ?? 0) : 0
        }
        return sample.value
    }
    
    /// Pure threshold evaluation over the latest sample per metric; kept
    /// free of instance state so the rules are unit-testable. Priority
    /// order: fan, temperature, memory, gpu, battery, cpu.
    static func evaluate(_ samples: [TelemetryMetric: TelemetrySample]) -> [Attention] {
        var result: [Attention] = []
        
        if let fan = samples[.fan] {
            let percentage = fan.value * 100
            let manual = (fan.secondaryValue ?? 0) > 0
            if manual || percentage >= Threshold.fanPercentage {
                result.append(Attention(
                    kind: .fan,
                    module: "Sensors",
                    level: percentage >= Threshold.fanCriticalPercentage ? .critical : .attention,
                    label: "\(fan.detail) \(fan.displayValue)\(manual ? " (manual)" : "")"
                ))
            }
        }
        
        if let temperature = samples[.temperature],
           temperature.value >= Threshold.temperatureAttentionCelsius {
            result.append(Attention(
                kind: .temperature,
                module: "Sensors",
                level: temperature.value >= Threshold.temperatureCriticalCelsius ? .critical : .attention,
                label: "\(temperature.displayValue) \(temperature.detail)"
            ))
        }
        
        if let memory = samples[.memory], memory.value >= Threshold.memoryAttention {
            result.append(Attention(
                kind: .memory,
                module: "RAM",
                level: memory.value >= Threshold.memoryCritical ? .critical : .attention,
                label: "RAM \(memory.displayValue)"
            ))
        }
        
        if let gpu = samples[.gpu], gpu.value >= Threshold.gpuAttention {
            result.append(Attention(
                kind: .gpu,
                module: "GPU",
                level: gpu.value >= Threshold.gpuCritical ? .critical : .attention,
                label: "GPU \(gpu.displayValue)"
            ))
        }
        
        if let battery = samples[.battery],
           (battery.secondaryValue ?? 1) == 0,
           abs(battery.power ?? 0) >= Threshold.batteryDrainWatts {
            result.append(Attention(
                kind: .battery,
                module: "Battery",
                level: .attention,
                label: String(format: "Battery %.0fW", abs(battery.power ?? 0))
            ))
        }
        
        if let cpu = samples[.cpu], cpu.value >= Threshold.cpuAttention {
            result.append(Attention(
                kind: .cpu,
                module: "CPU",
                level: cpu.value >= Threshold.cpuCritical ? .critical : .attention,
                label: "CPU \(cpu.displayValue)"
            ))
        }
        
        return result
    }
}
