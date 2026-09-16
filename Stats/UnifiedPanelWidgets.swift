//
//  UnifiedPanelWidgets.swift
//  Stats
//
//  Self-contained detail widgets for the unified panel, split out of
//  UnifiedPanelContent to keep that file within the lint budget:
//  mini metrics, pills, grammar detail rows, and the top-processes
//  block. All frame-based, design-E grammar styling.
//

import Cocoa
import Kit

final class UnifiedMiniMetric: NSView {
    private let track = NSView()
    private let fill = NSView()
    private let valueField = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
    
    override var isFlipped: Bool { true }
    
    init(label: String, value: String, fraction: Double, color: NSColor? = nil) {
        super.init(frame: .zero)
        let labelField = unifiedLabel(label, font: .systemFont(ofSize: 10, weight: .regular), color: .tertiaryLabelColor)
        self.addSubview(labelField)
        self.addSubview(self.valueField)
        self.track.wantsLayer = true
        self.track.layer?.cornerRadius = 2
        self.fill.wantsLayer = true
        self.fill.layer?.cornerRadius = 2
        self.track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
        self.fill.layer?.backgroundColor = (color ?? .controlAccentColor).cgColor
        self.addSubview(self.track)
        self.addSubview(self.fill)
        labelField.frame = NSRect(x: 0, y: 0, width: 96, height: 12)
        self.valueField.frame = NSRect(x: 0, y: 14, width: 96, height: 12)
        self.valueField.stringValue = value
        self.track.frame = NSRect(x: 0, y: 28, width: 96, height: 4)
        self.fill.frame = NSRect(x: 0, y: 28, width: 96 * CGFloat(min(max(fraction, 0), 1)), height: 4)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Hero sub-metrics rendered as soft pills (well background, pill radius).
final class UnifiedPillRow: NSView {
    private var pills: [(view: NSView, label: NSTextField)] = []
    
    override var isFlipped: Bool { true }
    
    func setPills(_ texts: [String]) {
        while self.pills.count > texts.count {
            self.pills.removeLast().view.removeFromSuperview()
        }
        while self.pills.count < texts.count {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.cornerRadius = 6
            // monospaced digits: live values must not reflow the pills
            let label = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor)
            view.addSubview(label)
            self.addSubview(view)
            self.pills.append((view, label))
        }
        var changed = false
        for (index, text) in texts.enumerated() {
            let pill = self.pills[index]
            guard pill.label.stringValue != text else { continue }
            changed = true
            pill.label.stringValue = text
            pill.label.sizeToFit()
            pill.view.frame = NSRect(x: 0, y: 0, width: ceil(pill.label.frame.width) + 16, height: 18)
            pill.label.frame = NSRect(x: 8, y: 4, width: pill.label.frame.width, height: 11)
        }
        guard changed else { return }
        var x: CGFloat = 0
        for pill in self.pills {
            pill.view.frame.origin.x = x
            x += pill.view.frame.width + 6
        }
        self.frame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y, width: max(x - 6, 0), height: 18)
    }
}

/// Design-E grammar detail block: name/value row pairs with fixed
/// frames, shared by the expandable grammar rows (Disk, Network,
/// Thermal, Battery). Rows beyond the live data set are hidden, never
/// removed — the expanded height stays constant (one-pass expand).
final class UnifiedDetailRows: NSView {
    private var names: [NSTextField] = []
    private(set) var values: [NSTextField] = []
    
    override var isFlipped: Bool { true }
    
    /// Adds a row; returns the value field for per-tick updates.
    @discardableResult
    func addRow(_ label: String) -> NSTextField {
        let name = unifiedLabel(label, font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        let value = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .labelColor, alignment: .right)
        self.addSubview(name)
        self.addSubview(value)
        self.names.append(name)
        self.values.append(value)
        return value
    }
    
    /// Fixed layout; returns the content height for detailHeight sizing.
    @discardableResult
    func layoutRows(width: CGFloat) -> CGFloat {
        var y: CGFloat = 0
        for index in 0..<self.names.count {
            self.names[index].frame = NSRect(x: 0, y: y + 1, width: 180, height: 14)
            self.values[index].frame = NSRect(x: width - 150, y: y + 1, width: 150, height: 14)
            y += 18
        }
        self.frame = NSRect(x: 0, y: 0, width: width, height: max(ceil(y), 30))
        return max(ceil(y), 30)
    }
    
    /// Shows the first `count` rows, hides the rest (reserved height is
    /// kept so the card does not change size).
    func setLiveRows(_ count: Int) {
        for index in 0..<self.names.count {
            self.names[index].isHidden = index >= count
            self.values[index].isHidden = index >= count
        }
    }
    
    /// Updates a row's label (volume names arrive with the sample).
    func setName(_ index: Int, _ value: String) {
        guard index < self.names.count else { return }
        self.names[index].stringValue = value
    }
}

/// "Top processes" block: title + name/share-bar/value rows.
final class UnifiedTopProcesses: NSView {
    private struct Row {
        let name: NSTextField
        let value: NSTextField
        let track: NSView
        let fill: NSView
    }
    private var rows: [Row] = []
    
    override var isFlipped: Bool { true }
    
    init(title: String, rows: [(name: String, share: Double, value: String)]) {
        super.init(frame: .zero)
        let titleField = unifiedLabel(title.uppercased(), font: .systemFont(ofSize: 10, weight: .semibold), color: .tertiaryLabelColor)
        self.addSubview(titleField)
        titleField.frame = NSRect(x: 0, y: 0, width: 240, height: 12)
        var y: CGFloat = 16
        for _ in rows {
            let name = unifiedLabel(font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
            let value = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold), color: .labelColor, alignment: .right)
            let track = NSView()
            let fill = NSView()
            track.wantsLayer = true
            track.layer?.cornerRadius = 2
            track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.15).cgColor
            fill.wantsLayer = true
            fill.layer?.cornerRadius = 2
            fill.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            self.addSubview(name)
            self.addSubview(track)
            self.addSubview(fill)
            self.addSubview(value)
            name.frame = NSRect(x: 0, y: y + 1, width: 110, height: 14)
            track.frame = NSRect(x: 114, y: y + 6, width: 130, height: 4)
            fill.frame = NSRect(x: 114, y: y + 6, width: 0, height: 4)
            value.frame = NSRect(x: 248, y: y + 1, width: 76, height: 14)
            self.rows.append(Row(name: name, value: value, track: track, fill: fill))
            y += 19
        }
        self.frame = NSRect(x: 0, y: 0, width: 324, height: y)
        self.update(rows: rows)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// In-place per-tick refresh: no view churn when the process set is
    /// stable. Rows without data are hidden — empty skeleton rows must
    /// never be visible.
    func update(rows: [(name: String, share: Double, value: String)]) {
        for index in 0..<self.rows.count {
            let view = self.rows[index]
            guard index < rows.count else {
                view.name.isHidden = true
                view.value.isHidden = true
                view.track.isHidden = true
                view.fill.isHidden = true
                continue
            }
            let row = rows[index]
            view.name.isHidden = false
            view.value.isHidden = false
            view.track.isHidden = false
            view.fill.isHidden = false
            if view.name.stringValue != row.name {
                view.name.stringValue = row.name
            }
            if view.value.stringValue != row.value {
                view.value.stringValue = row.value
            }
            let width = 130 * CGFloat(min(max(row.share, 0), 1))
            if abs(view.fill.frame.width - width) > 0.5 {
                view.fill.frame = NSRect(x: 114, y: view.fill.frame.origin.y, width: width, height: 4)
            }
        }
    }
}


extension UnifiedMiniMetric {
    func set(value: String, fraction: Double) {
        self.valueField.stringValue = value
        self.fill.frame = NSRect(x: 0, y: 28, width: 96 * CGFloat(min(max(fraction, 0), 1)), height: 4)
    }
}
