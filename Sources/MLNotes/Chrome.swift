import AppKit

extension NSColor {
    convenience init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) { self.init(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }
}

/// Maße in Punkten bei 1×, aus der 1×-Referenz (Ars Technica, Ampel Ø12/Abstand 20) gemessen.
/// ponytail: Originalmessung auf 10.8 steht aus (Lastenheft M1); alle Werte zentral hier.
enum M {
    static let titleH: CGFloat = 23            // Lederkopf
    static let sidebarW: CGFloat = 130
    static let listW: CGFloat = 243
    static let rowH: CGFloat = 37
    static let lineH: CGFloat = 22             // Papierlinien-Raster
    /// Standardgröße = Fenster im Referenzfoto (1002×603); die 1×-Referenz von Ars Technica ist 736×443 (gleiche Proportionen, Faktor 1,36).
    static let mainDefault = NSSize(width: 1002, height: 603)
    static let singleDefault = NSSize(width: 360, height: 480)
    /// Mindestgrößen: Papier ≥ 250 pt breit, mindestens drei Listenzeilen.
    static func mainMin(folders: Bool) -> NSSize { NSSize(width: (folders ? sidebarW : 0) + listW + 250, height: 300) }
    static let singleMin = NSSize(width: 250, height: 180)
    static let corner: CGFloat = 5
}

func lucida(_ s: CGFloat, bold: Bool = false) -> NSFont { NSFont(name: bold ? "LucidaGrande-Bold" : "LucidaGrande", size: s) ?? .systemFont(ofSize: s, weight: bold ? .bold : .regular) }

enum Tex {
    static func load(_ n: String) -> NSImage? {
        guard let u = Bundle.main.url(forResource: n, withExtension: "png"), let i = NSImage(contentsOf: u) else { return nil }
        i.size = NSSize(width: 256, height: 256); return i      // 512 px = 256 pt → scharf bei 1× und 2×
    }
    static let leather = load("leather"), paper = load("paper")

    /// Kachel mit Mischmodus über einen Bereich legen (Raster an der Ansicht verankert, daher scrollt die Struktur mit).
    static func overlay(_ img: NSImage?, in r: NSRect, alpha: CGFloat) {
        guard let img else { return }
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: r).addClip()
        let t: CGFloat = 256
        var y = floor(r.minY / t) * t
        while y < r.maxY {
            var x = floor(r.minX / t) * t
            while x < r.maxX { img.draw(in: NSRect(x: x, y: y, width: t, height: t), from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil); x += t }
            y += t
        }
    }
}

/// Papierfarbe oben → unten (Messung: 238/232/175 → 240/235/182)
func paperTone(_ t: CGFloat) -> NSColor { NSColor(238 + 2 * t, 232 + 3 * t, 175 + 7 * t) }
let paperColor = NSColor(238, 232, 175), paperLine = NSColor(209, 204, 149)

enum Draw {
    /// Zeilenprofil des Lederkopfs (Referenz, Zeilenmittel; Zeile 0…21, Zeile 22 = dunkle Unterkante)
    private static let leatherRows: [(CGFloat, CGFloat, CGFloat)] = [(151,117,101),(167,125,112),(152,108,96),(144,100,90),(138,96,85),(128,94,81),(124,92,78),(120,91,76),(118,89,73),(116,86,71),(114,84,70),(111,81,70),(109,78,67),(106,76,65),(104,74,63),(100,73,62),(99,72,62),(98,68,60),(97,67,60),(94,67,61),(94,74,66),(81,67,58),(56,48,32)]
    static func leather(_ r: NSRect, active: Bool) {
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: r).addClip()
        for (i, c) in leatherRows.enumerated() { NSColor(c.0, c.1, c.2).setFill(); NSRect(x: r.minX, y: r.minY + CGFloat(i), width: r.width, height: 1).fill() }
        if r.height > 23 { let c = leatherRows[leatherRows.count - 1]; NSColor(c.0, c.1, c.2).setFill(); NSRect(x: r.minX, y: r.minY + 23, width: r.width, height: r.height - 23).fill() }
        NSGraphicsContext.restoreGraphicsState()
        Tex.overlay(Tex.leather, in: r, alpha: 1)
        if !active { NSColor(170, 160, 155, 0.22).setFill(); r.fill(using: .sourceOver) }
    }

    /// Schlagschatten des Lederkopfs auf Seitenleiste und Liste (Messung: α 0,57 / 0,23 / 0,19 / 0,10 / 0,06 / 0,03 ab Zeile 23)
    static func titleShadow(width w: CGFloat) {
        for (i, a) in [0.57, 0.23, 0.19, 0.10, 0.06, 0.03].enumerated() { NSColor(0, 0, 0, a).setFill(); NSRect(x: 0, y: M.titleH + CGFloat(i), width: w, height: 1).fill() }
    }

    /// Papier mit gerissener Oberkante (Zeilenprofil der Referenz: Zeile 23 Übergang, 24–25 Creme, 26–30 Rissband, 31–34 zurück zum Papier).
    static func paperTop(width w: CGFloat, y: CGFloat) {
        let prof: [(CGFloat, CGFloat, CGFloat)] = [(123,116,91),(184,177,145),(204,196,162),(184,176,140),(168,160,122),(187,180,140),(177,170,127),(177,172,124),(205,198,144),(224,217,160),(232,226,169),(237,231,174)]
        for (i, c) in prof.enumerated() { NSColor(c.0, c.1, c.2).setFill(); NSRect(x: 0, y: y + CGFloat(i), width: w, height: 1).fill() }
        var seed: UInt32 = 987
        func r() -> CGFloat { seed = seed &* 1664525 &+ 1013904223; return CGFloat(seed >> 16) / 65535 }
        // zwei durchgehende, leicht wellige Risslinien (Referenz: dunkles Olive, vereinzelt unterbrochen)
        for (row, col, w0) in [(4.2, NSColor(120, 112, 78, 0.8), 1.3), (6.8, NSColor(128, 119, 84, 0.65), 1.1), (2.4, NSColor(215, 209, 172, 0.9), 1.0)] as [(CGFloat, NSColor, CGFloat)] {
            let p = NSBezierPath(); var off: CGFloat = 0, x: CGFloat = 0; p.move(to: NSPoint(x: 0, y: y + row))
            while x < w { off = max(-1.4, min(1.4, off + (r() - 0.5) * 1.1)); x += 3; p.line(to: NSPoint(x: x, y: y + row + off)) }
            col.setStroke(); p.lineWidth = w0; p.lineJoinStyle = .round; p.stroke()
        }
    }

    static func capsule(_ r: NSRect, fill: NSGradient, border: NSColor, radius: CGFloat) {
        let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.draw(in: p, angle: 90); border.setStroke(); p.lineWidth = 1; p.stroke()
    }
}

// MARK: Titelleiste mit Ampel

final class TitleBar: NSView {
    override var isFlipped: Bool { true }
    var title = "" { didSet { needsDisplay = true } }
    var active = true { didSet { needsDisplay = true } }
    var onZoom: () -> Void = {}, onFull: () -> Void = {}
    var fullscreen = false { didSet { needsDisplay = true } }
    private var fullRect: NSRect { NSRect(x: bounds.width - 26, y: 0, width: 24, height: M.titleH) }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if fullRect.contains(p) { onFull() }
        else if e.clickCount == 2, !fullscreen { onZoom() }
        else if !fullscreen { window?.performDrag(with: e) }
    }

    override func draw(_ dirty: NSRect) {
        let b = bounds
        Draw.leather(NSRect(x: 0, y: 0, width: b.width, height: M.titleH), active: active)
                // Titel
        let sh = NSShadow(); sh.shadowColor = NSColor(40, 25, 20, 0.85); sh.shadowOffset = NSSize(width: 0, height: -1); sh.shadowBlurRadius = 0
        let ps = NSMutableParagraphStyle(); ps.alignment = .center; ps.lineBreakMode = .byTruncatingTail
        let att: [NSAttributedString.Key: Any] = [.font: lucida(13), .foregroundColor: active ? NSColor(243, 229, 221) : NSColor(210, 195, 188), .paragraphStyle: ps, .shadow: sh]
        let tr = NSRect(x: 72, y: 4, width: b.width - 144, height: 16)
        (title as NSString).draw(in: tr, withAttributes: att)
        drawFull(NSRect(x: b.width - 23, y: 5, width: 12, height: 12))
    }

    /// Vollbild-Symbol: zwei diagonale Pfeile (↗ ↙ bzw. nach innen im Vollbild)
    private func drawFull(_ r: NSRect) {
        let c = active ? NSColor(52, 32, 26) : NSColor(110, 88, 80)
        let sh = NSShadow(); sh.shadowColor = NSColor(255, 230, 220, 0.25); sh.shadowOffset = NSSize(width: 0, height: -1); sh.shadowBlurRadius = 0
        NSGraphicsContext.saveGraphicsState(); sh.set(); c.setStroke(); c.setFill()
        func arrow(_ tip: NSPoint, _ tail: NSPoint, _ sx: CGFloat, _ sy: CGFloat) {
            let l = NSBezierPath(); l.lineWidth = 1.5; l.move(to: tail); l.line(to: tip); l.stroke()
            let h = NSBezierPath(); h.move(to: tip); h.line(to: NSPoint(x: tip.x - 5.5 * sx, y: tip.y)); h.line(to: NSPoint(x: tip.x, y: tip.y - 5.5 * sy)); h.close(); h.fill()
        }
        let tl = NSPoint(x: r.minX, y: r.minY), br = NSPoint(x: r.maxX, y: r.maxY), tr = NSPoint(x: r.maxX, y: r.minY), bl = NSPoint(x: r.minX, y: r.maxY)
        if fullscreen { arrow(NSPoint(x: r.midX + 1, y: r.midY - 1), tr, -1, 1); arrow(NSPoint(x: r.midX - 1, y: r.midY + 1), bl, 1, -1) }
        else { arrow(tr, NSPoint(x: r.midX, y: r.midY), 1, -1); arrow(bl, NSPoint(x: r.midX, y: r.midY), -1, 1); _ = (tl, br) }
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: Fenster

final class MLWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var userFrame: NSRect?          // Rückkehr nach Zoom / Vollbild
    var inFullscreen = false
}

/// Wurzelansicht; die Fensterform (Ecken) und die Ampel kommen vom System.
class ChromeView: NSView {
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
}
