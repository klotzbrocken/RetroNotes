# RetroNotes

Nachbau von Notes (OS X 10.8) im skeuomorphen Design. **Keine eigene Datenbank:** Konten, Ordner und Notizen werden über die
Scripting-Schnittstelle (JXA/osascript) aus der System-App „Notizen“ gelesen und dorthin zurückgeschrieben.

```
./build.sh                                   # → build/RetroNotes.app
Reference/make_assets.py                     # Texturen + AppIcon neu erzeugen
MLNotes -demo -select=1 -snap=/tmp/x.png -quit   # Demo-Daten (Referenzszene), PNG 1 px/pt; -single, -full, -size=WxH, -delay=s
python3 Reference/compare.py /tmp/x.png      # Pixelvergleich gegen Referenz (notes-big.png), optional Ausschnitt + Zoom
MLNotes -selftest                            # HTML↔Rich-Text-Roundtrip
```
Maße (1×, aus der Referenz): Lederkopf 22, Ampel Ø12/Abstand 20/Mitte y=11, Seitenleiste 130, Liste 239 (Zeile 37), Linienraster 22,
Standardfenster 736×443, Einzelnotiz 360×480, Mindestgröße 619×300 (ohne Ordner 489×300), Einzelnotiz 250×180 – Mindestmaße sind Annahmen, nicht am Original gemessen.

Grenzen: Notizen mit Anhängen/Tabellen/Passwortschutz sind schreibgeschützt (Speichern würde sie in Notes beschädigen); Checklisten,
Tabellen und Schriftfamilien werden nicht ins HTML zurückgeschrieben; Suche über die ersten 2000 Zeichen je Notiz.

Anhänge: Bilder (PNG/JPEG/GIF/TIFF bis 20 MP) lassen sich per Drag-and-drop oder Einsetzen in eine Notiz legen; sie werden als Data-URI in den
Notiz-Body geschrieben, daraus legt Notizen einen echten Anhang an (geprüft, auch 3 MB über Temp-Datei). Grenzen der Scripting-Schnittstelle:
andere Dateitypen lassen sich nicht anlegen (Hinweis statt stillem Verwerfen); vorhandene Anhänge sind weder auslesbar noch im Body enthalten –
solche Notizen bleiben schreibgeschützt, und ein eingefügtes Bild erscheint nach einem App-Neustart nicht mehr im Editor (in Notizen bleibt es erhalten).

Sicherung (Ablage › Alle Notizen sichern … / Aus Sicherung wiederherstellen …): Ordner mit `manifest.json` (Schema 1) + je Notiz die unveränderte
`.html` unter `Konto/Ordner/`. Wiederherstellung legt nur fehlende Notizen (nach ID) neu an und erstellt fehlende Ordner. Nicht enthalten:
Anhänge (nicht auslesbar) und passwortgeschützte Notizen – beides wird im Manifest und im Abschlussdialog benannt. Testhilfen: `-backup=PFAD`, `-restore=PFAD`.

## Release auf GitHub
`./release.sh` → Developer-ID-Signatur mit Hardened Runtime (`Resources/RetroNotes.entitlements`: nur Apple-Events/Automation), Notarisierung (`notarytool`,
Profil `Retromac` wie bei RetroMac), Stapeln und `build/RetroNotes-<Version>.zip` für GitHub Releases.
Nicht ins Repository/Release: Apple-Icons und -Screenshots, Systemschriften (Noteworthy, Marker Felt, Lucida Grande). Das Icon (`Resources/icon-source.png`)
ist KI-generiert (Gemini) – Nutzungsrechte vor Veröffentlichung selbst prüfen. Eine Lizenz für den Quellcode ist noch nicht gewählt.
