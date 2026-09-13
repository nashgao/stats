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
        static let temperatureAttentionCelsius: Double = 85
        static let temperatureCriticalCelsius: Double = 95
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
            let next = self.evaluate()
            if next != self._attentions {
                self._attentions = next
                NSLog(
                    "[Attention] %@",
                    next.isEmpty ? "quiet" : next.map({ "\($0.label) [\($0.level == .critical ? "critical" : "attention")]" }).joined(separator: " · ")
                )
            }
        }
    }
    
    private func evaluate() -> [Attention] {
        var result: [Attention] = []
        
        if let fan = self.samples[.fan] {
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
        
        if let temperature = self.samples[.temperature],
           temperature.value >= Threshold.temperatureAttentionCelsius {
            result.append(Attention(
                kind: .temperature,
                module: "Sensors",
                level: temperature.value >= Threshold.temperatureCriticalCelsius ? .critical : .attention,
                label: "\(temperature.displayValue) \(temperature.detail)"
            ))
        }
        
        if let memory = self.samples[.memory], memory.value >= Threshold.memoryAttention {
            result.append(Attention(
                kind: .memory,
                module: "RAM",
                level: memory.value >= Threshold.memoryCritical ? .critical : .attention,
                label: "RAM \(memory.displayValue)"
            ))
        }
        
        if let gpu = self.samples[.gpu], gpu.value >= Threshold.gpuAttention {
            result.append(Attention(
                kind: .gpu,
                module: "GPU",
                level: gpu.value >= Threshold.gpuCritical ? .critical : .attention,
                label: "GPU \(gpu.displayValue)"
            ))
        }
        
        if let battery = self.samples[.battery],
           (battery.secondaryValue ?? 1) == 0,
           abs(battery.power ?? 0) >= Threshold.batteryDrainWatts {
            result.append(Attention(
                kind: .battery,
                module: "Battery",
                level: .attention,
                label: String(format: "Battery %.0fW", abs(battery.power ?? 0))
            ))
        }
        
        if let cpu = self.samples[.cpu], cpu.value >= Threshold.cpuAttention {
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
