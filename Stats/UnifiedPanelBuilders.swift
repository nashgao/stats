//
//  UnifiedPanelBuilders.swift
//  Stats
//
//  Detail builders for the unified panel content, split out of
//  UnifiedPanelContent.swift: the CPU/GPU/RAM hero detail blocks, the
//  battery health rows, and the thermal/fan/temperature row machinery.
//  Extracted verbatim — no logic changes.
//

import Cocoa
import Kit
import Sensors

extension UnifiedPanelContent {
    // MARK: - detail builders
    
    func buildCPUDetail() -> NSView {
        let view = UnifiedFlippedView()
        let container = UnifiedFlippedView()
        container.frame = NSRect(x: 0, y: 0, width: 324, height: 178)
        let system = UnifiedMiniMetric(label: localizedString("System"), value: "–", fraction: 0)
        let user = UnifiedMiniMetric(label: localizedString("User"), value: "–", fraction: 0)
        let idle = UnifiedMiniMetric(label: localizedString("Idle"), value: "–", fraction: 0, color: .tertiaryLabelColor)
        container.addSubview(system)
        container.addSubview(user)
        container.addSubview(idle)
        system.frame = NSRect(x: 0, y: 0, width: 100, height: 32)
        user.frame = NSRect(x: 112, y: 0, width: 100, height: 32)
        idle.frame = NSRect(x: 224, y: 0, width: 100, height: 32)
        system.identifier = NSUserInterfaceItemIdentifier("cpu.system")
        user.identifier = NSUserInterfaceItemIdentifier("cpu.user")
        idle.identifier = NSUserInterfaceItemIdentifier("cpu.idle")
        view.addSubview(container)
        container.frame = NSRect(x: 0, y: 0, width: 324, height: 32)
        let tops = UnifiedTopProcesses(title: localizedString("Top processes"),
                                       rows: [("", 0, ""), ("", 0, ""), ("", 0, ""), ("", 0, "")])
        tops.identifier = NSUserInterfaceItemIdentifier("cpu.tops")
        view.addSubview(tops)
        tops.frame = NSRect(x: 0, y: 40, width: 324, height: 132)
        return view
    }
    
    func buildGPUDetail() -> NSView {
        let view = UnifiedFlippedView()
        let render = UnifiedMiniMetric(label: localizedString("Render"), value: "–", fraction: 0)
        let tiler = UnifiedMiniMetric(label: localizedString("Tiler"), value: "–", fraction: 0)
        let fps = UnifiedMiniMetric(label: localizedString("Frame rate"), value: "–", fraction: 0)
        render.identifier = NSUserInterfaceItemIdentifier("gpu.render")
        tiler.identifier = NSUserInterfaceItemIdentifier("gpu.tiler")
        fps.identifier = NSUserInterfaceItemIdentifier("gpu.fps")
        view.addSubview(render)
        view.addSubview(tiler)
        view.addSubview(fps)
        render.frame = NSRect(x: 0, y: 0, width: 100, height: 32)
        tiler.frame = NSRect(x: 112, y: 0, width: 100, height: 32)
        fps.frame = NSRect(x: 224, y: 0, width: 100, height: 32)
        view.frame = NSRect(x: 0, y: 0, width: 324, height: 32)
        return view
    }
    
    func buildRAMDetail() -> NSView {
        let view = UnifiedFlippedView()
        let app = UnifiedMiniMetric(label: localizedString("App"), value: "–", fraction: 0)
        let wired = UnifiedMiniMetric(label: localizedString("Wired"), value: "–", fraction: 0)
        let compressed = UnifiedMiniMetric(label: localizedString("Compressed"), value: "–", fraction: 0)
        app.identifier = NSUserInterfaceItemIdentifier("ram.app")
        wired.identifier = NSUserInterfaceItemIdentifier("ram.wired")
        compressed.identifier = NSUserInterfaceItemIdentifier("ram.compressed")
        view.addSubview(app)
        view.addSubview(wired)
        view.addSubview(compressed)
        app.frame = NSRect(x: 0, y: 0, width: 100, height: 32)
        wired.frame = NSRect(x: 112, y: 0, width: 100, height: 32)
        compressed.frame = NSRect(x: 224, y: 0, width: 100, height: 32)
        let tops = UnifiedTopProcesses(title: localizedString("Top processes"),
                                       rows: [("", 0, ""), ("", 0, "")])
        tops.identifier = NSUserInterfaceItemIdentifier("ram.tops")
        view.addSubview(tops)
        tops.frame = NSRect(x: 0, y: 40, width: 324, height: 60)
        view.frame = NSRect(x: 0, y: 0, width: 324, height: 100)
        return view
    }

    // MARK: - battery health detail
    
    func batteryDetailRow(_ label: String) -> NSTextField {
        let name = unifiedLabel(label, font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        let value = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .labelColor, alignment: .right)
        name.identifier = NSUserInterfaceItemIdentifier("battery.detail")
        value.identifier = NSUserInterfaceItemIdentifier("battery.detail")
        self.batteryDetailContainer.addSubview(name)
        self.batteryDetailContainer.addSubview(value)
        self.batteryDetailRows.append((name: name, value: value))
        return value
    }

    func layoutBatteryDetail() {
        let width = max(self.batteryRow.expandContainer.bounds.width, 100)
        var y: CGFloat = 0
        for row in self.batteryDetailRows {
            row.name.frame = NSRect(x: 0, y: y + 1, width: 180, height: 14)
            row.value.frame = NSRect(x: width - 160, y: y + 1, width: 160, height: 14)
            y += 18
        }
        self.batteryDetailContainer.frame = NSRect(x: 0, y: 0, width: width, height: max(ceil(y), 30))
        self.batteryRow.detailHeight = max(ceil(y), 30)
    }

    // MARK: - thermal pressure row
    
    @objc func thermalStateChanged(_ notification: Notification) {
        self.updateThermalRow()
    }
    
    /// Static E/P core-id partition (usagePerCore is indexed by core id),
    /// cached once per process. Super cores ride in the performance
    /// cluster, matching the classic popup's grouping.
    func coreIndices() -> (efficiency: [Int], performance: [Int]) {
        if let partition = self.corePartition {
            return partition
        }
        var efficiency: [Int] = []
        var performance: [Int] = []
        for core in SystemKit.shared.device.info.cpu?.cores ?? [] {
            if core.type == .efficiency {
                efficiency.append(Int(core.id))
            } else {
                performance.append(Int(core.id))
            }
        }
        let partition = (efficiency, performance)
        self.corePartition = partition
        return partition
    }
    
    func updateThermalRow() {
        let state = ProcessInfo.processInfo.thermalState
        let name = localizedString(UnifiedInfoFormatters.thermalStateName(state))
        if self.thermalRow.valueField.stringValue != name {
            self.thermalRow.valueField.stringValue = name
        }
        self.thermalRow.setStatus(level: UnifiedInfoFormatters.thermalStatusLevel(state))
        // Step series of the pressure level, normalized to the fixed
        // 0...100 chart range: nominal sits at the bottom, a state change
        // jumps the line by a third of the height. Fed per tick (this
        // runs from every relayout) and on state-change notifications.
        self.thermalRow.spark.add(Double(state.rawValue) * 100.0 / 3.0)
        // Tint the stroke with the row's semantic state color.
        let stroke: NSColor
        switch state {
        case .fair: stroke = UnifiedTokens.amberInk
        case .serious, .critical: stroke = UnifiedTokens.redInk
        default: stroke = UnifiedTokens.ok
        }
        if self.thermalRow.spark.strokeColor != stroke {
            self.thermalRow.spark.strokeColor = stroke
        }
        // Detail rows: state word + plain-language impact, tinted per
        // state, updated in place.
        self.thermalStateField?.stringValue = name
        let impact = localizedString(UnifiedInfoFormatters.thermalStateDescription(state))
        self.thermalImpactField?.stringValue = impact
        self.thermalImpactField?.textColor = stroke
    }
    
    func rebuildFans() {
        guard let sensors = self.sensorsList else { return }
        let fans = sensors.sensors.compactMap({ $0 as? Fan }).filter({ !$0.isComputed && $0.maxSpeed > 1 })
        let keys = fans.map({ $0.key }).sorted()
        if keys != self.fanKeys {
            self.fanKeys = keys
            for view in self.sensorsFansContainer.subviews {
                view.removeFromSuperview()
            }
            for fan in fans {
                // The module's own fan control: it sizes itself and reports
                // height changes through the callback.
                let fanView = FanView(fan, width: self.sensorsRow.expandContainer.bounds.width) { [weak self] in
                    self?.layoutFanContainer()
                    self?.relayout()
                    self?.onLayoutChange?()
                }
                self.sensorsFansContainer.addSubview(fanView)
            }
            // Measure synchronously so the expanded height is final in
            // the same pass — the previous async measure produced a
            // second layout (and a visible height jump) a beat later.
            self.sensorsFansContainer.layoutSubtreeIfNeeded()
            self.fanHeights = self.sensorsFansContainer.subviews
                .compactMap({ $0 as? FanView })
                .map({ max(ceil($0.frame.height), 64) })
        } else {
            // Same fan set: forward live values. The reader keeps sensor
            // order stable, so index pairing is exact — without this the
            // expanded card froze fan values at build time.
            let fanViews = self.sensorsFansContainer.subviews.compactMap({ $0 as? FanView })
            for (index, fanView) in fanViews.enumerated() where index < fans.count {
                fanView.update(fans[index])
            }
        }
        // Temperature rows (Option B): hot-first, top 5 in the panel; the
        // full list lives in the all-sensors popover ("All sensors (N)").
        // Membership changes require the newcomer to beat the held 5th
        // value by a deadband; values update in place.
        let temps = sensors.sensors
            .filter({ $0.type == .temperature && $0.popupState && $0.value.isFinite })
            .sorted(by: { $0.value > $1.value })
        self.totalTempCount = temps.count
        for temp in temps { self.latestTemps[temp.key] = temp }
        
        var desired = Array(temps.prefix(min(5, temps.count)).map({ $0.key }))
        if desired != self.tempKeys, !self.tempKeys.isEmpty {
            let threshold = self.latestTemps[self.tempKeys[min(4, self.tempKeys.count - 1)]]?.value ?? -.infinity
            let newcomers = desired.filter { !self.tempKeys.contains($0) }
            let accepted = newcomers.allSatisfy { key in
                (self.latestTemps[key]?.value ?? -.infinity) > threshold + self.tempDeadband
            }
            if !accepted {
                desired = self.tempKeys
            }
        }
        if desired != self.tempKeys {
            self.rebuildTempRows(desired)
        }
        for row in self.tempRows {
            guard let sensor = self.latestTemps[row.key] else { continue }
            if row.value.stringValue != sensor.formattedValue {
                row.value.stringValue = sensor.formattedValue
            }
        }
        self.updateShowAllRow()
        // keep the disclosure row on top of the z-order across fan rebuilds
        self.sensorsFansContainer.addSubview(self.showAllButton)
        self.layoutFanContainer()
        self.onLayoutChange?()
    }
    
    func rebuildTempRows(_ keys: [String]) {
        for row in self.tempRows {
            row.name.removeFromSuperview()
            row.value.removeFromSuperview()
        }
        self.tempRows = keys.map { key in
            let name = unifiedLabel(self.latestTemps[key]?.name ?? key, font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
            let value = unifiedLabel(self.latestTemps[key]?.formattedValue ?? "–", font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .labelColor, alignment: .right)
            name.identifier = NSUserInterfaceItemIdentifier("temp")
            value.identifier = NSUserInterfaceItemIdentifier("temp")
            self.sensorsFansContainer.addSubview(name)
            self.sensorsFansContainer.addSubview(value)
            return (key, name, value)
        }
        self.tempKeys = keys
    }
    
    func updateShowAllRow() {
        let extra = max(self.totalTempCount - 5, 0)
        self.showAllButton.isHidden = extra == 0
        let title = "\(localizedString("All sensors")) (\(self.totalTempCount)) ›"
        self.showAllButton.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }
    
    @objc func openAllSensors() {
        SensorsAllPopover.shared.show(relativeTo: self.showAllButton.bounds, of: self.showAllButton)
    }
    
    /// QA hook: open the all-sensors popover (same path as the row tap).
    func openAllSensorsForQA() {
        self.openAllSensors()
    }
    
    func layoutFanContainer() {
        let width = max(self.sensorsRow.expandContainer.bounds.width, 100)
        var y: CGFloat = 0
        var index = 0
        for case let fanView as FanView in self.sensorsFansContainer.subviews {
            let height = index < self.fanHeights.count ? self.fanHeights[index] : max(ceil(fanView.frame.height), 64)
            fanView.frame = NSRect(x: 0, y: y, width: width, height: height)
            y += height + 6
            index += 1
        }
        for row in self.tempRows {
            row.name.frame = NSRect(x: 0, y: y + 1, width: 220, height: 14)
            row.value.frame = NSRect(x: width - 100, y: y + 1, width: 100, height: 14)
            y += 18
        }
        if !self.showAllButton.isHidden {
            self.showAllButton.frame = NSRect(x: 0, y: y + 3, width: width, height: 16)
            y += 24
        }
        let height = max(ceil(y), 30)
        self.sensorsFansContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
        self.sensorsRow.detailHeight = height
        self.sensorsRow.expandContainer.frame = NSRect(x: 8, y: 44, width: self.sensorsRow.bounds.width - 16, height: height)
    }
}
