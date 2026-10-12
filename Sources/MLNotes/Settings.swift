import AppKit

/// Eigenes App-Icon: der Nutzer wählt ein PNG mit genau 256×256 Pixeln; es wird in Application Support kopiert und als Dock-Symbol gesetzt.
/// (Das Icon im Finder/Bundle bleibt unverändert – eine Änderung am Bundle würde die Code-Signatur ungültig machen.)
enum AppIcon {
    static var customURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RetroNotes/AppIcon.png")
    }
    static var hasCustom: Bool { FileManager.default.fileExists(atPath: customURL.path) }

    /// Beim Start und nach Änderung: gewähltes PNG, sonst Icon aus dem Bundle.
    static func apply() {
        if let i = NSImage(contentsOf: customURL), hasCustom { NSApp.applicationIconImage = i }
        else if let u = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let i = NSImage(contentsOf: u) { NSApp.applicationIconImage = i }
    }
    enum Failure: LocalizedError {
        case notPNG, size(Int, Int)
        var errorDescription: String? {
            switch self {
            case .notPNG: return L("The file is not a PNG image.", "Die Datei ist kein PNG-Bild.")
            case .size(let w, let h): return L("The image is \(w)×\(h) pixels; exactly 256×256 pixels are required.", "Das Bild hat \(w)×\(h) Pixel; verlangt sind genau 256×256 Pixel.")
            }
        }
    }
    static func set(from url: URL) throws {
        let d = try Data(contentsOf: url, options: .mappedIfSafe)
        guard d.starts(with: [0x89, 0x50, 0x4E, 0x47]), let rep = NSBitmapImageRep(data: d) else { throw Failure.notPNG }
        guard rep.pixelsWide == 256, rep.pixelsHigh == 256 else { throw Failure.size(rep.pixelsWide, rep.pixelsHigh) }
        try FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try d.write(to: customURL, options: .atomic)
        apply()
    }
    static func reset() { try? FileManager.default.removeItem(at: customURL); apply() }
}

final class SettingsWindow: NSWindowController {
    static let shared = SettingsWindow()
    private let preview = NSImageView(), status = NSTextField(wrappingLabelWithString: "")
    private let resetBtn = NSButton(title: "", target: nil, action: nil)

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 190), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("Settings", "Einstellungen"); w.isReleasedWhenClosed = false
        super.init(window: w)
        let v = w.contentView!
        let title = NSTextField(labelWithString: L("App Icon", "App-Symbol")); title.font = .boldSystemFont(ofSize: 13); title.frame = NSRect(x: 20, y: 150, width: 380, height: 18)
        preview.frame = NSRect(x: 20, y: 56, width: 80, height: 80); preview.imageScaling = .scaleProportionallyUpOrDown
        let choose = NSButton(title: L("Choose PNG…", "PNG wählen …"), target: self, action: #selector(choose)); choose.frame = NSRect(x: 116, y: 106, width: 150, height: 28)
        resetBtn.title = L("Use Default", "Standard verwenden"); resetBtn.target = self; resetBtn.action = #selector(reset); resetBtn.frame = NSRect(x: 272, y: 106, width: 130, height: 28)
        status.frame = NSRect(x: 116, y: 40, width: 286, height: 58); status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        let note = NSTextField(wrappingLabelWithString: L("The PNG must be exactly 256×256 pixels. It is used as the Dock icon; the icon of the app file in Finder stays unchanged.", "Das PNG muss genau 256×256 Pixel groß sein. Es wird als Dock-Symbol verwendet; das Symbol der App-Datei im Finder bleibt unverändert."))
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor; note.frame = NSRect(x: 20, y: 8, width: 380, height: 30)
        [title, preview, choose, resetBtn, status, note].forEach(v.addSubview)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    func show() { refresh(); window?.center(); showWindow(nil); NSApp.activate(ignoringOtherApps: true) }
    private func refresh() {
        preview.image = NSApp.applicationIconImage; resetBtn.isEnabled = AppIcon.hasCustom
        status.stringValue = AppIcon.hasCustom ? L("Custom icon active.", "Eigenes Symbol aktiv.") : L("Default icon active.", "Standardsymbol aktiv.")
    }
    @objc private func choose() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png]; p.canChooseDirectories = false
        p.message = L("Choose a PNG image of exactly 256×256 pixels.", "Wähle ein PNG-Bild mit genau 256×256 Pixeln.")
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try AppIcon.set(from: u) } catch { let a = NSAlert(error: error); a.informativeText = L("Please choose a different file.", "Bitte wähle eine andere Datei."); a.beginSheetModal(for: window!) }
        refresh()
    }
    @objc private func reset() { AppIcon.reset(); refresh() }
}
