#!/bin/bash
# Builds build/Markview.app. `./build.sh install` also copies it to /Applications
# and registers its Quick Look extension.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Markview.app
APPEX=$APP/Contents/PlugIns/MarkviewQuickLook.appex
OPENER=$APPEX/Contents/XPCServices/LinkOpener.xpc
TARGET="$(uname -m)-apple-macos14.0"

# Diagrams are drawn by MermaidKit (Vendor/MermaidKit) and math by SwaTex (Vendor/SwaTex).
# Each is built into shared libraries in Contents/Frameworks that the app and the
# extension both load, so they are in the app once. Building them takes a minute or two,
# so they are kept in build/modules and rebuilt only when their sources change.
MODULES=build/modules
build_module() {   # folder, module name, and the module it depends on, if any
  local sources=$1/$2 name=$2 lib="$MODULES/lib$2.dylib"
  if [ ! -f "$lib" ] || [ -n "$(find "$sources" -name '*.swift' -newer "$lib" | head -1)" ] \
     || { [ -n "${3:-}" ] && [ "$MODULES/lib$3.dylib" -nt "$lib" ]; }; then
    echo "Building $name"
    swiftc -O -wmo -num-threads 8 -parse-as-library -swift-version 6 -application-extension -target "$TARGET" \
      -module-name "$name" -I "$MODULES" -L "$MODULES" ${3:+-l$3} \
      -emit-module -emit-module-path "$MODULES/$name.swiftmodule" \
      -emit-library -Xlinker -install_name -Xlinker "@rpath/lib$name.dylib" -o "$lib" $(find "$sources" -name '*.swift')
  fi
}
mkdir -p "$MODULES"
build_module Vendor/MermaidKit MermaidLayout
build_module Vendor/MermaidKit MermaidRender MermaidLayout
build_module Vendor/SwaTex SwaTex
build_module Vendor/SwaTex SwaTexRender SwaTex
LIBRARIES=(MermaidLayout MermaidRender SwaTex SwaTexRender)
LINK="-I $MODULES -L $MODULES $(printf -- '-l%s ' "${LIBRARIES[@]}")"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" \
  "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources/vendor" "$OPENER/Contents/MacOS"
swiftc -O -target "$TARGET" $LINK -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$APP/Contents/MacOS/Markview" Sources/*.swift Native/*.swift
for library in "${LIBRARIES[@]}"; do cp "$MODULES/lib$library.dylib" "$APP/Contents/Frameworks/"; done
cp Info.plist "$APP/Contents/"
cp -R Resources/. "$APP/Contents/Resources/"
# SwaTex's KaTeX fonts, which the extension reads from the app too.
cp -R Vendor/SwaTex/SwaTexRender/Resources/Fonts "$APP/Contents/Resources/"

# The Quick Look preview (Space in Finder) is an app extension. It shows a
# document the same way the app does: with everything in Native/ except the
# window controller, and its own copy of the highlighter and emoji list.
swiftc -O -target "$TARGET" -application-extension -parse-as-library -module-name MarkviewQuickLook $LINK \
  -Xlinker -rpath -Xlinker @executable_path/../../../../Frameworks -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$APPEX/Contents/MacOS/MarkviewQuickLook" \
  Sources/Links.swift Sources/Outline.swift QuickLook/LinkOpening.swift Native/QuickLook/*.swift \
  $(ls Native/*.swift | grep -v ViewerWindowController)
cp QuickLook/Info.plist "$APPEX/Contents/"
cp Resources/vendor/* "$APPEX/Contents/Resources/vendor/"

# The extension's sandbox can't open links, so it carries a service that does.
swiftc -O -target "$TARGET" -o "$OPENER/Contents/MacOS/LinkOpener" \
  Sources/Links.swift QuickLook/LinkOpening.swift QuickLook/LinkOpener/main.swift
cp QuickLook/LinkOpener/Info.plist "$OPENER/Contents/"
codesign --force --sign - "$OPENER"
codesign --force --sign - --entitlements QuickLook/QuickLook.entitlements "$APPEX"

codesign --force --sign - "$APP/Contents/Frameworks"/*.dylib
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = install ]; then
  INSTALLED=/Applications/Markview.app
  rm -rf "$INSTALLED"
  cp -R "$APP" /Applications/
  # Replacing the app drops the extension's registration, and Quick Look runs
  # whichever copy is registered: make that the installed one, and only it.
  pluginkit -r "$APPEX" 2>/dev/null || true
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED"
  pluginkit -a "$INSTALLED/Contents/PlugIns/MarkviewQuickLook.appex"
  echo "Installed $INSTALLED"
fi
