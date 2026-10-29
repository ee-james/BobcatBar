#!/bin/bash
## @file    build.sh
## @author  James Zeman
## @date    9 SEP 2026
## @brief   Builds BobcatBar and assembles an ad-hoc signed menu-bar .app bundle
##          (no restricted entitlements, so ad-hoc signing is fine).
##
## @param   release|debug   build configuration (default release).
## @param   --install       replaces $INSTALL_DIR/<App>.app and relaunches it if it was
##                          running. INSTALL_DIR defaults to ~/Applications; set it in
##                          build.local (git ignores it) to install somewhere else.
## @param   --release       builds for Apple silicon and Intel, signs with your Developer ID
##                          (hardened runtime), notarizes, staples, and zips it to
##                          build/BobcatBar-<version>.zip for a GitHub release. Needs a
##                          "Developer ID Application" certificate in the keychain and a
##                          notarytool profile (NOTARY_PROFILE, default "notary"), made once with
##                          xcrun notarytool store-credentials notary --apple-id <id> --team-id <team>
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BobcatBar"
BUNDLE_ID="com.zetsystems.bobcatbar"
VERSION="0.1.0"
CONFIG=release
INSTALL_DIR="$HOME/Applications"
[[ -f build.local ]] && source build.local
NOTARY_PROFILE="notary"
INSTALL=0
RELEASE=0
for arg in "$@"; do
  case "$arg" in
    release|debug)     CONFIG="$arg" ;;
    --install|install) INSTALL=1 ;;
    --release)         RELEASE=1; CONFIG=release ;;
    *) echo "usage: $0 [release|debug] [--install] [--release]" >&2; exit 1 ;;
  esac
done

if (( RELEASE )); then
  IDENTITY="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
  if [[ -z "$IDENTITY" ]]; then
    echo "no Developer ID Application certificate in the keychain (Xcode > Settings > Accounts > Manage Certificates)" >&2
    exit 1
  fi
  ARCHS=(--arch arm64 --arch x86_64)
else
  ARCHS=()
fi

echo "▸ swift build -c $CONFIG ${ARCHS[*]:-}"
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/$APP_NAME"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp icon/BobcatTemplate.png     "$APP/Contents/Resources/"
cp icon/BobcatTemplate@2x.png  "$APP/Contents/Resources/"

# app icon (Finder, About): the Icon Composer file compiles to Assets.car plus an .icns for older macOS
xcrun actool "$PWD/icon/AppIcon.icon" --compile "$PWD/$APP/Contents/Resources" --app-icon AppIcon \
  --platform macosx --minimum-deployment-target 14.0 --target-device mac \
  --output-partial-info-plist "$PWD/build/icon-partial.plist" >/dev/null   # actool needs absolute paths

BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"   # only goes up; Sparkle compares it

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>$VERSION</string>
  <key>CFBundleVersion</key>         <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>        <string>AppIcon</string>
  <key>CFBundleIconName</key>        <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <key>LSUIElement</key>             <true/>
  <key>NSHumanReadableCopyright</key> <string>© 2026 James Zeman. MIT License.</string>
</dict>
</plist>
PLIST

if (( RELEASE )); then
  echo "▸ codesign ($IDENTITY)"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  echo "▸ codesign (ad-hoc)"
  codesign --force --sign - --timestamp=none "$APP"
fi
codesign --verify --verbose=1 "$APP"

echo "▸ built $APP"

if (( RELEASE )); then
  ZIP="build/$APP_NAME-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "▸ notarizing (a few minutes)"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"   # again, with the ticket stapled
  spctl --assess --type execute --verbose "$APP"
  echo "▸ $ZIP is ready: gh release create v$VERSION $ZIP"
fi

if (( INSTALL )); then
  DEST="$INSTALL_DIR/$APP_NAME.app"
  WAS_RUNNING=0
  if pgrep -xq "$APP_NAME"; then
    WAS_RUNNING=1
    pkill -x "$APP_NAME" || true
    for _ in {1..20}; do pgrep -xq "$APP_NAME" || break; sleep 0.25; done
  fi
  rm -rf "$DEST"
  mkdir -p "$(dirname "$DEST")"
  ditto "$APP" "$DEST"
  echo "▸ installed to $DEST"
  if (( WAS_RUNNING )); then open "$DEST"; echo "▸ relaunched"; fi
fi
