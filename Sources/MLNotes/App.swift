import AppKit

func snapshotPNG(_ v: NSView, to path: String) {
    let w = Int(v.bounds.width.rounded()), h = Int(v.bounds.height.rounded())
    guard let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    r.size = v.bounds.size; v.cacheDisplay(in: v.bounds, to: r)
    try? (r.converting(to: .sRGB, renderingIntent: .default) ?? r).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let args = CommandLine.arguments
    lazy var store = NotesStore(demo: args.contains("-demo"))
    var main: MLWindow?
    var singles: [String: MLWindow] = [:]
    var root: RootView? { (NSApp.keyWindow ?? main)?.contentView as? RootView }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppIcon.apply()
        buildMenu(); openMain()
        store.reload()
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.store.reload() }
        if let a = args.first(where: { $0.hasPrefix("-backup=") }) {      // Testhilfe ohne Dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [self] in store.backup(to: URL(fileURLWithPath: String(a.dropFirst(8))), progress: { _ in }) { r in print("BACKUP", r); NSApp.terminate(nil) } }
        }
        if let a = args.first(where: { $0.hasPrefix("-restore=") }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [self] in store.restore(from: URL(fileURLWithPath: String(a.dropFirst(9))), progress: { _ in }) { r in print("RESTORE", r); NSApp.terminate(nil) } }
        }
        if let a = args.first(where: { $0.hasPrefix("-snap=") }) {      // Entwicklerhilfe: Fensterinhalt als PNG (1 px je pt)
            if args.contains("-single"), let id = store.notes.first(where: { $0.name.hasPrefix("Things") })?.id ?? store.notes.first?.id { openSingle(id) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                if args.contains("-full") { toggleFull(main!) }
                if let s = args.first(where: { $0.hasPrefix("-select=") }), let i = Int(s.dropFirst(8)), let r = main?.contentView as? RootView, i < r.rows.count { r.select(r.rows[i].id) }
                if args.contains("-inactive") { NSApp.hide(nil) }
                if let f = args.first(where: { $0.hasPrefix("-dropimg=") }), let d = try? Data(contentsOf: URL(fileURLWithPath: String(f.dropFirst(9)))), let r = main?.contentView as? RootView {   // Testhilfe: Bild wie beim Drop einfügen
                    r.paper.text.isEditable = true; _ = r.paper.text.insert((images: [(d, "t")], rejected: []), at: 36)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(args.first { $0.hasPrefix("-delay=") }.map { String($0.dropFirst(7)) } ?? "") ?? 1.8)) { [self] in
                let w = args.contains("-single") ? singles.values.first : main
                if !args.contains("-inactive") { (w?.contentView as? RootView)?.active = true }
                if args.contains("-realshot"), let w {   // echte Fensteraufnahme inkl. Systemampel (nur dieses Fenster)
                    let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); t.arguments = ["-x", "-o", "-l", "\(w.windowNumber)", String(a.dropFirst(6))]; try? t.run(); t.waitUntilExit()
                } else if let v = w?.contentView { snapshotPNG(v, to: String(a.dropFirst(6))) }
                if args.contains("-quit") { NSApp.terminate(nil) }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool { if main == nil { openMain() } else if !f { main?.makeKeyAndOrderFront(nil) }; return true }
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        PaperView.all.allObjects.forEach { $0.flush(sync: true) }; return .terminateNow
    }

    // MARK: Fenster
    func makeWindow(_ root: RootView, size: NSSize, min: NSSize) -> MLWindow {
        let w = MLWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        // Systemampel; Inhalt (Lederkopf) reicht unter die transparente Titelleiste
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.isReleasedWhenClosed = false; w.delegate = self
        w.backgroundColor = NSColor(232, 232, 232)
        w.contentView = root; w.minSize = min; w.contentMinSize = min
        root.onZoom = { [weak w] in w?.zoom(nil) }
        root.onFullscreen = { [weak self, weak w] in if let w { self?.toggleFull(w) } }
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { _ in root.active = true }
        nc.addObserver(forName: NSWindow.didResignKeyNotification, object: w, queue: .main) { _ in root.active = false }
        for n in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didExposeNotification] { nc.addObserver(forName: n, object: w, queue: .main) { _ in self.placeLights(w) } }
        placeLights(w)
        return w
    }
    /// Systemampel mittig im 23-pt-Lederkopf; Abstand wie im System (Knopf + 6 pt).
    func placeLights(_ w: NSWindow) {
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let fs = (w as? MLWindow)?.inFullscreen == true
        for (i, t) in types.enumerated() {
            guard let b = w.standardWindowButton(t), let sv = b.superview else { continue }
            b.isHidden = fs
            let step = b.frame.width + 6
            b.setFrameOrigin(NSPoint(x: 9 + CGFloat(i) * step, y: sv.frame.height - M.titleH / 2 - b.frame.height / 2 - 0.5))
        }
    }
    func openMain() {
        if let m = main { m.makeKeyAndOrderFront(nil); return }
        let r = RootView(store: store, single: false)
        var size = M.mainDefault
        if let a = args.first(where: { $0.hasPrefix("-size=") }) { let p = a.dropFirst(6).split(separator: "x").compactMap { Double($0) }; if p.count == 2 { size = NSSize(width: p[0], height: p[1]) } }
        let min = M.mainMin(folders: r.showFolders)
        let w = makeWindow(r, size: size, min: min)
        r.wire(self)
        if !args.contains("-demo"), w.setFrameUsingName("MLNMain2") { ensureVisible(w, min: min) } else { w.center() }
        if !args.contains("-demo") { w.setFrameAutosaveName("MLNMain2") }
        ensureVisible(w, min: min)
        main = w; w.makeKeyAndOrderFront(nil)
    }
    /// Gespeicherte Größe/Position nach Displaywechsel in den sichtbaren Bereich zurückführen (FEN-07).
    func ensureVisible(_ w: NSWindow, min: NSSize) {
        var f = w.frame; f.size.width = max(f.width, min.width); f.size.height = max(f.height, min.height)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(f.insetBy(dx: 40, dy: 40)) }) { w.setFrame(f, display: false); w.center() } else { w.setFrame(f, display: false) }
    }
    func openSingle(_ id: String) {
        if let w = singles[id] { w.makeKeyAndOrderFront(nil); return }      // FEN-04
        let r = RootView(store: store, single: true, noteID: id)
        let w = makeWindow(r, size: M.singleDefault, min: M.singleMin)
        let o = main?.frame ?? NSRect(x: 200, y: 400, width: 0, height: 0)
        w.setFrameTopLeftPoint(NSPoint(x: o.maxX + 14 + CGFloat(singles.count) * 24, y: o.maxY - CGFloat(singles.count) * 24))
        ensureVisible(w, min: M.singleMin)
        r.onDeleted = { [weak self] d in self?.noteDeleted(d) }
        singles[id] = w; w.makeKeyAndOrderFront(nil)
    }
    func noteDeleted(_ id: String) { if let w = singles[id] { singles[id] = nil; w.close() } }
    func windowWillClose(_ n: Notification) {
        guard let w = n.object as? MLWindow, let r = w.contentView as? RootView else { return }
        r.paper.flush(sync: true)
        if let k = singles.first(where: { $0.value === w })?.key { singles[k] = nil }
        if w === main { main = nil }
        if w.inFullscreen { NSApp.presentationOptions = [] }
    }
    func zoom(_ w: MLWindow) {
        if let u = w.userFrame { w.userFrame = nil; w.setFrame(u, display: true, animate: true); return }
        w.userFrame = w.frame; w.setFrame((w.screen ?? NSScreen.main!).visibleFrame, display: true, animate: true)
    }
    /// Eigener Vollbildmodus (B2: Lederrahmen, Naht, Lasche) – kein bloßes Vergrößern des Hauptfensters.
    func toggleFull(_ w: MLWindow) {
        guard let r = w.contentView as? RootView else { return }
        if w.inFullscreen {
            w.inFullscreen = false; NSApp.presentationOptions = []; r.fs = false; w.hasShadow = true; placeLights(w)
            if let f = w.preFull { w.setFrame(f, display: true) }
        } else {
            w.preFull = w.frame; w.inFullscreen = true
            if w.isVisible, NSApp.isActive { NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar] }
            r.fs = true; w.hasShadow = false; placeLights(w)
            w.setFrame((w.screen ?? NSScreen.main!).frame, display: true)
        }
    }

    // MARK: Menü
    func buildMenu() {
        let bar = NSMenu()
        func sub(_ t: String) -> NSMenu { let i = NSMenuItem(); let s = NSMenu(title: t); i.submenu = s; bar.addItem(i); return s }
        @discardableResult func add(_ m: NSMenu, _ t: String, _ sel: Selector?, _ k: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: k); i.keyEquivalentModifierMask = mods; i.target = target ?? self; m.addItem(i); return i
        }
        let app = sub("RetroNotes")
        add(app, L("About RetroNotes", "Über RetroNotes"), #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        app.addItem(.separator())
        add(app, L("Settings…", "Einstellungen …"), #selector(showSettings), ",")
        app.addItem(.separator())
        add(app, L("Hide RetroNotes", "RetroNotes ausblenden"), #selector(NSApplication.hide(_:)), "h", target: NSApp)
        app.addItem(.separator())
        add(app, L("Quit RetroNotes", "RetroNotes beenden"), #selector(NSApplication.terminate(_:)), "q", target: NSApp)
        let file = sub(L("File", "Ablage"))
        add(file, L("New Note", "Neue Notiz"), #selector(newNote), "n")
        add(file, L("New Folder", "Neuer Ordner"), #selector(newFolder), "N", [.command, .shift])
        add(file, L("Open Note in New Window", "Notiz in neuem Fenster öffnen"), #selector(openCurrent), "\r")
        add(file, L("Export…", "Exportieren …"), #selector(exportNote), "e")
        add(file, L("Back Up All Notes…", "Alle Notizen sichern …"), #selector(backupAll))
        add(file, L("Restore from Backup…", "Aus Sicherung wiederherstellen …"), #selector(restoreAll))
        file.addItem(.separator())
        add(file, L("Close Window", "Fenster schließen"), #selector(closeWin), "w")
        let edit = sub(L("Edit", "Bearbeiten"))
        add(edit, L("Undo", "Widerrufen"), Selector(("undo:")), "z", target: nil)
        add(edit, L("Redo", "Wiederholen"), Selector(("redo:")), "Z", [.command, .shift], target: nil)
        edit.addItem(.separator())
        add(edit, L("Cut", "Ausschneiden"), #selector(NSText.cut(_:)), "x", target: nil)
        add(edit, L("Copy", "Kopieren"), #selector(NSText.copy(_:)), "c", target: nil)
        add(edit, L("Paste", "Einsetzen"), #selector(NSText.paste(_:)), "v", target: nil)
        add(edit, L("Paste and Match Style", "Einsetzen und Stil anpassen"), #selector(NSTextView.pasteAsPlainText(_:)), "V", [.command, .option, .shift], target: nil)
        add(edit, L("Select All", "Alles auswählen"), #selector(NSText.selectAll(_:)), "a", target: nil)
        edit.addItem(.separator())
        add(edit, L("Delete Note", "Notiz löschen"), #selector(deleteNote), "\u{8}")
        add(edit, L("Undo Delete Note", "Löschen der Notiz widerrufen"), #selector(undoDelete), "")
        add(edit, L("Find", "Suchen"), #selector(find), "f")
        let fmt = sub(L("Format", "Format"))
        add(fmt, L("Bold", "Fett"), #selector(bold), "b"); add(fmt, L("Italic", "Kursiv"), #selector(italic), "i")
        add(fmt, L("Underline", "Unterstrichen"), #selector(underline), "u"); add(fmt, L("Strikethrough", "Durchgestrichen"), #selector(strike), "")
        fmt.addItem(.separator())
        let df = NSMenuItem(title: L("Default Font", "Standardschrift"), action: nil, keyEquivalent: ""); let dm = NSMenu(); df.submenu = dm; fmt.addItem(df)
        for f in DefaultFont.allCases { let i = add(dm, f.rawValue, #selector(setFont(_:))); i.representedObject = f.rawValue }
        add(fmt, L("Show Fonts", "Schriften einblenden"), #selector(NSFontManager.orderFrontFontPanel(_:)), "t", target: NSFontManager.shared)
        add(fmt, L("Lists…", "Listen …"), Selector(("orderFrontListPanel:")), "", target: nil)
        let view = sub(L("View", "Darstellung"))
        add(view, L("Show/Hide Folders", "Ordner ein-/ausblenden"), #selector(toggleFolders), "s", [.command, .option])
        add(view, L("Enter/Exit Full Screen", "Vollbild ein-/ausschalten"), #selector(fullMenu), "f", [.command, .control])
        let win = sub(L("Window", "Fenster"))
        add(win, L("Minimize", "Im Dock ablegen"), #selector(NSWindow.miniaturize(_:)), "m", target: nil)
        add(win, L("Zoom", "Zoomen"), #selector(zoomMenu))
        add(win, L("Notes", "Notizen"), #selector(showMain), "0")
        NSApp.mainMenu = bar; NSApp.windowsMenu = win
    }
    func validateMenuItem(_ i: NSMenuItem) -> Bool {
        if i.action == #selector(setFont(_:)) { i.state = (i.representedObject as? String) == DefaultFont.current.rawValue ? .on : .off }
        if i.action == #selector(undoDelete) { return root?.lastDeleted != nil }
        return true
    }
    @objc func newNote() { if let r = root, !r.single { r.newNote() } else { openMain(); (main?.contentView as? RootView)?.newNote() } }
    @objc func newFolder() { if let r = main?.contentView as? RootView { r.newFolder() } }
    @objc func openCurrent() { if let r = root { if let id = r.single ? r.paper.noteID : r.noteID { openSingle(id) } } }
    /// Einzelnotiz exportieren: RTFD (Rich Text mit Bildern, Standard) oder reiner Text (mit Hinweis auf Verluste).
    @objc func exportNote() {
        guard let r = root, let id = r.single ? r.paper.noteID : r.noteID, let ts = r.paper.text.textStorage else { return }
        r.paper.flush()
        let panel = NSSavePanel(); panel.canCreateDirectories = true
        let pop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        pop.addItems(withTitles: [L("Rich Text with Attachments (RTFD)", "Rich Text mit Anhängen (RTFD)"), L("Plain Text (.txt)", "Reiner Text (.txt)")])
        let hint = NSTextField(wrappingLabelWithString: ""); hint.font = .systemFont(ofSize: 11); hint.frame = NSRect(x: 0, y: 0, width: 360, height: 30)
        let upd = { [unowned panel] in
            let rtfd = pop.indexOfSelectedItem == 0
            hint.stringValue = rtfd ? "" : L("Formatting and images are not kept in plain text.", "Formatierung und Bilder gehen im reinen Text verloren.")
            panel.allowedContentTypes = [rtfd ? .rtfd : .plainText]
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = base + (rtfd ? ".rtfd" : ".txt")
        }
        let target = ClosureItem(title: "", action: upd); pop.target = target; pop.action = NSSelectorFromString("run"); objc_setAssociatedObject(pop, "t", target, .OBJC_ASSOCIATION_RETAIN)
        let stack = NSStackView(views: [pop, hint]); stack.orientation = .vertical; stack.alignment = .leading; stack.frame = NSRect(x: 0, y: 0, width: 360, height: 62)
        panel.accessoryView = stack
        var title = (r.store.note(id)?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if title.isEmpty { title = L("New Note", "Neue Notiz") }
        panel.nameFieldStringValue = String(title.prefix(80)); upd()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if pop.indexOfSelectedItem == 0 {
                guard let fw = RT.rtfd(ts) else { throw CocoaError(.fileWriteUnknown) }
                try fw.write(to: url, options: .atomic, originalContentsURL: nil)
            } else { try RT.plain(ts).write(to: url, atomically: true, encoding: .utf8) }
        } catch { let a = NSAlert(error: error); a.informativeText = L("Choose another location and try again.", "Wähle einen anderen Ort und versuche es erneut."); a.runModal() }
    }
    // MARK: Sicherung / Wiederherstellung
    private func busy(_ text: String) -> (set: (String) -> Void, close: () -> Void) {
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 92), styleMask: [.titled], backing: .buffered, defer: false)
        w.title = text
        let lbl = NSTextField(labelWithString: ""); lbl.frame = NSRect(x: 20, y: 52, width: 320, height: 18); lbl.lineBreakMode = .byTruncatingMiddle
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 24, width: 320, height: 12)); bar.style = .bar; bar.isIndeterminate = true; bar.startAnimation(nil)
        w.contentView?.addSubview(lbl); w.contentView?.addSubview(bar); w.center(); w.makeKeyAndOrderFront(nil)
        return ({ lbl.stringValue = $0 }, { w.orderOut(nil) })
    }
    private func report(_ r: Result<BackupSummary, Error>, restore: Bool, at url: URL) {
        let a = NSAlert()
        switch r {
        case .failure(let e): a.alertStyle = .warning; a.messageText = restore ? L("Restore failed", "Wiederherstellung fehlgeschlagen") : L("Backup failed", "Sicherung fehlgeschlagen"); a.informativeText = e.localizedDescription
        case .success(let s):
            if restore {
                a.messageText = L("\(s.restored) note(s) restored", "\(s.restored) Notiz(en) wiederhergestellt")
                a.informativeText = L("Already present: \(s.skipped). Folders created: \(s.foldersCreated). Not restorable (unknown account): \(s.failed). Attachments are not part of the backup (not readable via scripting).",
                                      "Bereits vorhanden: \(s.skipped). Neu angelegte Ordner: \(s.foldersCreated). Nicht wiederherstellbar (Konto fehlt): \(s.failed). Anhänge sind nicht Teil der Sicherung (per Scripting nicht lesbar).")
            } else {
                a.messageText = L("\(s.notes) note(s) backed up", "\(s.notes) Notiz(en) gesichert")
                a.informativeText = L("Notes with attachments: \(s.withAttachments) (attachments are not readable via scripting and are not included). Password-protected: \(s.locked). Failed: \(s.failed).",
                                      "Notizen mit Anhängen: \(s.withAttachments) (Anhänge sind per Scripting nicht lesbar und nicht enthalten). Passwortgeschützt: \(s.locked). Fehlgeschlagen: \(s.failed).")
                a.addButton(withTitle: "OK"); a.addButton(withTitle: L("Show in Finder", "Im Finder zeigen"))
                if a.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                return
            }
        }
        a.runModal()
    }
    @objc func backupAll() {
        PaperView.all.allObjects.forEach { $0.flush(sync: true) }
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.message = L("Choose where to save the backup folder.", "Wähle, wo der Sicherungsordner angelegt wird."); p.prompt = L("Back Up", "Sichern")
        guard p.runModal() == .OK, let base = p.url else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        let dir = base.appendingPathComponent(L("Notes Backup ", "Notizen-Sicherung ") + f.string(from: Date()))
        let b = busy(L("Backing Up Notes", "Notizen werden gesichert"))
        store.backup(to: dir, progress: b.set) { [self] r in b.close(); report(r, restore: false, at: dir) }
    }
    @objc func restoreAll() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = L("Choose a backup folder (containing manifest.json).", "Wähle einen Sicherungsordner (mit manifest.json)."); p.prompt = L("Restore", "Wiederherstellen")
        guard p.runModal() == .OK, let dir = p.url else { return }
        let c = NSAlert(); c.messageText = L("Restore missing notes from this backup?", "Fehlende Notizen aus dieser Sicherung wiederherstellen?")
        c.informativeText = L("Notes that still exist are left untouched. Missing notes are created again as new notes.", "Noch vorhandene Notizen bleiben unverändert. Fehlende Notizen werden als neue Notizen angelegt.")
        c.addButton(withTitle: L("Restore", "Wiederherstellen")); c.addButton(withTitle: L("Cancel", "Abbrechen"))
        guard c.runModal() == .alertFirstButtonReturn else { return }
        let b = busy(L("Restoring Notes", "Notizen werden wiederhergestellt"))
        store.restore(from: dir, progress: b.set) { [self] r in b.close(); report(r, restore: true, at: dir) }
    }
    @objc func showSettings() { SettingsWindow.shared.show() }
    @objc func closeWin() { NSApp.keyWindow?.close() }
    @objc func deleteNote() { if let r = root, let id = r.single ? r.paper.noteID : r.noteID { r.deleteNote(id) } }
    @objc func undoDelete() { (main?.contentView as? RootView)?.undoDelete() }
    @objc func find() { if let r = main?.contentView as? RootView { main?.makeKeyAndOrderFront(nil); r.panelOpen = r.fs ? true : r.panelOpen; main?.makeFirstResponder(r.list.search.field) } }
    @objc func bold() { root?.paper.toggle(.boldFontMask) }
    @objc func italic() { root?.paper.toggle(.italicFontMask) }
    @objc func underline() { root?.paper.toggleAttr(.underlineStyle) }
    @objc func strike() { root?.paper.toggleAttr(.strikethroughStyle) }
    @objc func setFont(_ s: NSMenuItem) {
        guard let n = s.representedObject as? String, let f = DefaultFont(rawValue: n) else { return }
        DefaultFont.current = f
        for p in PaperView.all.allObjects { let id = p.noteID; p.flush(); p.show(id) }
    }
    @objc func toggleFolders() { if let r = main?.contentView as? RootView { r.showFolders.toggle(); r.fixMin() } }
    @objc func fullMenu() { if let w = (NSApp.keyWindow ?? main) as? MLWindow { toggleFull(w) } }
    @objc func zoomMenu() { if let w = NSApp.keyWindow as? MLWindow { zoom(w) } }
    @objc func showMain() { openMain() }
}

extension RootView {
    func wire(_ d: AppDelegate) { onOpenSingle = { [weak d] in d?.openSingle($0) }; onDeleted = { [weak d] in d?.noteDeleted($0) } }
}
extension MLWindow {
    private static var key = 0
    var preFull: NSRect? { get { objc_getAssociatedObject(self, &Self.key) as? NSRect } set { objc_setAssociatedObject(self, &Self.key, newValue, .OBJC_ASSOCIATION_RETAIN) } }
}

@main
struct MLNotesApp {
    static func main() {
        if CommandLine.arguments.contains("-selftest") { _ = NSApplication.shared; exit(runSelfTest()) }
        let app = NSApplication.shared; let d = AppDelegate(); app.delegate = d; app.run()
    }
}
