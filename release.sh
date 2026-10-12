#!/bin/bash
# Release für GitHub: Developer-ID-Signatur + Hardened Runtime, Notarisierung der App, DMG (signiert, notarisiert, gestapelt).
# Notar-Profil: "Retromac" (dasselbe wie bei RetroMac; Anlegen: xcrun notarytool store-credentials Retromac --apple-id <ID> --team-id FTJLR8JRNS)
# Mit "./release.sh publish" wird zusätzlich ein GitHub-Release v<Version> mit dem DMG angelegt.
set -e
cd "$(dirname "$0")"
PROFILE="${NOTARY_PROFILE:-Retromac}"
VERSION=$(grep -A1 CFBundleShortVersionString build.sh | grep -o '<string>[^<]*' | head -1 | cut -c9-)
ID="Developer ID Application: Maik Klotz (FTJLR8JRNS)"
HARDENED=1 ./build.sh
APP="build/RetroNotes.app"; DMG="build/RetroNotes-$VERSION.dmg"; TMP=$(mktemp -d)
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== App notarisieren =="
ditto -c -k --keepParent "$APP" "$TMP/app.zip"
xcrun notarytool submit "$TMP/app.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

echo "== DMG =="
rm -f "$DMG"; mkdir "$TMP/dmg"; cp -R "$APP" "$TMP/dmg/"; ln -s /Applications "$TMP/dmg/Applications"
hdiutil create -volname "RetroNotes" -srcfolder "$TMP/dmg" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
rm -rf "$TMP"; echo "FERTIG: $DMG"

if [ "$1" = "publish" ]; then
  gh release create "v$VERSION" "$DMG" --title "RetroNotes $VERSION" --notes "Notarisiertes DMG (Developer ID, Hardened Runtime). Zugriff auf die System-App Notizen muss beim ersten Start erlaubt werden." 
fi
