//
//  constants.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 15/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public struct Popup_c_s {
    public let width: CGFloat = 264
    public let height: CGFloat = 300
    public let margins: CGFloat = 8
    public let spacing: CGFloat = 2
    public let headerHeight: CGFloat = 42
    public let separatorHeight: CGFloat = 30
    public let radius: CGFloat = 6
    public let processHeight: CGFloat = 22
}

public struct Settings_c_s {
    public let width: CGFloat = 540
    public let height: CGFloat = 480
    public let margin: CGFloat = 10
}

public struct Design_c_s {
    public let space1: CGFloat = 4
    public let space2: CGFloat = 8
    public let space3: CGFloat = 12
    public let space4: CGFloat = 16
    public let space5: CGFloat = 20
    public let space6: CGFloat = 24
    public let space8: CGFloat = 32

    public let sectionRadius: CGFloat = 10
    public let navigationRowHeight: CGFloat = 36
    public let minimumControlSize: CGFloat = 32

    public let sidebarWidth: CGFloat = 184
    public let sidebarMinimumWidth: CGFloat = 168
    public let sidebarMaximumWidth: CGFloat = 240
    public let contentMinimumWidth: CGFloat = 560
    public let settingsDefaultSize = CGSize(width: 900, height: 620)
    public let settingsMinimumSize = CGSize(width: 760, height: 520)
}

public struct Widget_c_s {
    public let width: CGFloat = 32
    public var height: CGFloat {
        get {
            let systemHeight = NSApplication.shared.mainMenu?.menuBarHeight
            return (systemHeight == 0 ? 22 : systemHeight) ?? 22
        }
    }
    public var margin: CGPoint {
        get { CGPoint(x: 0, y: 2) }
    }
    public let spacing: CGFloat = 2
}

public struct Constants {
    public static let Popup: Popup_c_s = Popup_c_s()
    public static let Settings: Settings_c_s = Settings_c_s()
    public static let Widget: Widget_c_s = Widget_c_s()
    public static let Design: Design_c_s = Design_c_s()
    
    public static let defaultProcessIcon = NSWorkspace.shared.icon(forFile: "/bin/bash")
}

public enum ModuleType: Int {
    case CPU
    case RAM
    case GPU
    case disk
    case sensors
    case network
    case battery
    case bluetooth
    case clock
    case remote
    
    case combined
    
    public var stringValue: String {
        switch self {
        case .CPU: return "CPU"
        case .RAM: return "RAM"
        case .GPU: return "GPU"
        case .disk: return "Disk"
        case .sensors: return "Sensors"
        case .network: return "Network"
        case .battery: return "Battery"
        case .bluetooth: return "Bluetooth"
        case .clock: return "Clock"
        case .remote: return "Remote"
        case .combined: return ""
        }
    }
    
    public var activityMonitorTab: Int? {
        switch self {
        case .CPU: return 0
        case .RAM: return 1
        case .disk: return 3
        case .network: return 4
        case .battery: return 2
        default: return nil
        }
    }
}
