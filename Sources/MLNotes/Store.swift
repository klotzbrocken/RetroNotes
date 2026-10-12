import AppKit

// Keine eigene Datenbank: alle Notizen, Ordner und Konten liegen in der System-App „Notizen“ und werden per
// Scripting-Schnittstelle (JXA über /usr/bin/osascript) gelesen und geschrieben. Hier wird nur gecacht.

struct NFolder: Hashable { let id: String; var name: String; let account: String }
struct NAccount { let id: String; let name: String; var folders: [NFolder] }
struct NNote { let id: String; var folder: String; var name: String; var modified: Date; var created: Date; var plain: String }
struct NBody { var html: String; var readOnly: String? }
enum Sel: Equatable { case all, folder(String) }

func L(_ en: String, _ de: String) -> String { Locale.preferredLanguages.first?.hasPrefix("de") == true ? de : en }

final class NotesStore {
    static let listChanged = Notification.Name("MLNListChanged")
    static let noteUpdated = Notification.Name("MLNNoteUpdated")   // object: Quelle (PaperView), userInfo["id"]
    let demo: Bool
    private(set) var accounts: [NAccount] = []
    private(set) var notes: [NNote] = []
    private(set) var error: String?
    private var bodies: [String: String] = [:]
    private let q = DispatchQueue(label: "mln.osa")
    private static let trashNames: Set<String> = ["recently deleted", "zuletzt gelöscht", "kürzlich gelöscht"]
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()

    init(demo: Bool) { self.demo = demo }

    // MARK: osascript
    private func osa(_ js: String, _ args: [String] = []) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-l", "JavaScript", "-e", js] + args
        let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
        try p.run()
        let d = o.fileHandleForReading.readDataToEndOfFile(), ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "osa", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: ed, as: UTF8.self)])
        }
        return String(decoding: d, as: UTF8.self)
    }
    private func post() { NotificationCenter.default.post(name: Self.listChanged, object: self) }
    private func fail(_ e: Error) {
        let m = e.localizedDescription
        error = m.contains("-1743") || m.contains("nicht berechtigt") || m.contains("not authorized")
            ? L("Access to Notes was denied. Allow it in System Settings › Privacy & Security › Automation.",
                "Zugriff auf Notizen wurde verweigert. Erlaube ihn in Systemeinstellungen › Datenschutz & Sicherheit › Automation.")
            : m
        post()
    }

    // MARK: Lesen
    private struct AccDTO: Decodable { struct F: Decodable { let id: String; let name: String }; let id: String; let name: String; let folders: [F] }
    private struct MetaDTO: Decodable { let ids: [String]; let names: [String]; let mod: [String]; let cre: [String] }
    private struct PlainDTO: Decodable { let ids: [String]; let plain: [String] }

    func reload(done: (() -> Void)? = nil) {
        if demo { if accounts.isEmpty { loadDemo() }; post(); done?(); return }
        q.async { [self] in
            do {
                let accJS = "function run(){const N=Application('Notes');return JSON.stringify(N.accounts().map(a=>({id:a.id(),name:a.name(),folders:a.folders().map(f=>({id:f.id(),name:f.name()}))})))}"
                let dto = try JSONDecoder().decode([AccDTO].self, from: Data(osa(accJS).utf8))
                let accs = dto.map { a in NAccount(id: a.id, name: a.name, folders: a.folders.filter { !Self.trashNames.contains($0.name.lowercased()) }.map { NFolder(id: $0.id, name: $0.name, account: a.id) }) }
                let metaJS = "function run(a){const ns=Application('Notes').folders.byId(a[0]).notes;return JSON.stringify({ids:ns.id(),names:ns.name(),mod:ns.modificationDate(),cre:ns.creationDate()})}"
                var all: [NNote] = []
                for f in accs.flatMap(\.folders) {
                    let m = try JSONDecoder().decode(MetaDTO.self, from: Data(osa(metaJS, [f.id]).utf8))
                    for i in m.ids.indices {
                        all.append(NNote(id: m.ids[i], folder: f.id, name: m.names[i], modified: Self.iso.date(from: m.mod[i]) ?? .distantPast, created: Self.iso.date(from: m.cre[i]) ?? .distantPast, plain: ""))
                    }
                }
                DispatchQueue.main.async {
                    let old = Dictionary(uniqueKeysWithValues: self.notes.map { ($0.id, $0.plain) })
                    self.accounts = accs; self.notes = all.map { var n = $0; n.plain = old[n.id] ?? ""; return n }
                    self.error = nil; self.post(); done?()
                    self.loadPlain(accs.flatMap(\.folders))
                }
            } catch { DispatchQueue.main.async { self.fail(error); done?() } }
        }
    }
    /// Phase 2: Klartext für Suche/Vorschau (je Notiz max. 2000 Zeichen).
    private func loadPlain(_ folders: [NFolder]) {
        q.async { [self] in
            let js = "function run(a){const ns=Application('Notes').folders.byId(a[0]).notes;return JSON.stringify({ids:ns.id(),plain:ns.plaintext().map(s=>s.slice(0,2000))})}"
            for f in folders {
                guard let p = try? JSONDecoder().decode(PlainDTO.self, from: Data(osa(js, [f.id]).utf8)) else { continue }
                DispatchQueue.main.async {
                    let m = Dictionary(uniqueKeysWithValues: zip(p.ids, p.plain))
                    for i in self.notes.indices { if let t = m[self.notes[i].id] { self.notes[i].plain = t } }
                    self.post()
                }
            }
        }
    }

    func body(_ id: String, done: @escaping (NBody) -> Void) {
        if demo { done(NBody(html: bodies[id] ?? "", readOnly: nil)); return }
        if let h = bodies[id] { done(NBody(html: h, readOnly: nil)); return }
        q.async { [self] in
            let js = "function run(a){const n=Application('Notes').notes.byId(a[0]);return JSON.stringify({body:n.body(),pw:n.passwordProtected(),att:n.attachments().length})}"
            struct D: Decodable { let body: String; let pw: Bool; let att: Int }
            do {
                let d = try JSONDecoder().decode(D.self, from: Data(osa(js, [id]).utf8))
                var ro: String?
                if d.pw { ro = L("This note is password-protected.", "Diese Notiz ist passwortgeschützt.") }
                else if d.att > 0 || d.body.contains("<table") || d.body.contains("<img") {
                    ro = L("Read-only: contains attachments or tables that would be lost on saving.", "Schreibgeschützt: enthält Anhänge oder Tabellen, die beim Speichern verloren gingen.")
                }
                DispatchQueue.main.async { if ro == nil { self.bodies[id] = d.body }; done(NBody(html: d.body, readOnly: ro)) }
            } catch { DispatchQueue.main.async { self.fail(error); done(NBody(html: "", readOnly: error.localizedDescription)) } }
        }
    }

    // MARK: Schreiben
    func save(_ id: String, html: String, plain: String, sync: Bool = false) {
        bodies[id] = html
        if let i = notes.firstIndex(where: { $0.id == id }) {
            notes[i].plain = plain; notes[i].modified = Date()
            notes[i].name = plain.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        }
        post()
        if demo { demoBodies[id] = html; return }
        let work = { [self] in
            // Große Bodys (Bilder) laufen über eine Temp-Datei: Argumentlänge von osascript ist begrenzt (~1 MiB).
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mln-\(UUID().uuidString).html")
            defer { try? FileManager.default.removeItem(at: tmp) }
            do {
                try html.write(to: tmp, atomically: true, encoding: .utf8)
                _ = try osa("ObjC.import('Foundation');function run(a){const b=ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError($(a[1]),$.NSUTF8StringEncoding,null));Application('Notes').notes.byId(a[0]).body=b;return 'ok'}", [id, tmp.path]) }
            catch { DispatchQueue.main.async { self.fail(error) } }
        }
        if sync { q.sync(execute: work) } else { q.async(execute: work) }
    }
    private var demoBodies: [String: String] = [:]

    func create(in folder: String, done: @escaping (String?) -> Void) {
        let html = "<div><br></div>"
        func add(_ id: String) {
            notes.append(NNote(id: id, folder: folder, name: "", modified: Date(), created: Date(), plain: "")); bodies[id] = html; post(); done(id)
        }
        if demo { add("demo-\(UUID().uuidString)"); return }
        q.async { [self] in
            do {
                let id = try osa("function run(a){const N=Application('Notes');const n=N.Note({body:a[1]});N.folders.byId(a[0]).notes.push(n);return n.id()}", [folder, html]).trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async { add(id) }
            } catch { DispatchQueue.main.async { self.fail(error); done(nil) } }
        }
    }
    /// Löscht in den Ordner „Zuletzt gelöscht“ der System-App (dort wiederherstellbar).
    func delete(_ id: String) {
        notes.removeAll { $0.id == id }; bodies[id] = nil; post()
        guard !demo else { return }
        q.async { [self] in do { _ = try osa("function run(a){Application('Notes').notes.byId(a[0]).delete();return 'ok'}", [id]) } catch { DispatchQueue.main.async { self.fail(error) } } }
    }
    func move(_ id: String, to folder: String) {
        if let i = notes.firstIndex(where: { $0.id == id }) { notes[i].folder = folder }; post()
        guard !demo else { return }
        q.async { [self] in do { _ = try osa("function run(a){const N=Application('Notes');N.move(N.notes.byId(a[0]),{to:N.folders.byId(a[1])});return 'ok'}", [id, folder]) } catch { DispatchQueue.main.async { self.fail(error); self.reload() } } }
    }
    func newFolder(_ name: String, account: String) {
        guard !demo else { if let i = accounts.firstIndex(where: { $0.id == account }) { accounts[i].folders.append(NFolder(id: "demo-\(UUID().uuidString)", name: name, account: account)); post() }; return }
        q.async { [self] in
            do { _ = try osa("function run(a){const N=Application('Notes');N.accounts.byId(a[0]).folders.push(N.Folder({name:a[1]}));return 'ok'}", [account, name]); DispatchQueue.main.async { self.reload() } }
            catch { DispatchQueue.main.async { self.fail(error) } }
        }
    }
    func renameFolder(_ id: String, to name: String) {
        guard !demo else { return }
        q.async { [self] in
            do { _ = try osa("function run(a){Application('Notes').folders.byId(a[0]).name=a[1];return 'ok'}", [id, name]); DispatchQueue.main.async { self.reload() } }
            catch { DispatchQueue.main.async { self.fail(error) } }
        }
    }
    func deleteFolder(_ id: String) {
        guard !demo else { return }
        q.async { [self] in
            do { _ = try osa("function run(a){Application('Notes').folders.byId(a[0]).delete();return 'ok'}", [id]); DispatchQueue.main.async { self.reload() } }
            catch { DispatchQueue.main.async { self.fail(error) } }
        }
    }

    func folder(_ id: String) -> NFolder? { accounts.flatMap(\.folders).first { $0.id == id } }
    func note(_ id: String) -> NNote? { notes.first { $0.id == id } }

    // MARK: Demo (nur -demo; für Referenzvergleiche ohne echte Notizen)
    private func loadDemo() {
        accounts = [NAccount(id: "a1", name: "iCloud", folders: [NFolder(id: "f1", name: "Notes", account: "a1")]),
                    NAccount(id: "a2", name: L("On My Mac", "Auf meinem Mac"), folders: [NFolder(id: "f2", name: "Notes", account: "a2")])]
        let cal = Calendar.current; let d = DateComponents(year: 2012, month: 5, day: 28, hour: 11, minute: 39)
        let base = cal.date(from: d)!
        let items: [(String, String)] = [
            ("OS X screenshots", "<div>OS X screenshots</div>"),
            ("Things to remove from the attic", "<div>Things to remove from the attic</div><div><br></div><div>Baby clothes: donate most, sell some.</div><div><br></div><div>Air conditioners: special trash pickup</div><div><br></div><div>Old Apple and NeXT hardware: keep!</div>"),
            ("Upstairs TiVo MAC addresses", "<div>Upstairs TiVo MAC addresses</div>"),
            ("Twitter and in-band signaling", "<div>Twitter and in-band signaling</div>"),
            ("ESB Incomparable", "<div>ESB Incomparable</div>")]
        for (i, it) in items.enumerated() {
            let id = "demo\(i)"; notes.append(NNote(id: id, folder: "f1", name: it.0, modified: base.addingTimeInterval(i < 3 ? Double(2 - i) * 0.1 : Double(-(i - 2) * 60)), created: base, plain: it.0))
            demoBodies[id] = it.1; bodies[id] = it.1
        }
    }
}

// MARK: Vollständige Sicherung / Wiederherstellung (AUS-01)
// Format: <Ordner>/manifest.json (schemaVersion, Notizen mit Konto/Ordner/Datum/Anhangszahl) + <Konto>/<Ordner>/<nnn> <Titel>.html
// mit dem unveränderten Notiz-Body. Grenze der Scripting-Schnittstelle: Anhänge sind nicht auslesbar – ihre Zahl steht im Manifest.
struct BackupNote: Codable { let id: String, account: String, folder: String, name: String, created: Date, modified: Date, file: String?, attachments: Int, locked: Bool }
struct BackupManifest: Codable { var schemaVersion = 1; let created: Date; let app: String; let notes: [BackupNote] }
struct BackupSummary { var notes = 0, withAttachments = 0, locked = 0, failed = 0, restored = 0, skipped = 0, foldersCreated = 0 }

extension NotesStore {
    private static let bodyJS = """
    function run(a){const ns=Application('Notes').folders.byId(a[0]).notes;const n=ns.length;const out=[];
     for(let i=0;i<n;i++){const x=ns[i];let o={id:x.id(),name:x.name(),mod:x.modificationDate(),cre:x.creationDate(),locked:false,att:0,body:''};
      try{o.locked=x.passwordProtected()}catch(e){}
      if(!o.locked){try{o.att=x.attachments().length;o.body=x.body()}catch(e){o.err=String(e)}}
      out.push(o)}
     return JSON.stringify(out)}
    """
    private struct RawNote: Decodable { let id: String; let name: String; let mod: String; let cre: String; let locked: Bool; let att: Int; let body: String; let err: String? }

    private static func safe(_ s: String) -> String {
        let t = s.components(separatedBy: CharacterSet(charactersIn: "/:\\\0\n\r")).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return String((t.isEmpty ? "Notiz" : t).prefix(60))
    }

    /// Schreibt alle Notizen (ohne „Zuletzt gelöscht“) in einen neuen Ordner `dir`. progress/done laufen im Hauptthread.
    func backup(to dir: URL, progress: @escaping (String) -> Void, done: @escaping (Result<BackupSummary, Error>) -> Void) {
        let accs = accounts, demo = demo, demoNotes = notes, demoBodies = demoBodies
        q.async { [self] in
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                var sum = BackupSummary(), entries: [BackupNote] = []
                for a in accs { for f in a.folders {
                    DispatchQueue.main.async { progress("\(a.name) › \(f.name)") }
                    let raws: [RawNote] = demo ? demoNotes.filter { $0.folder == f.id }.map { RawNote(id: $0.id, name: $0.name, mod: Self.iso.string(from: $0.modified), cre: Self.iso.string(from: $0.created), locked: false, att: 0, body: demoBodies[$0.id] ?? "", err: nil) }
                        : try JSONDecoder().decode([RawNote].self, from: Data(osa(Self.bodyJS, [f.id]).utf8))
                    let sub = dir.appendingPathComponent(Self.safe(a.name)).appendingPathComponent(Self.safe(f.name))
                    if !raws.isEmpty { try fm.createDirectory(at: sub, withIntermediateDirectories: true) }
                    for (i, r) in raws.enumerated() {
                        var file: String?
                        if !r.locked, r.err == nil {
                            let name = String(format: "%03d ", i + 1) + Self.safe(r.name) + ".html"
                            try r.body.write(to: sub.appendingPathComponent(name), atomically: true, encoding: .utf8)
                            file = "\(Self.safe(a.name))/\(Self.safe(f.name))/\(name)"
                        }
                        if r.locked { sum.locked += 1 } else if r.err != nil { sum.failed += 1 }
                        if r.att > 0 { sum.withAttachments += 1 }
                        sum.notes += 1
                        entries.append(BackupNote(id: r.id, account: a.name, folder: f.name, name: r.name, created: Self.iso.date(from: r.cre) ?? .distantPast, modified: Self.iso.date(from: r.mod) ?? .distantPast, file: file, attachments: r.att, locked: r.locked))
                    }
                } }
                let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try enc.encode(BackupManifest(created: Date(), app: "RetroNotes", notes: entries)).write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
                let readme = L("Backup of the Notes app. manifest.json lists all notes; each .html file is the unchanged note body.\nLimits of the Notes scripting interface: attachments cannot be read (\(sum.withAttachments) note(s) contain some, see \"attachments\" in the manifest); password-protected notes are listed but not saved (\(sum.locked)).\n",
                               "Sicherung der Notizen-App. manifest.json listet alle Notizen; jede .html-Datei ist der unveränderte Notiz-Body.\nGrenzen der Scripting-Schnittstelle: Anhänge lassen sich nicht auslesen (\(sum.withAttachments) Notiz(en) enthalten welche, siehe „attachments“ im Manifest); passwortgeschützte Notizen werden aufgeführt, aber nicht gesichert (\(sum.locked)).\n")
                try readme.write(to: dir.appendingPathComponent("LIESMICH.txt"), atomically: true, encoding: .utf8)
                DispatchQueue.main.async { done(.success(sum)) }
            } catch { DispatchQueue.main.async { done(.failure(error)) } }
        }
    }

    /// Legt fehlende Notizen aus einer Sicherung neu an (vorhandene IDs werden übersprungen; fehlende Ordner werden erstellt).
    func restore(from dir: URL, progress: @escaping (String) -> Void, done: @escaping (Result<BackupSummary, Error>) -> Void) {
        let have = Set(notes.map(\.id)), accs = accounts, demo = demo
        q.async { [self] in
            do {
                let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
                let m = try dec.decode(BackupManifest.self, from: Data(contentsOf: dir.appendingPathComponent("manifest.json")))
                guard m.schemaVersion == 1 else { throw NSError(domain: "mln", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Unknown backup version.", "Unbekannte Sicherungsversion.")]) }
                var sum = BackupSummary(); sum.notes = m.notes.count
                var todo: [[String: String]] = []
                for n in m.notes {
                    guard let f = n.file, !have.contains(n.id) else { sum.skipped += 1; continue }
                    todo.append(["account": n.account, "folder": n.folder, "path": dir.appendingPathComponent(f).path])
                }
                DispatchQueue.main.async { progress(L("\(todo.count) note(s) to restore …", "\(todo.count) Notiz(en) werden wiederhergestellt …")) }
                if !todo.isEmpty, !demo {
                    let list = FileManager.default.temporaryDirectory.appendingPathComponent("mln-restore-\(UUID().uuidString).json")
                    defer { try? FileManager.default.removeItem(at: list) }
                    try JSONSerialization.data(withJSONObject: todo).write(to: list)
                    let js = """
                    ObjC.import('Foundation');
                    function rd(p){return ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError($(p),$.NSUTF8StringEncoding,null))}
                    function run(a){const N=Application('Notes');const items=JSON.parse(rd(a[0]));let made=0,fold=0,miss=0;
                     for(const it of items){const acc=N.accounts().find(x=>x.name()==it.account);if(!acc){miss++;continue}
                      let f=acc.folders().find(x=>x.name()==it.folder);
                      if(!f){acc.folders.push(N.Folder({name:it.folder}));f=acc.folders().find(x=>x.name()==it.folder);fold++}
                      f.notes.push(N.Note({body:rd(it.path)}));made++}
                     return JSON.stringify({made:made,fold:fold,miss:miss})}
                    """
                    struct R: Decodable { let made: Int; let fold: Int; let miss: Int }
                    let r = try JSONDecoder().decode(R.self, from: Data(osa(js, [list.path]).utf8))
                    sum.restored = r.made; sum.foldersCreated = r.fold; sum.failed = r.miss
                }
                _ = accs
                DispatchQueue.main.async { self.reload { done(.success(sum)) } }
            } catch { DispatchQueue.main.async { done(.failure(error)) } }
        }
    }
}
