//
//  UnifiedDesignSystem.swift
//  Stats
//
//  Design-system layer for the unified panel, split out of
//  UnifiedPanelContent: perf/motion instrumentation, design tokens,
//  label/symbol factories, and the shared chrome views (sparkline,
//  card, hairline, chip). Extracted verbatim — no logic changes.
//

import Cocoa

// MARK: - perf instrumentation (env STATS_POPUP_PERF=1)
enum UnifiedPerf {
    static let enabled = ProcessInfo.processInfo.environment["STATS_POPUP_PERF"] == "1"
    private static var acc: [String: (ms: Double, n: Int, frames: Int)] = [:]

    static func measure(_ label: String, _ block: () -> Void) {
        guard self.enabled else { block(); return }
        let start = CFAbsoluteTimeGetCurrent()
        block()
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        var e = self.acc[label] ?? (0, 0, 0)
        e.ms += ms
        e.n += 1
        self.acc[label] = e
    }

    static func frameSet(_ label: String) {
        guard self.enabled else { return }
        var e = self.acc[label] ?? (0, 0, 0)
        e.frames += 1
        self.acc[label] = e
    }

    static func tick() {
        guard self.enabled, !self.acc.isEmpty else { return }
        var line: [String] = []
        for (key, e) in self.acc.sorted(by: { $0.key < $1.key }) where e.n > 0 || e.frames > 0 {
            let avg = e.n > 0 ? e.ms / Double(e.n) : 0
            line.append(String(format: "%@ avg %.2fms n=%d frameSets=%d", key, avg, e.n, e.frames))
        }
        self.acc = [:]
        NSLog("[UnifiedPerf] %@", line.joined(separator: " | "))
    }
}

// MARK: - motion (env-gated)
//
// The motion set (panel entrance/exit, expand spring, chevron
// rotation) is disabled whenever ANY QA or capture knob is
// active — captures and probes must see final state, never a
// mid-animation frame.
enum UnifiedMotion {
    static let enabled: Bool = {
        let env = ProcessInfo.processInfo.environment
        // QA escape hatch: force animations ON during a QA run so the
        // motion path itself can be probed.
        if env["STATS_QA_MOTION"] == "1" { return true }
        if env["STATS_POPUP_CAPTURE"] == "1" { return false }
        if env["STATS_POPUP_PERF"] == "1" { return false }
        if env["STATS_POPUP_DEBUG_PAINT"] == "1" { return false }
        return !env.contains { key, value in
            key.hasPrefix("STATS_QA_") && !value.isEmpty && value != "0"
        }
    }()
}

// MARK: - design tokens
//
// Extracted from stats-unified-redesign.html (column E). Light and dark
// are independently designed token sets, not inversions. Semantic label
// colors already match the mock's text/text-2/text-3 rgba values.
enum UnifiedTokens {
    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let pillRadius: CGFloat = 8
    static let chipRadius: CGFloat = 8
    static let contentMargin: CGFloat = 12

    static var isDark: Bool {
        switch NSAppearance.currentDrawing().name {
        case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
            return true
        default:
            return false
        }
    }

    private static func hex(_ value: UInt32, _ alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: alpha)
    }

    // surfaces (mock: --card / --card-border / --well / --hairline / --panel-border)
    static var card: NSColor { isDark ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 1, alpha: 0.82) }
    static var cardBorder: NSColor { isDark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.05) }
    static var well: NSColor { isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.05) }
    static var hairline: NSColor { isDark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.08) }
    static var panelBorder: NSColor { isDark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.07) }

    // status (mock: --ok / --amber-ink / --red-ink, with -soft / -border alphas)
    static var ok: NSColor { isDark ? hex(0x30d158) : hex(0x248a3d) }
    static var amberInk: NSColor { isDark ? hex(0xffb340) : hex(0x8a5200) }
    static var redInk: NSColor { isDark ? hex(0xff6961) : hex(0xc62828) }
    static var amberSoft: NSColor { .systemOrange.withAlphaComponent(isDark ? 0.15 : 0.18) }
    static var amberBorder: NSColor { .systemOrange.withAlphaComponent(isDark ? 0.38 : 0.45) }
    static var redSoft: NSColor { .systemRed.withAlphaComponent(isDark ? 0.16 : 0.13) }
    static var redBorder: NSColor { .systemRed.withAlphaComponent(isDark ? 0.38 : 0.45) }

    // mock: --shadow-card 0 1px 2px (dark .25 / light .06)
    static var cardShadowAlpha: CGFloat { isDark ? 0.25 : 0.06 }
}


// MARK: - sparkline

/// Thin single-hue sparkline: no axes, no fills, rounded joins.
final class UnifiedSparklineView: NSView {
    enum Scale {
        case fixed // 0...100
        case auto  // padded min/max
    }

    var scale: Scale = .auto
    var strokeColor = NSColor.controlAccentColor {
        didSet { self.needsDisplay = true }
    }
    private var values: [Double] = []
    /// One minute of history at the readers' 1 Hz cadence.
    private let capacity = 60
    /// Smooth-scroll state: when a point arrives, the new layout slides
    /// in from the right over one second instead of jumping a full cell
    /// at 1 Hz (motion-gated so QA captures stay deterministic).
    private var scrollStart: Date?
    private var scrollTimer: Timer?
    /// Value span before the latest point, for blending the auto scale.
    private var previousSpan: (lo: Double, hi: Double)?

    override var isOpaque: Bool { false }

    func add(_ value: Double) {
        if self.scale == .auto, self.values.count > 1 {
            self.previousSpan = self.currentSpan()
        }
        self.values.append(value)
        if self.values.count > self.capacity {
            self.values.removeFirst(self.values.count - self.capacity)
        }
        if UnifiedMotion.enabled {
            self.scrollStart = Date()
            if self.scrollTimer == nil {
                let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                    guard let self, let start = self.scrollStart else { return }
                    if Date().timeIntervalSince(start) >= 1.0 {
                        self.scrollTimer?.invalidate()
                        self.scrollTimer = nil
                    }
                    self.needsDisplay = true
                }
                RunLoop.main.add(timer, forMode: .common)
                self.scrollTimer = timer
            }
        }
        self.needsDisplay = true
    }

    deinit {
        self.scrollTimer?.invalidate()
    }

    private func currentSpan() -> (lo: Double, hi: Double) {
        switch self.scale {
        case .fixed:
            return (0, 100)
        case .auto:
            let min = self.values.min() ?? 0
            let max = self.values.max() ?? 1
            let span = Swift.max(max - min, 1)
            return (min - span * 0.25, max + span * 0.25)
        }
    }

    override func draw(_ rect: NSRect) {
        guard self.values.count > 1 else { return }
        let (loNow, hiNow) = self.currentSpan()
        // Blend factor for the scroll animation: 0 = the layout before
        // the latest point, 1 = the settled layout with it.
        var u: CGFloat = 1
        if let start = self.scrollStart {
            let t = CGFloat(Date().timeIntervalSince(start))
            if t >= 1 {
                self.scrollStart = nil
                self.previousSpan = nil
                u = 1
            } else {
                u = t
            }
        }
        let (lo, hi): (Double, Double)
        if let previous = self.previousSpan, u < 1 {
            lo = previous.lo + (loNow - previous.lo) * Double(u)
            hi = previous.hi + (hiNow - previous.hi) * Double(u)
        } else {
            lo = loNow
            hi = hiNow
        }
        let path = NSBezierPath()
        let w = self.bounds.width
        let h = self.bounds.height
        let segments = self.values.count - 1
        // Old layout: the window without the newest point spread over
        // the full width; new layout: the full window. Interpolating the
        // x positions slides the history left as the fresh point enters
        // from the right edge.
        let oldDen = CGFloat(max(segments - 1, 1))
        let newDen = CGFloat(max(segments, 1))
        for (i, value) in self.values.enumerated() {
            let oldX = CGFloat(i) / oldDen * w
            let newX = CGFloat(i) / newDen * w
            let x = oldX + (newX - oldX) * u
            // Non-flipped view inside a flipped row: higher values draw
            // toward the TOP of the band (100% up, nominal thermal low).
            let y = 2 + CGFloat((value - lo) / (hi - lo)) * (h - 5)
            if i == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        self.strokeColor.setStroke()
        path.stroke()
    }
}

// MARK: - chrome helpers

final class UnifiedFlippedView: NSView {
    override var isFlipped: Bool { true }
}

func unifiedLabel(_ string: String = "", font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) -> NSTextField {
    let field = NSTextField(labelWithString: string)
    field.font = font
    field.textColor = color
    field.alignment = alignment
    field.lineBreakMode = .byTruncatingTail
    return field
}

func unifiedSymbol(_ name: String, scale: NSImage.SymbolScale = .medium) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(textStyle: .body, scale: scale))
}

class UnifiedCardView: NSView {
    /// 0 quiet, 1 attention, 2 critical - tints the card background AND
    /// border. The border is owned here alone (updateLayer); poking
    /// layer?.borderColor from outside leaves a stale attention tint
    /// behind after the recovery.
    var statusLevel: Int = 0 {
        didSet { self.updateLayer() }
    }

    override var isFlipped: Bool { true }

    override func updateLayer() {
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            switch self.statusLevel {
            case 1:
                self.layer?.backgroundColor = UnifiedTokens.amberSoft.cgColor
                self.layer?.borderColor = UnifiedTokens.amberBorder.cgColor
            case 2:
                self.layer?.backgroundColor = UnifiedTokens.redSoft.cgColor
                self.layer?.borderColor = UnifiedTokens.redBorder.cgColor
            default:
                self.layer?.backgroundColor = UnifiedTokens.card.cgColor
                self.layer?.borderColor = UnifiedTokens.cardBorder.cgColor
            }
            self.layer?.shadowColor = NSColor(white: 0, alpha: UnifiedTokens.cardShadowAlpha).cgColor
        }
    }

    override func layout() {
        super.layout()
        // mock: --shadow-card, 0 1px 2px
        self.layer?.shadowOpacity = 1
        self.layer?.shadowOffset = NSSize(width: 0, height: -1)
        self.layer?.shadowRadius = 2
    }
}

final class UnifiedHairline: NSView {
    override func updateLayer() {
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = UnifiedTokens.hairline.cgColor
        }
    }
}

/// Small rounded status chip (header verdict).
final class UnifiedChipView: NSView {
    let textField = unifiedLabel(font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor)
    /// 0 quiet, 1 attention, 2 critical.
    var level: Int = 0

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.cornerRadius = UnifiedTokens.chipRadius
        self.addSubview(self.textField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            switch self.level {
            case 1:
                self.layer?.backgroundColor = UnifiedTokens.amberSoft.cgColor
            case 2:
                self.layer?.backgroundColor = UnifiedTokens.redSoft.cgColor
            default:
                self.layer?.backgroundColor = UnifiedTokens.well.cgColor
            }
        }
    }

    func setAttributed(_ value: NSAttributedString) {
        self.textField.attributedStringValue = value
        self.textField.sizeToFit()
        let size = self.textField.frame.size
        self.frame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y, width: size.width + 16, height: 20)
        self.textField.frame = NSRect(x: 8, y: 4, width: size.width, height: 13)
    }
}
