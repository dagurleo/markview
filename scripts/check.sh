#!/bin/bash
# Shows what this build renders differently from a released version: every sample, as a PDF
# and as a light and a dark snapshot, compared pixel by pixel.
#
#   scripts/check.sh          against the newest release
#   scripts/check.sh 0.2.0    against that version
#
# Run it after changing the renderer, and before a release: when nothing is meant to change,
# everything should come out the same. Both copies show the samples with the default settings,
# whatever Settings holds, in windows of the same width. The renderings are left in
# build/check/<version> and build/check/current, and for each difference an image of the
# current rendering with the changed pixels in red, in build/check/diff. Build first.
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK=build/check
APP=build/Markview.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -d "$APP" ] || { echo "Build first: ./build.sh" >&2; exit 2; }

VERSION=${1:-$(curl -fsSL https://github.com/dagurleo/markview/releases/latest/download/appcast.xml \
  | sed -n 's:.*<sparkle\:shortVersionString>\(.*\)</sparkle\:shortVersionString>.*:\1:p')}
REFERENCE=$CHECK/release-$VERSION/Markview.app
if [ ! -d "$REFERENCE" ]; then
  echo "Downloading Markview $VERSION"
  zip=$(mktemp)
  curl -fsSL -o "$zip" "https://github.com/dagurleo/markview/releases/download/v$VERSION/Markview-$VERSION.zip"
  mkdir -p "$CHECK/release-$VERSION"
  ditto -x -k "$zip" "$CHECK/release-$VERSION"
  rm "$zip"
fi

if [ ! -x "$CHECK/compare" ] || [ scripts/compare.swift -nt "$CHECK/compare" ]; then
  mkdir -p "$CHECK"
  swiftc -O scripts/compare.swift -o "$CHECK/compare"
fi

# Launching a copy registers its Quick Look extensions, and the first registered serves
# previews; afterwards they are unregistered again, so that the installed copy does.
unregister() {
  for app in "$REFERENCE" "$APP"; do
    for extension in "$app"/Contents/PlugIns/*.appex; do pluginkit -r "$extension" 2>/dev/null || true; done
    "$LSREGISTER" -u "$app" 2>/dev/null || true
  done
}
trap unregister EXIT

# Every setting at its default (see Settings.Key), and the zoom at 100%.
DEFAULTS=(-theme github -appearance system -textSize 16 -textFont "" -codeFont "" -lineLength 736 -lineSpacing 1.3 -pageZoom 1)
snapshot() {   # app, folder, sample
  local name
  name=$(basename "$3" .md)
  MARKVIEW_SNAPSHOT="$2/$name-light.png" MARKVIEW_PDF="$2/$name.pdf" MARKVIEW_APPEARANCE=light MARKVIEW_WIDTH=880 \
    MARKVIEW_SNAPSHOT_DELAY=2 "$1/Contents/MacOS/Markview" "$3" "${DEFAULTS[@]}" > /dev/null 2>&1
  MARKVIEW_SNAPSHOT="$2/$name-dark.png" MARKVIEW_APPEARANCE=dark MARKVIEW_WIDTH=880 \
    MARKVIEW_SNAPSHOT_DELAY=2 "$1/Contents/MacOS/Markview" "$3" "${DEFAULTS[@]}" > /dev/null 2>&1
}

rm -rf "$CHECK/$VERSION" "$CHECK/current" "$CHECK/diff"
mkdir -p "$CHECK/$VERSION" "$CHECK/current"
echo "Rendering the samples with $VERSION and with this build"
for sample in sample/*.md; do
  snapshot "$REFERENCE" "$CHECK/$VERSION" "$sample"
  snapshot "$APP" "$CHECK/current" "$sample"
done
"$CHECK/compare" "$CHECK/$VERSION" "$CHECK/current" "$CHECK/diff"
