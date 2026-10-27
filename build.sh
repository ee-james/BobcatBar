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
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BobcatBar"
BUNDLE_ID="com.zetsystems.bobcatbar"
VERSION="0.1.0"
CONFIG=release
INSTALL_DIR="$HOME/Applications"
[[ -f build.local ]] && source build.local
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    release|debug)     CONFIG="$arg" ;;
    --install|install) INSTALL=1 ;;
    *) echo "usage: $0 [release|debug] [--install]" >&2; exit 1 ;;
  esac
done

echo "▸ swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp icon/BobcatTemplate.png     "$APP/Contents/Resources/"
cp icon/BobcatTemplate@2x.png  "$APP/Contents/Resources/"

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
  <key>CFBundleVersion</key>         <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <key>LSUIElement</key>             <true/>
  <key>NSHumanReadableCopyright</key> <string>James Zeman</string>
</dict>
</plist>
PLIST

echo "▸ codesign (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

echo "▸ built $APP"

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
