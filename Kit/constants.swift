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
    public let width: CGFloat = 304
    public let height: CGFloat = 300
    public let maximumHeight: CGFloat = 720
    public let margins: CGFloat = 8
    public let spacing: CGFloat = 2
    public let headerHeight: CGFloat = 48
    public let separatorHeight: CGFloat = 30
    public let radius: CGFloat = 10
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

    public let separatorOpacity: CGFloat = 0.55
    public let hairlineWidth: CGFloat = 1
    public let trendLineWidth: CGFloat = 2

    public let metricTrendHeight: CGFloat = 38
    public let metricCardHeight: CGFloat = 148
    public let metricCardMinimumWidth: CGFloat = 220
    public let healthRibbonItemHeight: CGFloat = 52
    public let healthRibbonHeight: CGFloat = 128
    public let healthRibbonColumns: Int = 3
    public let deviceIconSize: CGFloat = 58
    public let supportPopoverSize = CGSize(width: 220, height: 56)

    public let sidebarWidth: CGFloat = 184
    public let sidebarMinimumWidth: CGFloat = 168
    public let sidebarMaximumWidth: CGFloat = 240
    public let contentMinimumWidth: CGFloat = 560
    public let dashboardTwoColumnMinimumWidth: CGFloat = 656
    public let dashboardThreeColumnMinimumWidth: CGFloat = 900
    public let settingsDefaultSize = CGSize(width: 900, height: 620)
    public let settingsMinimumSize = CGSize(width: 760, height: 520)

    public var surfaceSecondary: NSColor { .underPageBackgroundColor }
    public var surfaceElevated: NSColor { .windowBackgroundColor }
    public var textSecondary: NSColor { .secondaryLabelColor }
    public var separatorSubtle: NSColor { .separatorColor }
    public var accentPrimary: NSColor { .controlAccentColor }
    public var statusHealthy: NSColor { .systemGreen }
    public var statusAttention: NSColor { .systemOrange }
    public var statusCritical: NSColor { .systemRed }

    public var healthHeadlineFont: NSFont { .systemFont(ofSize: 24, weight: .semibold) }
    public var metricValueFont: NSFont { .monospacedDigitSystemFont(ofSize: 20, weight: .semibold) }
    public var compactMetricValueFont: NSFont { .monospacedDigitSystemFont(ofSize: 14, weight: .semibold) }
    public var sectionTitleFont: NSFont { .systemFont(ofSize: 15, weight: .semibold) }
    public var bodyFont: NSFont { .systemFont(ofSize: 13, weight: .regular) }
    public var bodyEmphasisFont: NSFont { .systemFont(ofSize: 13, weight: .medium) }
    public var secondaryFont: NSFont { .systemFont(ofSize: 12, weight: .regular) }
    public var secondaryEmphasisFont: NSFont { .systemFont(ofSize: 12, weight: .medium) }
    public var captionFont: NSFont { .systemFont(ofSize: 11, weight: .medium) }
    public var captionRegularFont: NSFont { .systemFont(ofSize: 11, weight: .regular) }
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
