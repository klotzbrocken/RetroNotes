import AppKit

let noteDragType = NSPasteboard.PasteboardType("de.maik.mlnotes.noteid")

// MARK: Seitenleiste (Konten / Ordner)

final class SidebarView: NSView {
    override var isFlipped: Bool { true }
    enum Item { case all, header(String, String), folder(NFolder) }   // header: (Kontoname, Konto-ID)
    var items: [Item] = [] { didSet { needsDisplay = true } }
    var sel: Sel = .all { didSet { needsDisplay = true } }
    var onSelect: (Sel) -> Void = { _ in }
    var onDrop: (String, String) -> Void = { _, _ in }          // noteID, folderID
    var onNewFolder: (String) -> Void = { _ in }, onRename: (NFolder) -> Void = { _ in }, onDelete: (NFolder) -> Void = { _ in }
    var active = true { didSet { needsDisplay = true } }
    private var dropTarget: String?

    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([noteDragType]) }
    required init?(coder: NSCoder) { fatalError() }

    /// Zeilenmitte in Fensterkoordinaten (gemessen: Alle 48, Konto 74, Ordner 93, Konto 120, Ordner 138)
    private func rows() -> [(Item, CGFloat)] {
        var y: CGFloat = 48, out: [(Item, CGFloat)] = []
        for (i, it) in items.enumerated() {
            if i > 0 { switch it { case .header: y += 27; case .folder: y += 19; case .all: break } }
            if case .header = it, i == 1 { y = 74 }
            out.append((it, y))
        }
        return out
    }
    override func draw(_ r: NSRect) {
        NSColor(232, 232, 232).setFill(); bounds.fill()
        Draw.titleShadow(width: bounds.width)
        NSColor(213, 213, 211).setFill(); NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        for (it, y) in rows() {
            switch it {
            case .all: label(L("All Notes", "Alle Notizen"), x: 16, y: y, color: sel == .all ? red : .black, bold: false)
            case .header(let n, _): label(n, x: 16, y: y, color: NSColor(150, 150, 150), bold: true)
            case .folder(let f):
                if dropTarget == f.id { NSColor(0, 0, 0, 0.08).setFill(); NSRect(x: 0, y: y - 10, width: bounds.width - 1, height: 20).fill() }
                label(f.name, x: 22, y: y, color: sel == .folder(f.id) ? red : .black, bold: false)
            }
        }
    }
    private let red = NSColor(196, 82, 58)
    private func label(_ t: String, x: CGFloat, y: CGFloat, color: NSColor, bold: Bool) {
        (t as NSString).draw(in: NSRect(x: x, y: y - 8, width: bounds.width - x - 6, height: 17),
            withAttributes: [.font: lucida(bold ? 11 : 12, bold: bold), .foregroundColor: color, .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail; return p }()])
    }
    private func item(at p: NSPoint) -> Item? { rows().first { abs($0.1 - p.y) <= 10 }?.0 }
    override func mouseDown(with e: NSEvent) {
        switch item(at: convert(e.locationInWindow, from: nil)) { case .all: onSelect(.all); case .folder(let f): onSelect(.folder(f.id)); default: break }
    }
    override func menu(for e: NSEvent) -> NSMenu? {
        let m = NSMenu()
        func add(_ t: String, _ a: @escaping () -> Void) { let i = ClosureItem(title: t, action: a); m.addItem(i) }
        switch item(at: convert(e.locationInWindow, from: nil)) {
        case .folder(let f): add(L("New Folder", "Neuer Ordner")) { self.onNewFolder(f.account) }; add(L("Rename Folder…", "Ordner umbenennen …")) { self.onRename(f) }; add(L("Delete Folder…", "Ordner löschen …")) { self.onDelete(f) }
        case .header(_, let acc): add(L("New Folder", "Neuer Ordner")) { self.onNewFolder(acc) }
        default: return nil
        }
        return m
    }
    // Drag-and-drop: Notiz auf Ordner (ORD-02)
    private func folderID(_ i: NSDraggingInfo) -> String? { if case .folder(let f)? = item(at: convert(i.draggingLocation, from: nil)) { return f.id }; return nil }
    override func draggingEntered(_ i: NSDraggingInfo) -> NSDragOperation { draggingUpdated(i) }
    override func draggingUpdated(_ i: NSDraggingInfo) -> NSDragOperation { dropTarget = folderID(i); needsDisplay = true; return dropTarget == nil ? [] : .move }
    override func draggingExited(_ i: NSDraggingInfo?) { dropTarget = nil; needsDisplay = true }
    override func performDragOperation(_ i: NSDraggingInfo) -> Bool {
        defer { dropTarget = nil; needsDisplay = true }
        guard let f = folderID(i), let id = i.draggingPasteboard.string(forType: noteDragType) else { return false }
        onDrop(id, f); return true
    }
}

final class ClosureItem: NSMenuItem {
    private let fn: () -> Void
    init(title: String, key: String = "", action: @escaping () -> Void) { fn = action; super.init(title: title, action: #selector(run), keyEquivalent: key); target = self }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { fn() }
}

// MARK: Liste

final class ListTable: NSTableView {
    override var isFlipped: Bool { true }
    override func drawBackground(inClipRect r: NSRect) {
        NSColor(240, 238, 237).setFill(); r.fill()
        NSColor(187, 185, 183).setStroke()
        let p = NSBezierPath(); p.lineWidth = 1; p.setLineDash([1, 1], count: 2, phase: 0)
        var y = CGFloat(Int(r.minY / M.rowH)) * M.rowH + M.rowH
        while y <= r.maxY + M.rowH { p.move(to: NSPoint(x: r.minX, y: y - 0.5)); p.line(to: NSPoint(x: r.maxX, y: y - 0.5)); y += M.rowH }
        p.stroke()
    }
    override func menu(for e: NSEvent) -> NSMenu? {
        let r = row(at: convert(e.locationInWindow, from: nil)); if r >= 0, !selectedRowIndexes.contains(r) { selectRowIndexes([r], byExtendingSelection: false) }
        return r >= 0 ? super.menu(for: e) : nil
    }
}
final class RowView: NSTableRowView {
    override func drawSelection(in r: NSRect) { NSColor(216, 215, 214).setFill(); r.fill() }
    override var isEmphasized: Bool { get { false } set {} }
}
final class NoteCell: NSView {
    override var isFlipped: Bool { true }
    var title = "", date = ""
    override func draw(_ r: NSRect) {
        let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 16, y: 0, width: bounds.width - 22, height: 17),
            withAttributes: [.font: NSFont(name: "Noteworthy-Bold", size: 13) ?? lucida(13), .foregroundColor: NSColor(20, 20, 20), .paragraphStyle: ps])
        (date as NSString).draw(in: NSRect(x: 16, y: 19, width: bounds.width - 22, height: 14),
            withAttributes: [.font: lucida(11), .foregroundColor: NSColor(150, 150, 150), .paragraphStyle: ps])
    }
}

/// Suchfeld (Pille): Lupe links, Löschen-Kreuz rechts.
final class SearchBox: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    let field = NSTextField()
    var onChange: (String) -> Void = { _ in }
    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none; field.font = lucida(13); field.delegate = self
        field.cell?.sendsActionOnEndEditing = false; field.usesSingleLineMode = true
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { field.frame = NSRect(x: 27, y: 3, width: bounds.width - 27 - 24, height: 16) }
    func controlTextDidChange(_ n: Notification) { needsDisplay = true; onChange(field.stringValue) }
    func clear() { field.stringValue = ""; needsDisplay = true; onChange("") }
    override func mouseDown(with e: NSEvent) {
        if !field.stringValue.isEmpty, convert(e.locationInWindow, from: nil).x > bounds.width - 24 { clear() } else { window?.makeFirstResponder(field) }
    }
    override func draw(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        NSColor(241, 239, 238).setFill(); p.fill()
        NSGraphicsContext.saveGraphicsState(); p.addClip(); NSColor(244, 243, 241).setFill(); NSRect(x: 0, y: 2, width: bounds.width, height: 3).fill(); NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(156, 154, 153), ending: NSColor(186, 184, 182))?.draw(in: { let o = NSBezierPath(roundedRect: bounds, xRadius: 11.5, yRadius: 11.5); o.append(NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10.5, yRadius: 10.5).reversed); o.windingRule = .evenOdd; return o }(), angle: 90)
        NSColor(66, 74, 78).setStroke()
        let c = NSBezierPath(ovalIn: NSRect(x: 9.5, y: 5, width: 9, height: 9)); c.lineWidth = 1.9; c.stroke()
        let h = NSBezierPath(); h.move(to: NSPoint(x: 17, y: 13.5)); h.line(to: NSPoint(x: 21.5, y: 18)); h.lineWidth = 2.8; h.lineCapStyle = .round; h.stroke()
        if !field.stringValue.isEmpty {
            NSColor(150, 150, 150).setFill(); NSBezierPath(ovalIn: NSRect(x: bounds.width - 20, y: 5, width: 12, height: 12)).fill()
            NSColor.white.setStroke(); let x = NSBezierPath(); x.lineWidth = 1.4
            x.move(to: NSPoint(x: bounds.width - 16.5, y: 8.5)); x.line(to: NSPoint(x: bounds.width - 11.5, y: 13.5)); x.move(to: NSPoint(x: bounds.width - 11.5, y: 8.5)); x.line(to: NSPoint(x: bounds.width - 16.5, y: 13.5)); x.stroke()
        }
    }
}

/// Knopf im Stil von 10.8 (heller Verlauf, 1-px-Rahmen); Symbol per Closure.
final class BezelButton: NSView {
    override var isFlipped: Bool { true }
    var icon: (NSRect, Bool) -> Void = { _, _ in }
    var onClick: () -> Void = {}
    var selected = false { didSet { needsDisplay = true } }
    private var pressed = false
    var segment: Int? // 0 links, 1 rechts, nil allein
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { pressed = true; needsDisplay = true
        while let n = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]), n.type == .leftMouseDragged { _ = n }
        let inside = bounds.contains(convert(window!.mouseLocationOutsideOfEventStream, from: nil)); pressed = false; needsDisplay = true; if inside { onClick() } }
    override func draw(_ r: NSRect) {
        let dark = pressed || selected
        let g = dark ? NSGradient(starting: NSColor(206, 206, 206), ending: NSColor(226, 226, 226))! : NSGradient(colors: [NSColor(254, 253, 252), NSColor(247, 246, 245), NSColor(243, 241, 241), NSColor(240, 239, 239)], atLocations: [0, 0.35, 0.7, 1], colorSpace: .sRGB)!
        var rr = bounds
        if let s = segment { rr = NSRect(x: s == 0 ? 0 : -8, y: 0, width: bounds.width + 8, height: bounds.height) }
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: bounds).addClip()
        Draw.capsule(rr, fill: g, border: NSColor(182, 180, 179), radius: 4)
        NSGraphicsContext.restoreGraphicsState()
        if segment == 1 { NSColor(182, 180, 179).setFill(); NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill() }
        icon(bounds, dark)
    }
}

final class ListColumn: NSView {
    override var isFlipped: Bool { true }
    let search = SearchBox(frame: .zero), scroll = NSScrollView(), table = ListTable()
    let plus = BezelButton(), seg0 = BezelButton(), seg1 = BezelButton()
    override init(frame: NSRect) {
        super.init(frame: frame)
        let col = NSTableColumn(identifier: .init("n")); col.resizingMask = .autoresizingMask
        table.addTableColumn(col); table.headerView = nil; table.rowHeight = M.rowH; table.intercellSpacing = .zero
        table.backgroundColor = .clear; table.style = .plain; table.selectionHighlightStyle = .regular; table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle; table.usesAutomaticRowHeights = false
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.autohidesScrollers = true
        [scroll, search, plus, seg0, seg1].forEach(addSubview)
        plus.icon = { r, _ in
            NSColor(90, 90, 90).setFill(); NSRect(x: r.midX - 5, y: r.midY - 0.75, width: 10, height: 1.6).fill(); NSRect(x: r.midX - 0.8, y: r.midY - 5, width: 1.6, height: 10).fill() }
        seg0.segment = 0; seg1.segment = 1
        // Symbole: Spalten-Ansicht (links: Ordner+Liste+Papier) / Liste+Papier (rechts)
        seg0.icon = { r, _ in Self.viewIcon(r, folders: true) }; seg1.icon = { r, _ in Self.viewIcon(r, folders: false) }
    }
    required init?(coder: NSCoder) { fatalError() }
    static func viewIcon(_ r: NSRect, folders: Bool) {
        NSColor(100, 100, 100).setFill(); NSColor(100, 100, 100).setStroke()
        let rows = folders ? 4 : 3, x0 = r.midX - 9, y0 = r.midY - CGFloat(rows) * 1.6 - 0.5
        for i in 0..<rows { NSRect(x: x0, y: y0 + CGFloat(i) * 3.2, width: folders ? 9 : 10, height: 1.3).fill() }
        let b = NSBezierPath(rect: NSRect(x: x0 + 11.5, y: r.midY - 4.5, width: 6, height: 9)); b.lineWidth = 1.2; b.stroke()
    }
    override func layout() {
        let w = bounds.width, h = bounds.height
        search.frame = NSRect(x: 13, y: 35, width: w - 27, height: 22)
        scroll.frame = NSRect(x: 14, y: 70, width: w - 29, height: h - 70 - 39)
        plus.frame = NSRect(x: 13, y: h - 30, width: 28, height: 22)
        seg0.frame = NSRect(x: w - 14 - 62, y: h - 30, width: 31, height: 22); seg1.frame = NSRect(x: w - 14 - 31, y: h - 30, width: 31, height: 22)
    }
    override func draw(_ r: NSRect) {
        NSColor(240, 238, 237).setFill(); bounds.fill()
        Draw.titleShadow(width: bounds.width)
        NSColor(186, 184, 182).setStroke(); let b = NSBezierPath(rect: NSRect(x: 13.5, y: 69.5, width: bounds.width - 28, height: bounds.height - 69 - 39)); b.lineWidth = 1; b.stroke()
        // Schattenwurf des Papiers auf die Liste
        NSGradient(starting: NSColor(0, 0, 0, 0), ending: NSColor(0, 0, 0, 0.17))?.draw(in: NSRect(x: bounds.width - 6, y: M.titleH, width: 6, height: bounds.height), angle: 0)
    }
}

// MARK: Papier / Editor

final class PaperText: NSTextView, NSLayoutManagerDelegate {
    /// Alle Zeilen rasten auf das 22-pt-Linienraster (größere Schrift belegt eine Linie mehr, wenn sie nicht passt).
    func layoutManager(_ lm: NSLayoutManager, shouldSetLineFragmentRect lf: UnsafeMutablePointer<NSRect>, lineFragmentUsedRect u: UnsafeMutablePointer<NSRect>, baselineOffset b: UnsafeMutablePointer<CGFloat>, in tc: NSTextContainer, forGlyphRange g: NSRange) -> Bool {
        let n = max(1, ceil((lf.pointee.height - 8) / M.lineH)), h = n * M.lineH
        lf.pointee.size.height = h; u.pointee.size.height = h; b.pointee = h - 1.5
        return true
    }
    var topInset: CGFloat { textContainerInset.height }
    var onImageDrop: ((String) -> Void)?

    // MARK: Bilder per Drag-and-drop / Einsetzen (Anhänge)
    /// Notes nimmt über Scripting nur Bilder an (als Data-URI im Body); andere Dateien werden mit Hinweis abgelehnt.
    private func imageItems(_ pb: NSPasteboard) -> (images: [(Data, String)], rejected: [String])? {
        var imgs: [(Data, String)] = [], rej: [String] = []
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        for u in urls {
            let isImg = (try? u.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) ?? false
            if isImg, let d = try? Data(contentsOf: u, options: .mappedIfSafe) { imgs.append((d, u.lastPathComponent)) } else { rej.append(u.lastPathComponent) }
        }
        if urls.isEmpty, let d = pb.data(forType: .png) ?? pb.data(forType: .tiff) { imgs.append((d, "")) }
        return imgs.isEmpty && rej.isEmpty ? nil : (imgs, rej)
    }
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { super.acceptableDragTypes + [.fileURL, .png, .tiff] }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { imageItems(s.draggingPasteboard) != nil && isEditable ? .copy : super.draggingEntered(s) }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation { imageItems(s.draggingPasteboard) != nil && isEditable ? .copy : super.draggingUpdated(s) }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard let it = imageItems(s.draggingPasteboard) else { return super.performDragOperation(s) }
        let idx = characterIndexForInsertion(at: convert(s.draggingLocation, from: nil))
        return insert(it, at: idx)
    }
    override func paste(_ sender: Any?) {
        if let it = imageItems(.general), (NSPasteboard.general.string(forType: .string) ?? "").isEmpty { _ = insert(it, at: selectedRange().location) } else { super.paste(sender) }
    }
    func insert(_ it: (images: [(Data, String)], rejected: [String]), at idx: Int) -> Bool {
        func warn(_ t: String, _ i: String) { let a = NSAlert(); a.messageText = t; a.informativeText = i; a.runModal() }
        guard isEditable else { warn(L("This note is read-only.", "Diese Notiz ist schreibgeschützt."), L("Notes with attachments or tables cannot be edited here without losing content.", "Notizen mit Anhängen oder Tabellen lassen sich hier nicht ohne Inhaltsverlust bearbeiten.")); return false }
        if !it.rejected.isEmpty { warn(L("Only images can be added.", "Nur Bilder können eingefügt werden."), L("The Notes app does not accept other files via its scripting interface: ", "Die System-App Notizen nimmt andere Dateien über ihre Scripting-Schnittstelle nicht an: ") + it.rejected.joined(separator: ", ")) }
        var at = min(idx, string.count), done = false
        for (d, _) in it.images {
            guard let rep = NSBitmapImageRep(data: d), rep.pixelsWide * rep.pixelsHigh <= 20_000_000, d.count <= 50 << 20 else { warn(L("Image too large.", "Bild zu groß."), L("Limit: 20 megapixels.", "Grenze: 20 Megapixel.")); continue }
            let att = NSTextAttachment(data: d, ofType: (d.starts(with: [0xFF, 0xD8]) ? "public.jpeg" : d.starts(with: [0x89, 0x50]) ? "public.png" : "public.tiff"))
            att.image = NSImage(data: d); RT.fit(att)
            let ns = NSMutableAttributedString(string: (at > 0 && (string as NSString).character(at: at - 1) != 10) ? "\n" : "", attributes: [.font: DefaultFont.current.font()])   // Bild immer in eigener Zeile
            ns.append(NSAttributedString(attachment: att))
            ns.addAttributes([.foregroundColor: RT.ink], range: NSRange(location: 0, length: ns.length))
            ns.append(NSAttributedString(string: "\n", attributes: [.font: DefaultFont.current.font()]))
            guard shouldChangeText(in: NSRange(location: at, length: 0), replacementString: ns.string) else { continue }
            textStorage?.replaceCharacters(in: NSRange(location: at, length: 0), with: ns)
            at += ns.length; done = true; didChangeText()
        }
        if done { setSelectedRange(NSRange(location: at, length: 0)) }
        return done
    }
    override func drawBackground(in r: NSRect) {
        let vis = enclosingScrollView?.contentView.bounds ?? bounds
        var gy = floor(r.minY)
        while gy < r.maxY { paperTone(min(max((gy - vis.minY + 35) / (vis.height + 89), 0), 1)).setFill(); NSRect(x: r.minX, y: gy, width: r.width, height: 1).fill(); gy += 1 }
        Tex.overlay(Tex.paper, in: r, alpha: 1)
        paperLine.setFill()
        var y = topInset + M.lineH - 1
        if y < r.minY { y += ceil((r.minY - y) / M.lineH) * M.lineH }
        while y < r.maxY { NSRect(x: r.minX, y: y, width: r.width, height: 1).fill(); y += M.lineH }
    }
    override var isOpaque: Bool { true }
}

final class PaperButton: NSView {
    override var isFlipped: Bool { true }
    var trash = true, onClick: () -> Void = {}
    private var pressed = false
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { pressed = true; needsDisplay = true
        while let n = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]), n.type == .leftMouseDragged { _ = n }
        let inside = bounds.contains(convert(window!.mouseLocationOutsideOfEventStream, from: nil)); pressed = false; needsDisplay = true; if inside { onClick() } }
    override func draw(_ r: NSRect) {
        (pressed ? NSColor(130, 40, 25) : NSColor(190, 78, 54)).setStroke()
        let ox = bounds.midX - 8, oy = bounds.midY - 8
        let p = NSBezierPath(); p.lineWidth = 1.9; p.lineCapStyle = .round; p.lineJoinStyle = .round
        func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x, y: oy + y) }
        if trash {
            p.move(to: P(1, 3.5)); p.line(to: P(15, 3.5)); p.move(to: P(5.5, 3.5)); p.line(to: P(5.5, 1)); p.line(to: P(10.5, 1)); p.line(to: P(10.5, 3.5))
            p.move(to: P(2.8, 5.5)); p.line(to: P(3.8, 15)); p.line(to: P(12.2, 15)); p.line(to: P(13.2, 5.5))
            p.move(to: P(6, 7)); p.line(to: P(6, 13)); p.move(to: P(8, 7)); p.line(to: P(8, 13)); p.move(to: P(10, 7)); p.line(to: P(10, 13))
        } else {
            p.move(to: P(6.5, 3.5)); p.line(to: P(2, 3.5)); p.line(to: P(2, 14.5)); p.line(to: P(13, 14.5)); p.line(to: P(13, 10))
            p.move(to: P(6, 10.5)); p.curve(to: P(14.5, 4), controlPoint1: P(6.5, 6), controlPoint2: P(10.5, 4.6))
            p.move(to: P(11.4, 1)); p.line(to: P(15, 4)); p.line(to: P(11.8, 7.2))
        }
        p.stroke()
    }
}

final class PaperHeader: NSView {
    override var isFlipped: Bool { true }
    var date = "", note = ""
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override func draw(_ r: NSRect) {
        let ps = NSMutableParagraphStyle(); ps.alignment = .right
        for (i, c) in [(219,212,171),(164,157,119),(216,212,168),(158,157,123)].enumerated() { NSColor(CGFloat(c.0), CGFloat(c.1), CGFloat(c.2)).setFill(); NSRect(x: 0, y: bounds.height - 4 + CGFloat(i), width: bounds.width, height: 1).fill() }   // Seitenstapel unten
        NSColor(169, 163, 142).setFill(); NSRect(x: 0, y: M.titleH, width: 1, height: bounds.height).fill()
        (date as NSString).draw(in: NSRect(x: 0, y: 40, width: bounds.width - 10, height: 15), withAttributes: [.font: lucida(11), .foregroundColor: NSColor(207, 118, 104), .paragraphStyle: ps])
        let pl = NSMutableParagraphStyle(); pl.lineBreakMode = .byTruncatingTail
        (note as NSString).draw(in: NSRect(x: 12, y: 40, width: bounds.width - 140, height: 15), withAttributes: [.font: lucida(10), .foregroundColor: NSColor(150, 110, 70), .paragraphStyle: pl])
    }
}

final class PaperView: NSView, NSTextViewDelegate {
    override var isFlipped: Bool { true }
    static var all = NSHashTable<PaperView>.weakObjects()
    let store: NotesStore
    let scroll = NSScrollView(), text: PaperText
    let header = PaperHeader(), trashBtn = PaperButton(), shareBtn = PaperButton()
    var onDelete: (String) -> Void = { _ in }
    var onTitle: (String) -> Void = { _ in }
    private(set) var noteID: String?
    private var dirty = false, timer: Timer?, token = 0, readOnly: String?
    var fullscreen = false { didSet { needsDisplay = true; needsLayout = true } }

    init(store: NotesStore) {
        self.store = store
        let ts = NSTextStorage(), lm = NSLayoutManager(), tc = NSTextContainer(containerSize: NSSize(width: 100, height: 1e7))
        ts.addLayoutManager(lm); lm.addTextContainer(tc); tc.widthTracksTextView = true; tc.lineFragmentPadding = 0
        text = PaperText(frame: NSRect(x: 0, y: 0, width: 100, height: 100), textContainer: tc)
        super.init(frame: .zero)
        lm.delegate = text
        text.isRichText = true; text.allowsUndo = true; text.usesFontPanel = true; text.importsGraphics = false
        text.isAutomaticLinkDetectionEnabled = true; text.isAutomaticSpellingCorrectionEnabled = false
        text.drawsBackground = false; text.delegate = self; text.textContainerInset = NSSize(width: 23, height: 32)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.maxSize = NSSize(width: 1e7, height: 1e7); text.registerForDraggedTypes(text.acceptableDragTypes)
        text.linkTextAttributes = [.foregroundColor: NSColor(40, 70, 170), .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.autohidesScrollers = true
        addSubview(scroll); addSubview(header); addSubview(trashBtn); addSubview(shareBtn)
        trashBtn.trash = true; shareBtn.trash = false
        trashBtn.onClick = { [weak self] in if let id = self?.noteID { self?.onDelete(id) } }
        shareBtn.onClick = { [weak self] in self?.share() }
        Self.all.add(self)
        NotificationCenter.default.addObserver(forName: NotesStore.noteUpdated, object: nil, queue: .main) { [weak self] n in
            guard let s = self, n.object as AnyObject? !== s, n.userInfo?["id"] as? String == s.noteID else { return }
            s.reloadFromStore()
        }
        NotificationCenter.default.addObserver(forName: NotesStore.listChanged, object: nil, queue: .main) { [weak self] _ in self?.needsDisplay = true }
        applyDefaults()
    }
    required init?(coder: NSCoder) { fatalError() }

    func applyDefaults() {
        let f = DefaultFont.current
        text.font = f.font(); text.textColor = RT.ink
        text.typingAttributes = [.font: f.font(), .foregroundColor: RT.ink]
        text.insertionPointColor = NSColor(40, 30, 20)
    }

    // MARK: Anzeige
    func show(_ id: String?) {
        flush()
        noteID = id; token += 1; let t = token
        readOnly = nil
        guard let id else { setContent(NSAttributedString()); text.isEditable = false; needsDisplay = true; return }
        text.isEditable = false
        store.body(id) { [weak self] b in
            guard let s = self, t == s.token else { return }
            s.readOnly = b.readOnly
            s.setContent(RT.attributed(b.html)); s.text.isEditable = b.readOnly == nil
            s.needsDisplay = true
        }
        needsDisplay = true
    }
    private func setContent(_ a: NSAttributedString) {
        applyDefaults()
        text.textStorage?.setAttributedString(a)
        text.undoManager?.removeAllActions(); text.setSelectedRange(NSRange(location: 0, length: 0)); scroll.contentView.scroll(to: .zero)
        dirty = false
    }
    private func reloadFromStore() {
        guard let id = noteID, !dirty else { return }
        store.body(id) { [weak self] b in
            guard let s = self, s.noteID == id, !s.dirty else { return }
            let sel = s.text.selectedRange(); s.text.textStorage?.setAttributedString(RT.attributed(b.html))
            s.text.setSelectedRange(NSRange(location: min(sel.location, s.text.string.count), length: 0)); s.needsDisplay = true
        }
    }
    func focus() { window?.makeFirstResponder(text) }

    // MARK: Speichern (≤ 1 s nach Eingabepause, beim Wechsel, Schließen, Beenden)
    func textDidChange(_ n: Notification) {
        guard noteID != nil, readOnly == nil else { return }
        dirty = true; timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.flush() }
        if let id = noteID, let s = text.textStorage { onTitle(s.string.split(whereSeparator: \.isNewline).first.map(String.init) ?? "") ; _ = id }
    }
    func flush(sync: Bool = false) {
        timer?.invalidate(); timer = nil
        guard dirty, let id = noteID, let s = text.textStorage else { return }
        dirty = false
        store.save(id, html: RT.html(s), plain: s.string, sync: sync)
        NotificationCenter.default.post(name: NotesStore.noteUpdated, object: self, userInfo: ["id": id])
        needsDisplay = true
    }
    var isEmptyNote: Bool { text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Formatierung
    func toggle(_ t: NSFontTraitMask) {
        let fm = NSFontManager.shared, r = text.selectedRange()
        guard text.isEditable, let ts = text.textStorage else { return }
        func conv(_ f: NSFont, add: Bool) -> NSFont {
            let df = DefaultFont.current
            let tr = fm.traits(of: f)
            return df.font(size: f.pointSize, bold: t == .boldFontMask ? add : tr.contains(.boldFontMask), italic: t == .italicFontMask ? add : tr.contains(.italicFontMask))
        }
        if r.length == 0 {
            let f = (text.typingAttributes[.font] as? NSFont) ?? DefaultFont.current.font()
            text.typingAttributes[.font] = conv(f, add: !fm.traits(of: f).contains(t)); return
        }
        guard text.shouldChangeText(in: r, replacementString: nil) else { return }
        let add = !((ts.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont).map { fm.traits(of: $0).contains(t) } ?? false)
        ts.beginEditing(); ts.enumerateAttribute(.font, in: r) { v, rr, _ in ts.addAttribute(.font, value: conv((v as? NSFont) ?? DefaultFont.current.font(), add: add), range: rr) }; ts.endEditing()
        text.didChangeText()
    }
    func toggleAttr(_ key: NSAttributedString.Key) {
        guard text.isEditable, let ts = text.textStorage else { return }
        let r = text.selectedRange(); guard r.length > 0, text.shouldChangeText(in: r, replacementString: nil) else { return }
        let on = (ts.attribute(key, at: r.location, effectiveRange: nil) as? Int ?? 0) != 0
        if on { ts.removeAttribute(key, range: r) } else { ts.addAttribute(key, value: 1, range: r) }
        text.didChangeText()
    }
    func share() {
        let s = NSSharingServicePicker(items: [text.attributedString().string])
        s.show(relativeTo: shareBtn.bounds, of: shareBtn, preferredEdge: .minY)
    }

    // MARK: Layout & Zeichnen
    override func layout() {
        let w = bounds.width, h = bounds.height
        let top: CGFloat = 35      // unter der gerissenen Kante
        scroll.frame = NSRect(x: 0, y: top, width: w, height: h - top - 54)    // Fußbereich (Symbole) ohne Linien
        text.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        RT.maxImageWidth = max(80, w - 46 - 14)
        text.textContainerInset = NSSize(width: 23, height: 59 - top)    // erste Linie bei y = 80 (Messung)
        header.frame = bounds
        trashBtn.frame = NSRect(x: w / 2 - 23 - 12, y: h - 33, width: 24, height: 24)
        shareBtn.frame = NSRect(x: w / 2 + 23 - 12, y: h - 33, width: 24, height: 24)
    }
    override func draw(_ r: NSRect) {
        var yy: CGFloat = 0; while yy < bounds.height { paperTone(yy / bounds.height).setFill(); NSRect(x: 0, y: yy, width: bounds.width, height: 1).fill(); yy += 1 }
        Draw.paperTop(width: bounds.width, y: M.titleH)
        // linke Papierkante
        var line = ""
        if let id = noteID, let n = store.note(id) { let f = DateFormatter(); f.dateFormat = L("MMM d, h:mm a", "d. MMM, HH:mm"); line = f.string(from: n.modified) }
        header.date = line; header.note = readOnly ?? ""; header.needsDisplay = true
    }
}
