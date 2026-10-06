#!/bin/bash
# Builds Markview for release: signed with Developer ID, notarized by Apple and stapled,
# then zipped as build/release/Markview-<version>.zip, with its SHA-256 for a Homebrew cask.
#
# Needs a "Developer ID Application" certificate in the keychain (the newest is used,
# or set IDENTITY to its SHA-1 hash) and notarytool credentials stored once as the
# "markview" profile:
#   xcrun notarytool store-credentials markview --apple-id <Apple ID> --team-id <team ID>
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE=${PROFILE:-markview}
VERSION=$(plutil -extract CFBundleShortVersionString raw Info.plist)
OUT=build/release
APP=build/Markview.app

# The newest valid Developer ID Application identity, as a hash: codesign takes a hash
# even when two certificates share a name, as a renewed one does.
newest_identity() {
  local hash issued newest=0 best=""
  for hash in $(security find-identity -v -p codesigning | awk '/"Developer ID Application/ {print $2}'); do
    issued=$(security find-certificate -a -Z -p -c "Developer ID Application" \
      | awk -v hash="$hash" '$0 == "SHA-1 hash: " hash {found = 1; next} found && /BEGIN/ {copy = 1} copy {print} copy && /END/ {exit}' \
      | openssl x509 -noout -startdate | cut -d= -f2)
    issued=$(date -j -f "%b %e %T %Y %Z" "$issued" +%s)
    if [ "$issued" -gt "$newest" ]; then newest=$issued; best=$hash; fi
  done
  echo "$best"
}
IDENTITY=${IDENTITY:-$(newest_identity)}
if [ -z "$IDENTITY" ]; then echo "No Developer ID Application certificate in the keychain" >&2; exit 1; fi
echo "Signing Markview $VERSION with $(security find-identity -v -p codesigning | awk -v hash="$IDENTITY" '$2 == hash' | cut -d'"' -f2) ($IDENTITY)"

SIGN=$IDENTITY ./build.sh
codesign --verify --deep --strict "$APP"

# Apple checks a zip of the app; the ticket it issues is then stapled to the app itself,
# so the app opens without a network check, and the stapled app is zipped again.
rm -rf "$OUT"
mkdir -p "$OUT"
ditto -c -k --keepParent "$APP" "$OUT/Markview-notarize.zip"
echo "Submitting to Apple's notary service; this usually takes a few minutes"
if ! xcrun notarytool submit "$OUT/Markview-notarize.zip" --keychain-profile "$PROFILE" --wait --output-format json > "$OUT/notarization.json"; then
  cat "$OUT/notarization.json" >&2
  exit 1
fi
status=$(plutil -extract status raw "$OUT/notarization.json")
id=$(plutil -extract id raw "$OUT/notarization.json")
if [ "$status" != Accepted ]; then
  echo "Notarization $status; Apple's log follows" >&2
  xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2
  exit 1
fi
rm "$OUT/Markview-notarize.zip"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$OUT/Markview-$VERSION.zip"
echo "Released $OUT/Markview-$VERSION.zip"
echo "SHA-256 $(shasum -a 256 "$OUT/Markview-$VERSION.zip" | cut -d' ' -f1)"
