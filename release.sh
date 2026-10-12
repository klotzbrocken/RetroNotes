#!/bin/bash
# Release für GitHub: Developer-ID-Signatur + Hardened Runtime, Notarisierung, Stapeln, ZIP.
# Notar-Profil: "Retromac" (dasselbe wie bei RetroMac; Anlegen: xcrun notarytool store-credentials Retromac --apple-id <ID> --team-id FTJLR8JRNS)
set -e
cd "$(dirname "$0")"
PROFILE="${NOTARY_PROFILE:-Retromac}"
VERSION=$(grep -A1 CFBundleShortVersionString build.sh | grep -o '<string>[^<]*' | head -1 | cut -c9-)
HARDENED=1 ./build.sh
APP="build/RetroNotes.app"
codesign --verify --deep --strict --verbose=2 "$APP"
ZIP="build/RetroNotes-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"       # ZIP mit angeheftetem Notarisierungsticket
  spctl --assess --type execute --verbose=2 "$APP"
  echo "FERTIG (notarisiert): $ZIP"
else
  echo "Notar-Profil '$PROFILE' fehlt – nur signiert, NICHT notarisiert: $ZIP (siehe Kommentar oben)"
fi
