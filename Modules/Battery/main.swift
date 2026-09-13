//
//  main.swift
//  Battery
//
//  Created by Serhiy Mytrovtsiy on 06/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit
import IOKit.ps

public struct Battery_Usage: Codable {
    public var powerSource: String = ""
    public var state: String? = nil
    public var isCharged: Bool = false
    public var isCharging: Bool = false
    public var isBatteryPowered: Bool = false
    public var optimizedChargingEngaged: Bool = false
    public var level: Double = 0
    public var cycles: Int = 0
    public var health: Int = 0
    
    public var designedCapacity: Int = 0
    public var maxCapacity: Int = 0
    public var currentCapacity: Int = 0
    
    public var current: Int = 0
    public var voltage: Double = 0
    public var temperature: Double = 0
    public var batteryPower: Double = 0

    public var ACwatts: Int = 0
    public var chargingCurrent: Int = 0
    public var chargingVoltage: Int = 0
    public var adapterPower: Double = 0
    public var adapterVoltage: Double = 0
    
    public var timeToEmpty: Int = 0
    public var timeToCharge: Int = 0
    public var timeOnACPower: Date? = nil
}

public class Battery: Module {
    private let popupView: Popup
    private let settingsView: Settings
    private let portalView: Portal
    private let notificationsView: Notifications
    
    private var usageReader: UsageReader? = nil
    private var processReader: ProcessReader? = nil
    
    public init() {
        self.settingsView = Settings(.battery)
        self.popupView = Popup(.battery)
        self.portalView = Portal(.battery, height: 70)
        self.notificationsView = Notifications(.battery)
        
        super.init(
            moduleType: .battery,
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView
        )
        guard self.available else { return }
        
        self.usageReader = UsageReader(.battery) { [weak self] value in
            self?.usageCallback(value)
        }
        self.processReader = ProcessReader(.battery) { [weak self] value in
            if let list = value {
                self?.popupView.processCallback(list)
            }
        }
        
        self.settingsView.callback = { [weak self] in
            DispatchQueue.global(qos: .background).async {
                self?.usageReader?.read()
            }
        }
        self.settingsView.callbackWhenUpdateNumberOfProcesses = { [weak self] in
            self?.popupView.numberOfProcessesUpdated()
            DispatchQueue.global(qos: .background).async {
                self?.processReader?.read()
            }
        }
        
        self.setReaders([self.usageReader, self.processReader])
    }
    
    public override func willTerminate() {
        guard self.isAvailable() else { return }
        self.notificationsView.willTerminate()
    }
    
    public override func isAvailable() -> Bool {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        return !sources.isEmpty
    }
    
    private func usageCallback(_ raw: Battery_Usage?) {
        guard let value = raw, self.enabled else { return }
        
        self.popupView.usageCallback(value)
        NotificationCenter.default.post(name: .unifiedPanelSample, object: value)
        self.portalView.loadCallback(value)
        self.notificationsView.usageCallback(value)

        let batteryLevel = min(max(abs(value.level), 0), 1)
        let batteryState = value.isCharging
            ? localizedString("Charging")
            : localizedString(value.isBatteryPowered ? "On battery" : "Power adapter")
        NotificationCenter.default.post(
            name: .telemetrySample,
            object: TelemetrySample(
                metric: .battery,
                value: batteryLevel,
                secondaryValue: value.isBatteryPowered ? 0 : 1,
                power: value.isBatteryPowered ? -abs(value.batteryPower) : abs(value.batteryPower),
                displayValue: "\(Int((batteryLevel * 100).rounded()))%",
                detail: batteryState
            )
        )
        
        self.menuBar.widgets.filter{ $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini:
                widget.setValue(abs(value.level))
                widget.setColorZones((0.15, 0.3))
            case let widget as BarChart:
                widget.setValue([[ColorValue(value.level)]])
                widget.setColorZones((0.15, 0.3))
            case let widget as BatteryWidget:
                widget.setValue(
                    percentage: value.level,
                    ACStatus: !value.isBatteryPowered,
                    isCharging: value.isCharging,
                    optimizedCharging: value.optimizedChargingEngaged,
                    time: value.isBatteryPowered ? value.timeToEmpty : value.timeToCharge
                )
            case let widget as BatteryDetailsWidget:
                widget.setValue(
                    percentage: value.level,
                    time: value.isBatteryPowered ? value.timeToEmpty : value.timeToCharge
                )
            default: break
            }
        }
    }
}
