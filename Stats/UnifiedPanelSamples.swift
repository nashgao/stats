//
//  UnifiedPanelSamples.swift
//  Stats
//
//  Sample routing for the unified panel content, split out of
//  UnifiedPanelContent.swift: the .unifiedPanelSample observer, the
//  per-module sample switch, and the hero detail field updaters.
//  Extracted verbatim — no logic changes.
//

import Cocoa
import Kit
import CPU
import GPU
import RAM
import Disk
import Net
import Sensors
import Battery

extension UnifiedPanelContent {
    // MARK: - samples
    
    @objc func sample(_ notification: Notification) {
        guard let value = notification.object else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            UnifiedPerf.measure("handle") {
                self.handle(value, userInfo: notification.userInfo)
            }
        }
    }
    
    func handle(_ value: Any, userInfo: [AnyHashable: Any]?) {
        switch value {
        case let load as CPU_Load:
            self.cpuLoad = load
            self.cpuHero.setValue(Int((load.totalUsage * 100).rounded()))
            self.cpuHero.spark.add(load.totalUsage * 100)
            let partition = self.coreIndices()
            let perCore = load.usagePerCore
            self.cpuCoresRowE?.update(partition.efficiency.map({ $0 < perCore.count ? perCore[$0] : 0 }), avg: load.usageECores)
            self.cpuCoresRowP?.update(partition.performance.map({ $0 < perCore.count ? perCore[$0] : 0 }), avg: load.usagePCores)
            let loadStr = self.cpuAvg.map { "\($0.load1.rounded(toPlaces: 1)) / \($0.load5.rounded(toPlaces: 1)) / \($0.load15.rounded(toPlaces: 1))" } ?? "–"
            let freqStr = self.cpuFreqValue.map { "\(($0/1000).rounded(toPlaces: 2)) GHz" } ?? "–"
            let tempStr = self.cpuTempValue.map { "\(Int($0))°C" } ?? "–"
            self.cpuHero.setPills([freqStr, tempStr, "load \(loadStr)"])
            self.updateMini("cpu.system", value: "\(Int((load.systemLoad * 100).rounded()))%", fraction: load.systemLoad)
            self.updateMini("cpu.user", value: "\(Int((load.userLoad * 100).rounded()))%", fraction: load.userLoad)
            self.updateMini("cpu.idle", value: "\(Int((load.idleLoad * 100).rounded()))%", fraction: load.idleLoad)
        case let freq as CPU_Frequency:
            self.cpuFreqValue = freq.value
        case let temp as Double:
            self.cpuTempValue = temp
        case let avg as CPU_AverageLoad:
            self.cpuAvg = avg
        case let procs as [TopProcess]:
            let module = userInfo?["module"] as? String ?? "CPU"
            if module == "RAM" {
                self.ramTop = procs
                let maxUsage = procs.map({ $0.usage }).max() ?? 0
                let rows = Array(procs.prefix(2)).map { proc in
                    (name: proc.name, share: maxUsage > 0 ? proc.usage / maxUsage : 0, value: Units(bytes: Int64(proc.usage)).getReadableMemory(style: .memory))
                }
                self.replaceTops("ram.tops", title: localizedString("Top processes"), rows: rows)
            } else {
                self.cpuTop = procs
                let maxUsage = procs.map({ $0.usage }).max() ?? 0
                let rows = Array(procs.prefix(4)).map { proc in
                    (name: proc.name, share: maxUsage > 0 ? proc.usage / maxUsage : 0, value: "\(Int(proc.usage.rounded()))%")
                }
                self.replaceTops("cpu.tops", title: localizedString("Top processes"), rows: rows)
            }
        case let gpu as GPU_Info:
            self.gpuInfo = gpu
            let usage = gpu.utilization ?? 0
            self.gpuHero.setValue(Int((usage * 100).rounded()))
            self.gpuHero.spark.add(usage * 100)
            let fps = gpu.fps.map { "\(Int($0)) FPS" } ?? "–"
            let render = gpu.renderUtilization.map { "\(Int(($0 * 100).rounded()))" } ?? "–"
            let tiler = gpu.tilerUtilization.map { "\(Int(($0 * 100).rounded()))" } ?? "–"
            self.gpuHero.setPills([fps, "render \(render)", "tiler \(tiler)"])
            self.updateMini("gpu.render", value: gpu.renderUtilization.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", fraction: gpu.renderUtilization ?? 0)
            self.updateMini("gpu.tiler", value: gpu.tilerUtilization.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", fraction: gpu.tilerUtilization ?? 0)
            self.updateMini("gpu.fps", value: gpu.fps.map { "\(Int($0))" } ?? "–", fraction: min((gpu.fps ?? 0) / 120, 1))
        case let ram as RAM_Usage:
            self.ramUsage = ram
            self.ramHero.setValue(Int((ram.usage * 100).rounded()))
            self.ramHero.spark.add(ram.usage * 100)
            self.ramWiredField?.stringValue = Units(bytes: Int64(ram.wired)).getReadableMemory(style: .memory)
            self.ramAppField?.stringValue = Units(bytes: Int64(ram.app)).getReadableMemory(style: .memory)
            self.ramCompressedField?.stringValue = Units(bytes: Int64(ram.compressed)).getReadableMemory(style: .memory)
            let used = Units(bytes: Int64(ram.used)).getReadableMemory(style: .memory)
            let total = Units(bytes: Int64(ram.total)).getReadableMemory(style: .memory)
            let swap = Units(bytes: Int64(ram.swap.used)).getReadableMemory(style: .memory)
            self.ramHero.setPills(["\(used) of \(total)", ram.pressure.value.rawValue, "swap \(swap)"])
            self.ramHero.setBullet(ram.usage)
            let totalBytes = ram.total == 0 ? 1 : ram.total
            self.updateMini("ram.app", value: Units(bytes: Int64(ram.app)).getReadableMemory(style: .memory), fraction: ram.app / totalBytes)
            self.updateMini("ram.wired", value: Units(bytes: Int64(ram.wired)).getReadableMemory(style: .memory), fraction: ram.wired / totalBytes)
            self.updateMini("ram.compressed", value: Units(bytes: Int64(ram.compressed)).getReadableMemory(style: .memory), fraction: ram.compressed / totalBytes)
        case let disks as Disks:
            let drive = disks.array.first(where: { $0.root }) ?? disks.array.first
            guard let drive else { return }
            let total = Double(drive.activity.read + drive.activity.write)
            self.diskRow.valueField.stringValue = Units(bytes: Int64(total)).getReadableSpeed()
            self.diskRow.spark.add(total / 1024)
            self.diskReadField?.stringValue = Units(bytes: drive.activity.read).getReadableSpeed()
            self.diskWriteField?.stringValue = Units(bytes: drive.activity.write).getReadableSpeed()
            let volumes = disks.array.sorted { ($0.root ? 1 : 0) > ($1.root ? 1 : 0) }
            // live prefix first — it un-hides every row; the per-slot
            // hiding for empty volume slots runs after, so they stay gone
            self.diskDetail.setLiveRows(5)
            for (index, field) in self.diskVolumeFields.enumerated() {
                guard index < volumes.count else {
                    self.diskDetail.setRowHidden(2 + index, hidden: true)
                    continue
                }
                self.diskDetail.setRowHidden(2 + index, hidden: false)
                let volume = volumes[index]
                let used = volume.size - volume.free
                let title = volume.mediaName.isEmpty ? volume.BSDName : volume.mediaName
                self.diskDetail.setName(2 + index, title)
                field.stringValue = "\(Units(bytes: used).getReadableMemory(style: .memory)) of \(Units(bytes: volume.size).getReadableMemory(style: .memory))"
                field.toolTip = title
            }
            // Since-boot SMART totals are deliberately not shown here:
            // the NVMe data-unit counters read ~1000x too high on this
            // class of controller (hundreds of "TB" per day), and an
            // unverifiable number is worse than none. The classic popup
            // still shows them for anyone who wants the raw figures.
        case let net as Network_Usage:
            let down = UnifiedInfoFormatters.compactRate(net.bandwidth.download)
            let up = UnifiedInfoFormatters.compactRate(net.bandwidth.upload)
            self.netRow.valueField.stringValue = "\(down)↓ \(up)↑"
            self.netRow.spark.add(Double(net.bandwidth.download + net.bandwidth.upload) / 1024)
            self.netDownField?.stringValue = Units(bytes: net.bandwidth.download).getReadableSpeed()
            self.netUpField?.stringValue = Units(bytes: net.bandwidth.upload).getReadableSpeed()
            self.netTotalInField?.stringValue = Units(bytes: net.total.download).getReadableMemory(style: .memory)
            self.netTotalOutField?.stringValue = Units(bytes: net.total.upload).getReadableMemory(style: .memory)
            self.netInterfaceField?.stringValue = net.interface?.displayName ?? "–"
            if let address = net.interface?.address, !address.isEmpty {
                self.netAddressField?.stringValue = address
            } else {
                self.netAddressField?.stringValue = "–"
            }
        case let sensors as Sensors_List:
            self.sensorsList = sensors
            let temps = sensors.sensors.filter({ $0.type == .temperature && $0.popupState && $0.value.isFinite })
            if let hottest = temps.max(by: { $0.value < $1.value }) {
                self.sensorsRow.valueField.stringValue = hottest.formattedValue
                self.sensorsRow.spark.add(hottest.value)
            }
            self.rebuildFans()
        case let battery as Battery_Usage:
            let minutes = battery.isBatteryPowered ? battery.timeToEmpty : (battery.isCharging ? battery.timeToCharge : 0)
            self.batteryRow.valueField.stringValue = UnifiedInfoFormatters.batteryRowValue(
                level: Int((abs(battery.level) * 100).rounded()),
                minutes: minutes
            )
            self.batteryRow.spark.add(abs(battery.level) * 100)
            self.batteryCyclesField?.stringValue = "\(battery.cycles)"
            self.batteryHealthField?.stringValue = "\(UnifiedInfoFormatters.batteryPercent(battery.maxCapacity, of: battery.designedCapacity))% of design"
            self.batteryFullChargeField?.stringValue = "\(battery.fullChargeCapacity.formatted(.number.grouping(.automatic))) mAh · \(UnifiedInfoFormatters.batteryPercent(battery.fullChargeCapacity, of: battery.designedCapacity))% of design"
            self.batteryConditionField?.stringValue = localizedString(UnifiedInfoFormatters.batteryCondition(battery.health))
            self.batteryPowerField?.stringValue = UnifiedInfoFormatters.batteryPowerText(
                batteryPower: battery.batteryPower,
                adapterPower: battery.adapterPower,
                onBattery: battery.isBatteryPowered,
                isCharging: battery.isCharging
            )
            self.batteryTimeField?.stringValue = UnifiedInfoFormatters.batteryTimeText(
                onBattery: battery.isBatteryPowered,
                isCharging: battery.isCharging,
                minutesToEmpty: battery.timeToEmpty,
                minutesToFull: battery.timeToCharge,
                optimizedCharging: battery.optimizedChargingEngaged
            )
        default:
            break
        }
    }
    
    func updateMini(_ identifier: String, value: String, fraction: Double) {
        for hero in [self.cpuHero, self.gpuHero, self.ramHero] {
            if let metric = hero.expandContainer.findView(withIdentifier: identifier) as? UnifiedMiniMetric {
                metric.set(value: value, fraction: fraction)
            }
        }
    }
    
    func replaceTops(_ identifier: String, title: String, rows: [(name: String, share: Double, value: String)]) {
        for hero in [self.cpuHero, self.gpuHero, self.ramHero] {
            if let tops = hero.expandContainer.findView(withIdentifier: identifier) as? UnifiedTopProcesses {
                tops.update(rows: rows)
            }
        }
    }
}

extension NSView {
    func findView(withIdentifier identifier: String) -> NSView? {
        if self.identifier?.rawValue == identifier {
            return self
        }
        for subview in self.subviews {
            if let found = subview.findView(withIdentifier: identifier) {
                return found
            }
        }
        return nil
    }
}
