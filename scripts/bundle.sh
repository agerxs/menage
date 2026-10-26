#!/usr/bin/env bash
# Construit build/Menage.app (release, signature ad hoc).
#   scripts/bundle.sh            → build/Menage.app
#   scripts/bundle.sh --install  → copie aussi dans ~/Applications et relance l'app
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="0.1.0"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="build/Menage.app"

swift build -c release --product Menage
BIN="$(swift build -c release --show-bin-path)/Menage"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Menage"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>        <string>dev.ager.menage</string>
    <key>CFBundleName</key>              <string>Ménage</string>
    <key>CFBundleDisplayName</key>       <string>Ménage</string>
    <key>CFBundleExecutable</key>        <string>Menage</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key>           <string>${BUILD_NUMBER}</string>
    <key>CFBundleDevelopmentRegion</key> <string>fr</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "OK : $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x Menage 2>/dev/null || true
    rm -rf "$HOME/Applications/Menage.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/Menage.app"
    echo "Installé et lancé : ~/Applications/Menage.app"
fi
