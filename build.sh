#!/bin/bash
# Baut "RetroNotes.app" in ./build (stabile Signatur, falls ein Entwicklerzertifikat vorhanden ist)
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E "error|warning: var|Build" | head -40
APP="build/RetroNotes.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MLNotes "$APP/Contents/MacOS/RetroNotes"
cp Resources/AppIcon.icns Resources/leather.png Resources/paper.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>RetroNotes</string>
<key>CFBundleDisplayName</key><string>RetroNotes</string>
<key>CFBundleIdentifier</key><string>de.maik.RetroNotes</string>
<key>CFBundleExecutable</key><string>RetroNotes</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
<key>NSAppleEventsUsageDescription</key><string>RetroNotes liest und schreibt deine Notizen in der System-App „Notizen“. / Reads and writes your notes in the system Notes app.</string>
</dict></plist>
P
KIND="Apple Development"; [ -n "$HARDENED" ] && KIND="Developer ID Application"
ID="${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o "\"$KIND[^\"]*\"" | head -1 | tr -d '"')}"
if [ -n "$HARDENED" ]; then   # Release: Developer ID + Hardened Runtime + Zeitstempel (Voraussetzung für Notarisierung)
  codesign --force --timestamp --options runtime --entitlements Resources/RetroNotes.entitlements --sign "$ID" "$APP" && echo "signiert (Hardened Runtime): $ID"
elif [ -n "$ID" ]; then codesign --force --sign "$ID" "$APP" && echo "signiert: $ID" || codesign --force --sign - "$APP"
else codesign --force --sign - "$APP" >/dev/null 2>&1; echo "ad-hoc signiert (Automation-Freigabe ggf. nach jedem Build neu)"; fi
echo "OK: $APP"
