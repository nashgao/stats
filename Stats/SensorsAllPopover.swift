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
    private static weak var instance: SensorsAllPopover?

    /// Closing the main panel must not instantiate an unopened popover.
    static func closeIfShown() {
        guard let instance = self.instance, instance.isShown else { return }
        instance.close()
    }
    
    private let popover = NSPopover()
    private let content = SensorsAllPopoverContent()
    private var escapeMonitor: Any?
    
    private override init() {
        super.init()
        self.popover.contentViewController = self.content
        self.popover.behavior = .transient
        self.popover.animates = true
        self.popover.delegate = self
        Self.instance = self
    }
    
    var isShown: Bool { self.popover.isShown }
    
    func show(relativeTo rect: NSRect, of view: NSView) {
        self.popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        self.content.isPresented = self.popover.isShown
        self.content.refresh()
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
    
    func popoverWillClose(_ notification: Notification) {
        self.content.isPresented = false
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
    fileprivate var isPresented = false
    private let scroll = NSScrollView()
    private let document = FlippedDocumentView()
    private let emptyField = NSTextField(labelWithString: "")
    private var latest: [String: Sensor_p] = [:]
    private var keys: [String] = []
    private var rows: [String: (name: NSTextField, value: NSTextField)] = [:]
    
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
    
    /// Hidden popovers cache samples only. Visible rows keep their view
    /// identity across ranking and filter changes; only their positions
    /// and readouts change.
    func refresh() {
        guard self.isPresented, self.isViewLoaded else { return }
        let desired = SensorsAllPopover.filteredKeys(self.latest, query: self.searchField.stringValue)
        if desired != self.keys {
            self.layoutRows(desired)
        }
        for key in self.keys {
            guard let sensor = self.latest[key], let row = self.rows[key] else { continue }
            if row.name.stringValue != sensor.name {
                row.name.stringValue = sensor.name
            }
            let value = sensor.formattedValue
            if row.value.stringValue != value {
                row.value.stringValue = value
            }
        }
    }
    
    private func layoutRows(_ desired: [String]) {
        let visibleKeys = Set(desired)
        for (key, row) in self.rows where !visibleKeys.contains(key) && !row.name.isHidden {
            row.name.isHidden = true
            row.value.isHidden = true
        }
        var y: CGFloat = 4
        for key in desired {
            let row: (name: NSTextField, value: NSTextField)
            if let existing = self.rows[key] {
                row = existing
            } else {
                let name = unifiedLabel(font: .systemFont(ofSize: 12, weight: .regular), color: .secondaryLabelColor)
                let value = unifiedLabel(font: .monospacedDigitSystemFont(ofSize: 12, weight: .semibold), color: .labelColor, alignment: .right)
                row = (name, value)
                self.rows[key] = row
                self.document.addSubview(name)
                self.document.addSubview(value)
            }
            if row.name.isHidden {
                row.name.isHidden = false
                row.value.isHidden = false
            }
            let nameFrame = NSRect(x: 12, y: y + 3, width: 260, height: 16)
            let valueFrame = NSRect(x: 268, y: y + 3, width: 100, height: 16)
            if row.name.frame != nameFrame { row.name.frame = nameFrame }
            if row.value.frame != valueFrame { row.value.frame = valueFrame }
            y += Self.rowHeight
        }
        let frame = NSRect(x: 0, y: 0, width: 380, height: max(y, 30))
        if self.document.frame != frame { self.document.frame = frame }
        self.keys = desired
        self.emptyField.isHidden = !desired.isEmpty
    }
    
    func controlTextDidChange(_ obj: Notification) {
        self.refresh()
    }
}
