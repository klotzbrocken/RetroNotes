import AppKit

/// Lederlasche unten links im Vollbild (B2): öffnet/schließt die Ordner-/Notizliste.
final class LeatherTab: NSView {
    override var isFlipped: Bool { true }
    var onClick: () -> Void = {}
    override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    override func mouseDown(with e: NSEvent) { onClick() }
    override func draw(_ r: NSRect) {
        let p = NSBezierPath(); let b = bounds
        p.move(to: NSPoint(x: 0, y: b.maxY)); p.line(to: NSPoint(x: 0, y: 0)); p.line(to: NSPoint(x: b.maxX - 22, y: 0))
        p.curve(to: NSPoint(x: b.maxX, y: 22), controlPoint1: NSPoint(x: b.maxX - 8, y: 0), controlPoint2: NSPoint(x: b.maxX, y: 10)); p.line(to: NSPoint(x: b.maxX, y: b.maxY)); p.close()
        NSGraphicsContext.saveGraphicsState(); p.addClip()
        Draw.leather(b, active: true); NSColor(0, 0, 0, 0.12).setFill(); b.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(20, 12, 10, 0.6).setStroke(); p.lineWidth = 1; p.stroke()
        let sh = NSShadow(); sh.shadowColor = NSColor(30, 18, 14, 0.85); sh.shadowOffset = NSSize(width: 0, height: -1); sh.shadowBlurRadius = 0
        (L("Notes", "Notizen") as NSString).draw(at: NSPoint(x: 18, y: 14), withAttributes: [.font: lucida(13), .foregroundColor: NSColor(243, 229, 221), .shadow: sh])
    }
}

final class RootView: ChromeView, NSTableViewDataSource, NSTableViewDelegate {
    let store: NotesStore, single: Bool
    let titleBar = TitleBar(), paper: PaperView
    let sidebar = SidebarView(), list = ListColumn(), tab = LeatherTab()
    var sel: Sel = .all { didSet { UserDefaults.standard.set(selKey, forKey: "sel") } }
    var showFolders = UserDefaults.standard.object(forKey: "showFolders") as? Bool ?? true { didSet { UserDefaults.standard.set(showFolders, forKey: "showFolders"); needsLayout = true; list.needsDisplay = true } }
    var query = ""
    var rows: [NNote] = []
    var fs = false { didSet { applyFS() } }
    var panelOpen = false { didSet { needsLayout = true } }
    var active = true { didSet { titleBar.active = active; sidebar.active = active; needsDisplay = true } }
    private var suppress = false, fresh: String?
    private(set) var noteID: String?
    var onOpenSingle: (String) -> Void = { _ in }, onDeleted: (String) -> Void = { _ in }, onFullscreen: () -> Void = {}
    var onClose: () -> Void = {}, onMini: () -> Void = {}, onZoom: () -> Void = {}
    var lastDeleted: (folder: String, html: String)?
    private var selKey: String { if case .folder(let f) = sel { return f }; return "all" }

    init(store: NotesStore, single: Bool, noteID: String? = nil) {
        self.store = store; self.single = single; paper = PaperView(store: store)
        super.init(frame: NSRect(origin: .zero, size: single ? M.singleDefault : M.mainDefault))
        [paper, sidebar, list, tab, titleBar].forEach(addSubview)     // Titelleiste zuoberst
        tab.isHidden = true
        titleBar.onZoom = { [weak self] in self?.onZoom() }; titleBar.onFull = { [weak self] in self?.onFullscreen() }
        tab.onClick = { [weak self] in self?.panelOpen.toggle() }
        paper.onDelete = { [weak self] id in self?.deleteNote(id) }
        paper.onTitle = { [weak self] t in self?.updateTitle(t) }
        if single {
            sidebar.isHidden = true; list.isHidden = true; self.noteID = noteID; paper.show(noteID); updateTitle(nil)
        } else {
            if store.demo { sel = .folder("f1") } else if let k = UserDefaults.standard.string(forKey: "sel"), k != "all" { sel = .folder(k) }
            list.table.dataSource = self; list.table.delegate = self
            list.table.target = self; list.table.doubleAction = #selector(dbl)
            list.search.onChange = { [weak self] q in self?.query = q; self?.refresh() }
            list.plus.onClick = { [weak self] in self?.newNote() }
            list.seg0.onClick = { [weak self] in self?.showFolders = true; self?.fixMin() }; list.seg1.onClick = { [weak self] in self?.showFolders = false; self?.fixMin() }
            sidebar.onSelect = { [weak self] s in self?.sel = s; self?.panelOpen = self?.fs == true ? true : false; self?.rebuildSidebar(); self?.refresh() }
            sidebar.onDrop = { [weak self] id, f in self?.store.move(id, to: f) }
            sidebar.onNewFolder = { [weak self] acc in self?.promptFolder(account: acc) }
            sidebar.onRename = { [weak self] f in self?.promptRename(f) }
            sidebar.onDelete = { [weak self] f in self?.confirmDelete(f) }
            list.table.menu = noteMenu()
        }
        NotificationCenter.default.addObserver(forName: NotesStore.listChanged, object: store, queue: .main) { [weak self] _ in self?.storeChanged() }
        storeChanged()
    }
    required init?(coder: NSCoder) { fatalError() }

    func fixMin() { (window as? MLWindow).map { w in
        let m = M.mainMin(folders: showFolders); w.minSize = m
        if w.frame.width < m.width || w.frame.height < m.height { var f = w.frame; f.size.width = max(f.width, m.width); f.size.height = max(f.height, m.height); w.setFrame(f, display: true, animate: true) }
    } }

    // MARK: Daten → Ansicht
    func storeChanged() {
        if single { updateTitle(nil); needsDisplay = true; return }
        rebuildSidebar(); refresh()
        if let e = store.error, window != nil, !errorShown { errorShown = true; let a = NSAlert(); a.messageText = e; a.runModal() }
    }
    private var errorShown = false
    func rebuildSidebar() {
        var it: [SidebarView.Item] = [.all]
        for a in store.accounts { it.append(.header(a.name, a.id)); a.folders.forEach { it.append(.folder($0)) } }
        sidebar.items = it
        if case .folder(let f) = sel, store.folder(f) == nil, !store.accounts.isEmpty { sel = .all }
        sidebar.sel = sel
    }
    func refresh() {
        let q = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        rows = store.notes.filter { n in
            if case .folder(let f) = sel, n.folder != f { return false }
            return q.isEmpty || (n.name + "\n" + n.plain).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(q)
        }.sorted { $0.modified > $1.modified }
        suppress = true; list.table.reloadData()
        if let id = noteID, let i = rows.firstIndex(where: { $0.id == id }) { list.table.selectRowIndexes([i], byExtendingSelection: false) }
        suppress = false
        if noteID == nil || (store.note(noteID!) == nil), let f = rows.first, query.isEmpty || true { if noteID == nil || store.note(noteID!) == nil { select(f.id) } }
        updateTitle(nil)
    }
    func numberOfRows(in t: NSTableView) -> Int { rows.count }
    func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
        let v = NoteCell(); let n = rows[row]
        v.title = n.name.isEmpty ? L("New Note", "Neue Notiz") : n.name; v.date = Self.dateText(n.modified); return v
    }
    func tableView(_ t: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RowView() }
    func tableViewSelectionDidChange(_ n: Notification) {
        guard !suppress else { return }
        let r = list.table.selectedRow; select(r >= 0 && r < rows.count ? rows[r].id : nil)
    }
    func tableView(_ t: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let i = NSPasteboardItem(); i.setString(rows[row].id, forType: noteDragType); return i
    }
    static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        if Calendar.current.isDateInToday(d) { f.timeStyle = .short; f.dateStyle = .none } else { f.timeStyle = .none; f.dateStyle = .short }
        return f.string(from: d)
    }
    @objc func dbl() { let r = list.table.clickedRow; if r >= 0, r < rows.count { onOpenSingle(rows[r].id) } }

    // MARK: Auswahl / Aktionen
    func select(_ id: String?) {
        if let f = fresh, f != id, f == paper.noteID, paper.isEmptyNote { fresh = nil; store.delete(f) }   // leere neue Notiz verwerfen
        noteID = id; paper.show(id); updateTitle(nil)
        if let id, let i = rows.firstIndex(where: { $0.id == id }), list.table.selectedRow != i { suppress = true; list.table.selectRowIndexes([i], byExtendingSelection: false); list.table.scrollRowToVisible(i); suppress = false }
        if id == nil { suppress = true; list.table.deselectAll(nil); suppress = false }
    }
    func updateTitle(_ live: String?) {
        let id = single ? paper.noteID : noteID
        let n = live ?? id.flatMap { store.note($0)?.name } ?? ""
        titleBar.title = single ? (n.isEmpty ? L("New Note", "Neue Notiz") : n) : (n.isEmpty ? L("Notes", "Notizen") : L("Notes", "Notizen") + " — " + n)
    }
    func newNote() {
        if !query.isEmpty { list.search.clear() }
        let folder: String? = { if case .folder(let f) = sel { return f }; return store.accounts.first?.folders.first?.id }()
        guard let folder else { return }
        store.create(in: folder) { [weak self] id in
            guard let self, let id else { return }
            self.fresh = id; self.refresh(); self.select(id); self.paper.focus()
        }
    }
    func deleteNote(_ id: String) {
        paper.flush()
        let html = (id == paper.noteID) ? RT.html(paper.text.attributedString()) : ""
        if let n = store.note(id) { lastDeleted = (n.folder, html) }
        let idx = rows.firstIndex { $0.id == id }
        if fresh == id { fresh = nil }
        store.delete(id); onDeleted(id)
        if single { window?.close(); return }
        refresh(); if noteID == id || store.note(noteID ?? "") == nil { noteID = nil; let n = min(idx ?? 0, rows.count - 1); select(rows.isEmpty ? nil : rows[max(0, n)].id) }
    }
    func undoDelete() {
        guard let l = lastDeleted else { return }; lastDeleted = nil
        store.create(in: l.folder) { [weak self] id in
            guard let id, let self else { return }
            self.store.save(id, html: l.html, plain: RT.attributed(l.html).string); self.refresh(); self.select(id)
        }
    }
    func noteMenu() -> NSMenu {
        let m = NSMenu(); m.delegate = menuDel
        return m
    }
    private lazy var menuDel = NoteMenuDelegate(self)

    func promptFolder(account: String) {
        let a = NSAlert(); a.messageText = L("New Folder", "Neuer Ordner"); a.addButton(withTitle: "OK"); a.addButton(withTitle: L("Cancel", "Abbrechen"))
        let t = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 22)); t.stringValue = L("New Folder", "Neuer Ordner"); a.accessoryView = t
        if a.runModal() == .alertFirstButtonReturn, !t.stringValue.isEmpty { store.newFolder(t.stringValue, account: account) }
    }
    func newFolder() { if let a = store.accounts.first(where: { acc in if case .folder(let f) = sel { return acc.folders.contains { $0.id == f } }; return false }) ?? store.accounts.first { promptFolder(account: a.id) } }
    func promptRename(_ f: NFolder) {
        let a = NSAlert(); a.messageText = L("Rename Folder", "Ordner umbenennen"); a.addButton(withTitle: "OK"); a.addButton(withTitle: L("Cancel", "Abbrechen"))
        let t = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 22)); t.stringValue = f.name; a.accessoryView = t
        if a.runModal() == .alertFirstButtonReturn, !t.stringValue.isEmpty { store.renameFolder(f.id, to: t.stringValue) }
    }
    func confirmDelete(_ f: NFolder) {
        let n = store.notes.filter { $0.folder == f.id }.count
        let a = NSAlert(); a.alertStyle = .warning
        a.messageText = L("Delete the folder “\(f.name)”?", "Ordner „\(f.name)“ löschen?")
        a.informativeText = L("It contains \(n) note(s), which are moved to Recently Deleted.", "Er enthält \(n) Notiz(en), die in „Zuletzt gelöscht“ verschoben werden.")
        a.addButton(withTitle: L("Delete", "Löschen")); a.addButton(withTitle: L("Cancel", "Abbrechen"))
        if a.runModal() == .alertFirstButtonReturn { store.deleteFolder(f.id) }
    }

    // MARK: Layout
    override func layout() {
        let w = bounds.width, h = bounds.height
        if fs {
            let pw = min(w - 140, 800), px = (w - pw) / 2
            titleBar.frame = NSRect(x: px, y: 18, width: pw, height: M.titleH)
            paper.frame = NSRect(x: px, y: 18, width: pw, height: h - 18 - 22)
            tab.frame = NSRect(x: 0, y: h - 62, width: 150, height: 44)
            let pw2 = M.sidebarW + M.listW
            sidebar.frame = NSRect(x: 0, y: 0, width: M.sidebarW, height: h)
            list.frame = NSRect(x: M.sidebarW, y: 0, width: M.listW, height: h)
            _ = pw2
            sidebar.isHidden = single || !panelOpen; list.isHidden = single || !panelOpen
            tab.isHidden = single
            if panelOpen { sidebar.frame = NSRect(x: 0, y: 40, width: M.sidebarW, height: h - 40 - 70); list.frame = NSRect(x: M.sidebarW, y: 40, width: M.listW, height: h - 40 - 70) }
        } else {
            titleBar.frame = NSRect(x: 0, y: 0, width: w, height: M.titleH)
            tab.isHidden = true
            if single { paper.frame = bounds }
            else {
                sidebar.isHidden = !showFolders; list.isHidden = false
                let sw = showFolders ? M.sidebarW : 0
                sidebar.frame = NSRect(x: 0, y: 0, width: sw, height: h)
                list.frame = NSRect(x: sw, y: 0, width: M.listW, height: h)
                paper.frame = NSRect(x: sw + M.listW, y: 0, width: w - sw - M.listW, height: h)
            }
        }
        list.seg0.selected = showFolders; list.seg1.selected = !showFolders
        titleBar.fullscreen = fs
    }
    private func applyFS() {
        paper.fullscreen = fs; panelOpen = false
        needsLayout = true; needsDisplay = true
    }
    override func draw(_ r: NSRect) {
        guard fs else { NSColor(232, 232, 232).setFill(); bounds.fill(); return }
        Draw.leather(bounds, active: true); NSColor(0, 0, 0, 0.42).setFill(); bounds.fill()
        // umlaufende Naht
        let seam = NSBezierPath(roundedRect: bounds.insetBy(dx: 9, dy: 9), xRadius: 6, yRadius: 6)
        seam.lineWidth = 1.5; seam.setLineDash([5, 3], count: 2, phase: 0); NSColor(176, 134, 106, 0.8).setStroke(); seam.stroke()
        let d = bounds.insetBy(dx: 9, dy: 10); let dark = NSBezierPath(roundedRect: d.offsetBy(dx: 0, dy: 1.5), xRadius: 6, yRadius: 6)
        dark.lineWidth = 1.5; dark.setLineDash([5, 3], count: 2, phase: 0); NSColor(0, 0, 0, 0.45).setStroke(); dark.stroke()
    }
    override func cancelOperation(_ s: Any?) { if fs { onFullscreen() } }
    override var acceptsFirstResponder: Bool { true }
}

final class NoteMenuDelegate: NSObject, NSMenuDelegate {
    weak var root: RootView?
    init(_ r: RootView) { root = r }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let r = root, let row = Optional(r.list.table.clickedRow), row >= 0, row < r.rows.count else { return }
        let n = r.rows[row]
        menu.addItem(ClosureItem(title: L("Open in New Window", "In neuem Fenster öffnen")) { r.onOpenSingle(n.id) })
        let mv = NSMenuItem(title: L("Move to", "Bewegen nach"), action: nil, keyEquivalent: ""); let sub = NSMenu()
        for a in r.store.accounts { for f in a.folders { sub.addItem(ClosureItem(title: "\(a.name) — \(f.name)") { r.store.move(n.id, to: f.id) }) } }
        mv.submenu = sub; menu.addItem(mv)
        menu.addItem(.separator())
        menu.addItem(ClosureItem(title: L("Delete", "Löschen")) { r.deleteNote(n.id) })
    }
}
