#!/bin/bash
# Takes the screenshots on the landing page with this build's snapshot hooks, into
# site/shots/out. Build first; run from anywhere. Settings come from launch arguments, so
# the user's own are neither used nor changed; each window is sized with an argument too.
set -euo pipefail
cd "$(dirname "$0")/../.."
APP=build/Markview.app
OUT=site/shots/out
SHOTS=site/shots
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -d "$APP" ] || { echo "Build first: ./build.sh" >&2; exit 2; }
mkdir -p "$OUT/themes"

# Launching the build registers its Quick Look extension; leave the installed copy serving previews.
unregister() {
  for extension in "$APP"/Contents/PlugIns/*.appex; do pluginkit -r "$extension" 2>/dev/null || true; done
  "$LSREGISTER" -u "$APP" 2>/dev/null || true
}
trap unregister EXIT

# shot <name> <file> <appearance> <theme> <width> <height> [VAR=value ...]
shot() {
  local name=$1 file=$2 appearance=$3 theme=$4 width=$5 height=$6
  shift 6
  env MARKVIEW_SNAPSHOT="$OUT/$name-page.png" MARKVIEW_CHROME_SNAPSHOT="$OUT/$name.png" \
    MARKVIEW_APPEARANCE="$appearance" MARKVIEW_WIDTH="$width" MARKVIEW_SNAPSHOT_DELAY=3 "$@" \
    "$APP/Contents/MacOS/Markview" "$file" -theme "$theme" -appearance system -textSize 16 -textFont "" -codeFont "" \
    -lineLength 736 -lineSpacing 1.3 -pageZoom 1 "-NSWindow Frame Viewer" "200 200 $width $height 0 0 3440 1410" \
    > /dev/null 2>&1
  echo "$name"
}

only=${1:-all}   # all, features, themes or finish

if [ "$only" = all ] || [ "$only" = features ]; then
  for appearance in light dark; do
    for theme in github paper; do
      shot "hero-$theme-$appearance" "$SHOTS/lighthouse" $appearance $theme 1180 700 MARKVIEW_OUTLINE=1
    done
  done
  shot math-light "$SHOTS/notes/gaussian.md" light paper 900 860
  shot math-dark "$SHOTS/notes/gaussian.md" dark paper 900 860
  shot diagrams-light "$SHOTS/lighthouse/docs/architecture.md" light github 900 900
  shot diagrams-dark "$SHOTS/lighthouse/docs/architecture.md" dark tokyo-night 900 900
  shot code-dark "$SHOTS/lighthouse/docs/checks.md" dark catppuccin 900 860
  shot code-light "$SHOTS/lighthouse/docs/checks.md" light one 900 860
  shot outline-light "$SHOTS/lighthouse/runbooks/incidents.md" light rose-pine 1100 760 MARKVIEW_OUTLINE=1
  shot outline-dark "$SHOTS/lighthouse/runbooks/incidents.md" dark rose-pine 1100 760 MARKVIEW_OUTLINE=1
  shot folder-light "$SHOTS/lighthouse" light rose-pine 980 660 MARKVIEW_OUTLINE=1 MARKVIEW_LINK=runbooks/incidents.md
  shot folder-dark "$SHOTS/lighthouse" dark rose-pine 980 660 MARKVIEW_OUTLINE=1 MARKVIEW_LINK=runbooks/incidents.md
  shot find-light "$SHOTS/lighthouse/docs/architecture.md" light github 900 640 MARKVIEW_FIND=SQLite
  shot quicklook-light "$SHOTS/lighthouse/README.md" light github 760 600
  shot quicklook-dark "$SHOTS/lighthouse/README.md" dark github 760 600
  shot settings-light "$SHOTS/themes.md" light paper 700 520 MARKVIEW_SETTINGS="$OUT/settings-window-light.png" MARKVIEW_SETTINGS_PANE=1
  shot settings-dark "$SHOTS/themes.md" dark paper 700 520 MARKVIEW_SETTINGS="$OUT/settings-window-dark.png" MARKVIEW_SETTINGS_PANE=1
fi

if [ "$only" = all ] || [ "$only" = themes ]; then
  for theme in github solarized one monokai dracula nord tokyo-night catppuccin gruvbox ayu rose-pine paper; do
    for appearance in light dark; do
      shot "themes/$theme-$appearance" "$SHOTS/themes.md" $appearance $theme 720 560
    done
  done
fi

# Lights the windows' traffic lights (each snapshot's window was in the background), then
# writes WebP copies for the page into site/public/shots.
LIGHTS=build/site-lights
[ "$LIGHTS" -nt site/shots/lights.swift ] || swiftc -O site/shots/lights.swift -o "$LIGHTS"
ASSETS=site/public/shots
mkdir -p "$ASSETS/themes"
for png in "$OUT"/*.png "$OUT"/themes/*.png; do
  name=${png#"$OUT"/}
  name=${name%.png}
  case $name in
    quicklook-*-page) cp "$png" "$OUT/lit.png"; name=${name%-page} ;;   # Quick Look shows the page alone
    quicklook-*) continue ;;
    *-page) continue ;;                          # the page alone, kept for comparing
    settings-window-*|find-*) cp "$png" "$OUT/lit.png" ;;   # already lit, or a panel
    *) "$LIGHTS" "$png" "$OUT/lit.png" ;;
  esac
  cwebp -quiet -q 86 -m 6 "$OUT/lit.png" -o "$ASSETS/$name.webp"
done
rm -f "$OUT/lit.png"
