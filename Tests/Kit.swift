//
//  Kit.swift
//  Tests
//
//  Created by Serhiy Mytrovtsiy on 04/07/2026.
//  Using Swift 6.0.
//  Running on macOS 26.5.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import XCTest
import Kit
@testable import Stats

class KitTests: XCTestCase {
    @MainActor
    func testSettingsWindow_initializesWithAdaptiveMinimumSize() throws {
        let window = SettingsWindow()
        defer { window.close() }

        XCTAssertGreaterThanOrEqual(window.frame.width, Constants.Design.settingsMinimumSize.width)
        XCTAssertGreaterThanOrEqual(window.frame.height, Constants.Design.settingsMinimumSize.height)
    }

    @MainActor
    func testSettingsSidebar_usesFocusableLabeledRows() throws {
        func descendants(of view: NSView) -> [NSView] {
            view.subviews + view.subviews.flatMap(descendants)
        }

        func assertVisible(_ view: NSView, in contentView: NSView, file: StaticString = #filePath, line: UInt = #line) {
            let frame = view.convert(view.bounds, to: contentView)
            XCTAssertGreaterThan(frame.width, 0, file: file, line: line)
            XCTAssertGreaterThan(frame.height, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minX, contentView.bounds.minX, file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.minY, contentView.bounds.minY, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxX, contentView.bounds.maxX, file: file, line: line)
            XCTAssertLessThanOrEqual(frame.maxY, contentView.bounds.maxY, file: file, line: line)
        }

        let window = SettingsWindow()
        defer { window.close() }
        window.open(module: "Dashboard")
        window.contentView?.layoutSubtreeIfNeeded()

        let buttons = descendants(of: try XCTUnwrap(window.contentView)).compactMap { $0 as? NSButton }
        let navigation = buttons
            .filter { ["Dashboard", "Settings"].contains($0.accessibilityLabel()) }

        XCTAssertEqual(Set(navigation.compactMap { $0.accessibilityLabel() }), Set(["Dashboard", "Settings"]))
        XCTAssertTrue(navigation.allSatisfy { $0.focusRingType == .default })
        navigation.forEach { button in
            let stack = button.superview as? NSStackView
            XCTAssertNotNil(stack)
            XCTAssertEqual(
                button.frame.width,
                (stack?.bounds.width ?? 0) - Constants.Design.space4,
                accuracy: 1,
                "\(button.accessibilityLabel() ?? "Navigation item") should fill the sidebar row"
            )
            XCTAssertEqual(button.frame.minX, Constants.Design.space2, accuracy: 1)
        }
        XCTAssertTrue(["Pause the Stats", "More actions"].allSatisfy { label in
            buttons.contains { $0.accessibilityLabel() == label && $0.focusRingType == .default }
        })

        window.open(module: "Settings")
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.toolbar?.items.contains(where: { $0.itemIdentifier == .toggleSidebar }) == true)
        let contentView = try XCTUnwrap(window.contentView)
        for label in ["Pause the Stats", "More actions"] {
            let button = try XCTUnwrap(buttons.first { $0.accessibilityLabel() == label })
            XCTAssertFalse(button.isHidden)
            assertVisible(button, in: contentView)
        }
        assertVisible(try XCTUnwrap(navigation.first { $0.accessibilityLabel() == "Settings" }), in: contentView)
    }

    func testIsNewestVersion_release() throws {
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.11.0"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.11.1"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.1", latestVersion: "v2.11.0"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.12.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.12.0", latestVersion: "v2.11.5"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v3.0.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v3.0.0", latestVersion: "v2.99.99"))
    }
    
    func testIsNewestVersion_beta() throws {
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.0-beta1"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0-beta2", latestVersion: "v2.11.0-beta1"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.0-beta2"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.10.9"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v2.11.0", latestVersion: "v2.11.1-beta1"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v2.11.0-beta1", latestVersion: "v2.11.1-beta1"))
    }
    
    func testIsNewestVersion_malformed() throws {
        XCTAssertFalse(isNewestVersion(currentVersion: "v3", latestVersion: "v3.0.0"))
        XCTAssertTrue(isNewestVersion(currentVersion: "v3", latestVersion: "v3.0.1"))
        XCTAssertFalse(isNewestVersion(currentVersion: "v3.0", latestVersion: "v3.0.0"))
        XCTAssertFalse(isNewestVersion(currentVersion: "", latestVersion: ""))
    }
    
    func testUnitsGetReadableSpeed_byte() throws {
        XCTAssertEqual(Units(bytes: 0).getReadableSpeed(base: .byte), "0 KB/s")
        XCTAssertEqual(Units(bytes: 999).getReadableSpeed(base: .byte), "0 KB/s")
        XCTAssertEqual(Units(bytes: 1_000).getReadableSpeed(base: .byte), "1 KB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte), "500 KB/s")
        XCTAssertEqual(Units(bytes: 2_500_000).getReadableSpeed(base: .byte), "2.5 MB/s")
        XCTAssertEqual(Units(bytes: 150_000_000).getReadableSpeed(base: .byte), "150 MB/s")
        XCTAssertEqual(Units(bytes: 2_000_000_000).getReadableSpeed(base: .byte), "2.0 GB/s")
        XCTAssertEqual(Units(bytes: 2_000_000_000_000).getReadableSpeed(base: .byte), "2.0 TB/s")
        XCTAssertEqual(Units(bytes: -5).getReadableSpeed(base: .byte), "0 KB/s")
    }
    
    func testUnitsGetReadableSpeed_bit() throws {
        XCTAssertEqual(Units(bytes: 100).getReadableSpeed(base: .bit), "0 Kb/s")
        XCTAssertEqual(Units(bytes: 50_000).getReadableSpeed(base: .bit), "400 Kb/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .bit), "4.0 Mb/s")
        XCTAssertEqual(Units(bytes: 200_000_000).getReadableSpeed(base: .bit), "1.6 Gb/s")
        XCTAssertEqual(Units(bytes: 200_000_000_000).getReadableSpeed(base: .bit), "1.6 Tb/s")
    }
    
    func testUnitsGetReadableSpeed_fixedUnit() throws {
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte, unit: "KB"), "500 KB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .byte, unit: "MB"), "0.5 MB/s")
        XCTAssertEqual(Units(bytes: 500_000).getReadableSpeed(base: .bit, unit: "MB"), "4 Mb/s")
    }
}
