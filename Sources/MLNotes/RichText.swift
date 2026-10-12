import AppKit

/// Die drei Standardschriften von Notes 10.8 (Macworld). Gilt für neue Notizen und die Darstellung.
enum DefaultFont: String, CaseIterable {
    case noteworthy = "Noteworthy", markerFelt = "Marker Felt", helvetica = "Helvetica"
    static var current: DefaultFont {
        get { DefaultFont(rawValue: UserDefaults.standard.string(forKey: "defaultFont") ?? "") ?? .noteworthy }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "defaultFont") }
    }
    var size: CGFloat { switch self { case .noteworthy: 15; case .markerFelt: 14; case .helvetica: 13 } }
    func font(size s: CGFloat? = nil, bold: Bool = false, italic: Bool = false) -> NSFont {
        let sz = s ?? size
        let name: String
        switch self {
        case .noteworthy: name = bold ? "Noteworthy-Bold" : "Noteworthy-Light"
        case .markerFelt: name = bold ? "MarkerFelt-Wide" : "MarkerFelt-Thin"
        case .helvetica: name = bold ? (italic ? "Helvetica-BoldOblique" : "Helvetica-Bold") : (italic ? "Helvetica-Oblique" : "Helvetica")
        }
        return NSFont(name: name, size: sz) ?? .systemFont(ofSize: sz, weight: bold ? .bold : .regular)
    }
}

enum RT {
    static let ink = NSColor(30, 28, 26)

    /// Notes-HTML → Attributed String in der gewählten Standardschrift (Fett/Kursiv/Größenverhältnis bleiben erhalten).
    static func attributed(_ html: String) -> NSMutableAttributedString {
        let doc = html.contains("<html") ? html : "<html><head><meta charset=\"utf-8\"></head><body>\(html)</body></html>"
        guard let m = try? NSMutableAttributedString(data: Data(doc.utf8), options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) else { return NSMutableAttributedString() }
        normalize(m)
        return m
    }

    static func normalize(_ m: NSMutableAttributedString) {
        let df = DefaultFont.current, full = NSRange(location: 0, length: m.length)
        m.enumerateAttribute(.font, in: full) { v, r, _ in
            let f = (v as? NSFont) ?? .systemFont(ofSize: 12)
            let t = NSFontManager.shared.traits(of: f)
            m.addAttribute(.font, value: df.font(size: df.size * min(max(f.pointSize / 12, 1), 1.25), bold: t.contains(.boldFontMask), italic: t.contains(.italicFontMask)), range: r)
            if t.contains(.italicFontMask), df != .helvetica { m.addAttribute(.obliqueness, value: 0.2, range: r) }   // Schrift ohne Kursivschnitt
        }
        m.enumerateAttribute(.paragraphStyle, in: full) { v, r, _ in
            let p = ((v as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            p.paragraphSpacing = 0; p.paragraphSpacingBefore = 0; p.lineSpacing = 0
            p.minimumLineHeight = 0; p.maximumLineHeight = 0; p.lineHeightMultiple = 0
            m.addAttribute(.paragraphStyle, value: p, range: r)
        }
        m.enumerateAttribute(.attachment, in: full) { v, _, _ in if let a = v as? NSTextAttachment { fit(a) } }
        m.removeAttribute(.backgroundColor, range: full)
        m.enumerateAttribute(.link, in: full) { v, r, _ in if v == nil { m.addAttribute(.foregroundColor, value: ink, range: r) } }
        if m.string.hasSuffix("\n") { m.deleteCharacters(in: NSRange(location: m.length - 1, length: 1)) }
    }

    /// Attributed String → einfaches Notes-HTML (div / ul / ol / b / i / u / s / a). Größen und Schriftfamilien werden nicht gespeichert.
    static func html(_ s: NSAttributedString) -> String {
        let str = s.string as NSString
        if str.length == 0 { return "<div><br></div>" }
        var out = "", open: String?, loc = 0
        func close() { if let o = open { out += "</\(o)>"; open = nil } }
        while loc <= str.length {
            if loc == str.length { if str.hasSuffix("\n") { close(); out += "<div><br></div>" }; break }
            let pr = str.paragraphRange(for: NSRange(location: loc, length: 0))
            var body = pr; if body.length > 0, str.character(at: NSMaxRange(body) - 1) == 10 { body.length -= 1 }
            var bodyR = body
            if let l = (s.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle)?.textLists.last, body.length > 0,
               let m = try? NSRegularExpression(pattern: "^\\t[^\\t]*\\t").firstMatch(in: str as String, range: body), m.range.location == body.location { _ = l; bodyR = NSRange(location: NSMaxRange(m.range), length: body.length - m.range.length) }   // Listenmarke gehört nicht zum Inhalt
            let inline = inlineHTML(s, bodyR)
            if let l = (s.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle)?.textLists.last {
                let r = l.markerFormat.rawValue, tag = (r.contains("decimal") || r.contains("alpha") || r.contains("roman")) ? "ol" : "ul"
                if open != tag { close(); out += "<\(tag)>"; open = tag }
                out += "<li>\(inline.isEmpty ? "<br>" : inline)</li>"
            } else { close(); out += inline.isEmpty ? "<div><br></div>" : "<div>\(inline)</div>" }
            loc = NSMaxRange(pr)
        }
        close()
        return out
    }
    private static func inlineHTML(_ s: NSAttributedString, _ r: NSRange) -> String {
        var out = ""
        s.enumerateAttributes(in: r) { a, rr, _ in
            if let at = a[.attachment] as? NSTextAttachment { out += imgTag(at); return }
            var t = (s.string as NSString).substring(with: rr).replacingOccurrences(of: "\u{FFFC}", with: "")
                .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\u{2028}", with: "<br>")
            if t.isEmpty { return }
            let tr = (a[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
            if tr.contains(.boldFontMask) { t = "<b>\(t)</b>" }
            if tr.contains(.italicFontMask) || ((a[.obliqueness] as? Double) ?? 0) > 0 { t = "<i>\(t)</i>" }
            if let u = a[.underlineStyle] as? Int, u != 0, a[.link] == nil { t = "<u>\(t)</u>" }
            if let k = a[.strikethroughStyle] as? Int, k != 0 { t = "<strike>\(t)</strike>" }
            if let l = a[.link] { t = "<a href=\"\(((l as? URL)?.absoluteString ?? "\(l)").replacingOccurrences(of: "\"", with: "&quot;"))\">\(t)</a>" }
            out += t
        }
        return out
    }
}

extension RT {
    /// Anzeigebreite eingebetteter Bilder (Textbreite); wird von PaperView gesetzt.
    nonisolated(unsafe) static var maxImageWidth: CGFloat = 340
    static func data(of at: NSTextAttachment) -> Data? { at.fileWrapper?.regularFileContents ?? at.contents }
    /// Bild als Data-URI: Notes legt daraus beim Setzen des Bodys einen echten Anhang an (geprüft).
    static func imgTag(_ at: NSTextAttachment) -> String {
        guard var d = data(of: at) else { return "" }
        var mime = "image/png"
        if d.starts(with: [0xFF, 0xD8]) { mime = "image/jpeg" } else if d.starts(with: [0x47, 0x49, 0x46]) { mime = "image/gif" }
        else if !d.starts(with: [0x89, 0x50]) {      // TIFF, HEIC, WebP … → PNG
            guard let i = NSImage(data: d), let t = i.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) else { return "" }
            d = png
        }
        return "<img src=\"data:\(mime);base64,\(d.base64EncodedString())\">"
    }
    /// Bild proportional auf die Textbreite verkleinern (Original bleibt unverändert, ANH-05).
    static func fit(_ at: NSTextAttachment) {
        if at.image == nil, let d = data(of: at) { at.image = NSImage(data: d) }
        guard let img = at.image, img.size.width > 0 else { return }
        let k = min(1, maxImageWidth / img.size.width)
        at.bounds = NSRect(x: 0, y: 0, width: (img.size.width * k).rounded(), height: (img.size.height * k).rounded())
    }
}

extension RT {
    /// Notiz als RTFD-Paket (Rich Text mit Bildanhängen) bzw. als reiner Text.
    static func rtfd(_ s: NSAttributedString) -> FileWrapper? { s.rtfdFileWrapper(from: NSRange(location: 0, length: s.length), documentAttributes: [:]) }
    static func plain(_ s: NSAttributedString) -> String { s.string.replacingOccurrences(of: "\u{FFFC}", with: "") }
}

extension NSString { func hasSuffix(_ s: String) -> Bool { (self as String).hasSuffix(s) } }

/// `MLNotes -selftest`: HTML → Text → HTML verliert weder Text noch Auszeichnung (ponytail: ein Check statt Testframework).
func runSelfTest() -> Int32 {
    let a = RT.attributed("<div>Titel &amp; Co</div><div><b>fett</b> <i>kursiv</i> <u>unter</u></div><div><br></div><ul><li>eins</li><li>zwei</li></ul>")
    let h = RT.html(a)
    let ok = a.string.contains("Titel & Co") && h.contains("<b>fett</b>") && h.contains("<i>kursiv</i>") && h.contains("<u>unter</u>") && h.contains("<li>eins</li>") && h.contains("&amp;")
    // Bild: PNG-Anhang → <img data:…> → wieder einlesen → Daten identisch
    let png = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!
    let at = NSTextAttachment(data: png, ofType: "public.png"); at.image = NSImage(data: png); RT.fit(at)
    let ih = RT.html(NSAttributedString(attachment: at))
    let back = RT.attributed(ih); var same = false
    back.enumerateAttribute(.attachment, in: NSRange(location: 0, length: back.length)) { v, _, _ in if let a = v as? NSTextAttachment, let d = RT.data(of: a), let i = NSBitmapImageRep(data: d), i.pixelsWide == 8, i.pixelsHigh == 4 { same = true } }
    let ok2 = ih.contains("<img src=\"data:image/png;base64,") && same && at.bounds.width == 8
    // RTFD-Export: Text, Fett und Bild bleiben im Paket erhalten
    let exp = NSMutableAttributedString(string: "Hallo ", attributes: [.font: DefaultFont.current.font(bold: true)]); exp.append(NSAttributedString(attachment: at))
    var ok3 = false
    if let fw = RT.rtfd(exp), let rd = NSAttributedString(rtfdFileWrapper: fw, documentAttributes: nil) {
        var img = false; rd.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rd.length)) { v, _, _ in if v is NSTextAttachment { img = true } }
        ok3 = rd.string.hasPrefix("Hallo") && img && fw.isDirectory
    }
    // Icon-Einstellung: falsche Größe / kein PNG werden abgelehnt
    let small = FileManager.default.temporaryDirectory.appendingPathComponent("mln-icon-test.png"); try? NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!.representation(using: .png, properties: [:])!.write(to: small)
    var ok4 = false; do { try AppIcon.set(from: small) } catch AppIcon.Failure.size(100, 100) { ok4 = true } catch {}
    try? "x".write(to: small, atomically: true, encoding: .utf8); do { try AppIcon.set(from: small) } catch AppIcon.Failure.notPNG { ok4 = ok4 && true } catch { ok4 = false }
    try? FileManager.default.removeItem(at: small); ok3 = ok3 && ok4
    print(ok && ok2 && ok3 ? "selftest OK" : "selftest FAIL img=\(ok2) rtfd=\(ok3) \(ih.prefix(60))"); return ok && ok2 && ok3 ? 0 : 1
    print(ok ? "selftest OK" : "selftest FAIL: \(h)"); return ok ? 0 : 1
}
