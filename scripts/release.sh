#!/bin/bash
# Builds Markview for release: signed with Developer ID, notarized by Apple and stapled.
# Writes to build/release:
#   Markview-<version>.zip  the app, for the Homebrew cask (its SHA-256 is printed) and for Sparkle
#   Markview-<version>.dmg  a disk image with a link to Applications, for downloading by hand
#   appcast.xml             what tells installed copies about the new version
#   notes.md                the version's section of CHANGELOG.md, for the GitHub release
#
# Needs a "Developer ID Application" certificate in the keychain (the newest is used,
# or set IDENTITY to its SHA-1 hash), notarytool credentials stored once as the
# "markview" profile:
#   xcrun notarytool store-credentials markview --apple-id <Apple ID> --team-id <team ID>
# and Sparkle's signing key in the keychain, made once with
#   build/Sparkle-<Sparkle version>/bin/generate_keys --account markview
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE=${PROFILE:-markview}
VERSION=$(plutil -extract CFBundleShortVersionString raw Info.plist)
BUILD=$(plutil -extract CFBundleVersion raw Info.plist)
OUT=build/release
APP=build/Markview.app
REPOSITORY=https://github.com/dagurleo/markview
SPARKLE=build/Sparkle-$(sed -n 's/^SPARKLE_VERSION=//p' build.sh)
SPARKLE_KEY=markview

# What changed, shown in the update window and on the GitHub release.
NOTES=$(awk -v version="$VERSION" '/^## / {found = ($2 == version); next} found' CHANGELOG.md | sed '/./,$!d')
if [ -z "$NOTES" ]; then echo "CHANGELOG.md has no section for $VERSION" >&2; exit 1; fi

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

# Has Apple's notary service check a file, and stops with its log if it is not accepted.
notarize() {
  echo "Submitting $(basename "$1") to Apple's notary service; this usually takes a minute or two"
  if ! xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --output-format json > "$OUT/notarization.json"; then
    cat "$OUT/notarization.json" >&2
    exit 1
  fi
  local status id
  status=$(plutil -extract status raw "$OUT/notarization.json")
  id=$(plutil -extract id raw "$OUT/notarization.json")
  if [ "$status" != Accepted ]; then
    echo "Notarization $status; Apple's log follows" >&2
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2
    exit 1
  fi
  rm "$OUT/notarization.json"
}

SIGN=$IDENTITY ./build.sh
codesign --verify --deep --strict "$APP"
rm -rf "$OUT"
mkdir -p "$OUT"

# Apple checks a zip of the app; the ticket it issues is then stapled to the app itself,
# so the app opens without a network check, and the stapled app is zipped again.
ditto -c -k --keepParent "$APP" "$OUT/Markview-notarize.zip"
notarize "$OUT/Markview-notarize.zip"
rm "$OUT/Markview-notarize.zip"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$OUT/Markview-$VERSION.zip"

# Installed copies read appcast.xml from $REPOSITORY/releases/latest/download (SUFeedURL), so it
# is attached to every release and describes that version alone. Sparkle checks both the zip
# and the appcast against the public half of the key, which is in Info.plist.
ENCLOSURE=$("$SPARKLE/bin/sign_update" --account "$SPARKLE_KEY" "$OUT/Markview-$VERSION.zip")
cat > "$OUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Markview</title>
    <link>$REPOSITORY</link>
    <item>
      <title>Markview $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$(plutil -extract LSMinimumSystemVersion raw Info.plist)</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[$NOTES]]></description>
      <enclosure url="$REPOSITORY/releases/download/v$VERSION/Markview-$VERSION.zip" type="application/octet-stream" $ENCLOSURE/>
    </item>
  </channel>
</rss>
EOF
"$SPARKLE/bin/sign_update" --account "$SPARKLE_KEY" "$OUT/appcast.xml"
printf '%s\n' "$NOTES" > "$OUT/notes.md"

# The disk image holds the stapled app and a link to Applications to drag it onto. It is
# signed and notarized too, so that opening it raises no warning either.
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/Markview.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Markview $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$OUT/Markview-$VERSION.dmg"
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$OUT/Markview-$VERSION.dmg"
notarize "$OUT/Markview-$VERSION.dmg"
xcrun stapler staple "$OUT/Markview-$VERSION.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$OUT/Markview-$VERSION.dmg"

for file in "$OUT/Markview-$VERSION.zip" "$OUT/Markview-$VERSION.dmg"; do
  echo "Released $file  SHA-256 $(shasum -a 256 "$file" | cut -d' ' -f1)"
done
echo "Wrote $OUT/appcast.xml and $OUT/notes.md"
