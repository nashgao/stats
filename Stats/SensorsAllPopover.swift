//
//  SensorsAllPopover.swift
//  Stats
//
//  All-sensors lookup popover: the full hot-first temperature list with
//  a live filter, presented as a native NSPopover from the unified
//  panel's "All sensors" row. Keeps the panel itself compact — the full
//  list lives here, where real scrolling and search belong.
//

import Cocoa
import Kit
import Sensors

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class SensorsAllPopover: NSObject, NSPopoverDelegate {
    static let shared = SensorsAllPopover()
    
    private let popover = NSPopover()
    private let content = SensorsAllPopoverContent()
    private var escapeMonitor: Any?
    
    private override init() {
        super.init()
        self.popover.contentViewController = self.content
        self.popover.behavior = .transient
        self.popover.animates = true
        self.popover.delegate = self
    }
    
    var isShown: Bool { self.popover.isShown }
    
    func show(relativeTo rect: NSRect, of view: NSView) {
        self.content.refreshNow()
        self.popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        view.window?.makeFirstResponder(self.content.searchField)
        self.escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.close()
            return nil
        }
    }
    
    func close() {
        self.popover.performClose(nil)
    }
    
    func popoverDidClose(_ notification: Notification) {
        if let monitor = self.escapeMonitor {
            NSEvent.removeMonitor(monitor)
            self.escapeMonitor = nil
        }
    }
    
    /// Testable filter: hot-first keys whose name or key contains the
    /// query (case-insensitive); an empty query keeps everything.
    static func filteredKeys(_ latest: [String: Sensor_p], query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return latest
            .filter { q.isEmpty || $0.value.name.lowercased().contains(q) || $0.key.lowercased().contains(q) }
            .sorted { lhs, rhs in
                if lhs.value.value != rhs.value.value {
                    return lhs.value.value > rhs.value.value
                }
                return lhs.value.name < rhs.value.name
            }
            .map { $0.key }
    }
}

final class SensorsAllPopoverContent: NSViewController, NSSearchFieldDelegate {
    fileprivate let searchField = NSSearchField()
    private let scroll = NSScrollView()
    private let document = FlippedDocumentView()
    private let emptyField = NSTextField(labelWithString: "")
    private var latest: [String: Sensor_p] = [:]
    private var keys: [String] = []
    private var rows: [(key: String, name: NSTextField, value: NSTextField)] = []
    
    private static let rowHeight: CGFloat = 22
    
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.sample(_:)), name: .unifiedPanelSample, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 520))
        self.view = root
        
        self.searchField.frame = NSRect(x: 12, y: 484, width: 356, height: 24)
        self.searchField.placeholderString = localizedString("Filter sensors")
        self.searchField.delegate = self
        root.addSubview(self.searchField)
        
        self.scroll.frame = NSRect(x: 0, y: 0, width: 380, height: 476)
        self.scroll.hasVerticalScroller = true
        self.scroll.borderType = .noBorder
        self.scroll.drawsBackground = false
        self.scroll.backgroundColor = .clear
        self.scroll.documentView = self.document
        root.addSubview(self.scroll)
        
        self.emptyField.stringValue = localizedString("No matching sensors")
        self.emptyField.font = .systemFont(ofSize: 12)
        self.emptyField.textColor = .secondaryLabelColor
        self.emptyField.alignment = .center
        self.emptyField.frame = NSRect(x: 0, y: 218, width: 380, height: 40)
        root.addSubview(self.emptyField)
    }
    
    @objc private func sample(_ notification: Notification) {
        guard let list = notification.object as? Sensors_List else { return }
        // .unifiedPanelSample is posted from the reader queue — view work
        // must happen on the main thread (the popover's AutoLayout engine
        // is primed from there, so background addSubview crashes).
        DispatchQueue.main.async {
            for sensor in list.sensors where sensor.type == .temperature && sensor.value.isFinite {
                self.latest[sensor.key] = sensor
            }
            self.refresh()
        }
    }
    
    /// Re-apply the current filter against the latest samples:
    /// membership changes rebuild the rows; otherwise values update
    /// in place — no per-tick reshuffle.
    func refresh() {
        let desired = SensorsAllPopover.filteredKeys(self.latest, query: self.searchField.stringValue)
        if desired != self.keys {
            self.rebuild(desired)
        }
        for row in self.rows {
            guard let sensor = self.latest[row.key] else { continue }
            if row.value.stringValue != sensor.formattedValue {
                row.value.stringValue = sensor.formattedValue
            }
        }
    }
    
    func refreshNow() {
        self.refresh()
    }
    
    private func rebuild(_ desired: [String]) {
        for row in self.rows {
            row.name.removeFromSuperview()
            row.value.removeFromSuperview()
        }
        var y: CGFloat = 4
        self.rows = desired.map { key in
            let sensor = self.latest[key]
            let name = unifiedLabel(sensor?.name ?? key, font: .systemFont(ofSize: 12, weight: .regular), color: .secondaryLabelColor)
            let value = unifiedLabel(sensor?.formattedValue ?? "–", font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold), color: .labelColor, alignment: .right)
            name.frame = NSRect(x: 12, y: y + 3, width: 260, height: 16)
            value.frame = NSRect(x: 268, y: y + 3, width: 100, height: 16)
            self.document.addSubview(name)
            self.document.addSubview(value)
            y += Self.rowHeight
            return (key, name, value)
        }
        self.document.frame = NSRect(x: 0, y: 0, width: 380, height: max(y, 30))
        self.keys = desired
        self.emptyField.isHidden = !self.rows.isEmpty
    }
    
    func controlTextDidChange(_ obj: Notification) {
        self.refresh()
    }
}
