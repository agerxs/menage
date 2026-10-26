#!/usr/bin/env bash
# Construit build/Menage.app (release) et la signe.
#   scripts/bundle.sh            → build/Menage.app
#   scripts/bundle.sh --install  → copie aussi dans ~/Applications et relance l'app
#
# Signature : le certificat « Developer ID Application » s'il existe, sinon « Apple Development »,
# sinon ad hoc. Avec un vrai certificat, macOS reconnaît l'app d'une version à l'autre et garde ses
# autorisations (Téléchargements, accès complet au disque, notifications, ouverture à la session).
# MENAGE_SIGN_IDENTITY="…" force une identité précise.
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

identity="${MENAGE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identities="$(security find-identity -v -p codesigning)"
    for kind in "Developer ID Application" "Apple Development"; do
        identity="$(grep -m1 -o "\"$kind: [^\"]*\"" <<<"$identities" | tr -d '"' || true)"
        [[ -n "$identity" ]] && break
    done
fi

if [[ -n "$identity" ]]; then
    # Runtime renforcé : exigé pour la notarisation, sans effet gênant pour une app sans greffon.
    codesign --force --options runtime --timestamp=none --sign "$identity" "$APP"
    echo "OK : $APP, signée par « $identity »"
else
    codesign --force --sign - "$APP"
    echo "OK : $APP, signature ad hoc (aucun certificat trouvé : macOS redemandera les autorisations à chaque mise à jour)"
fi

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x Menage 2>/dev/null || true
    # Attendre la fin de l'ancienne instance : sinon `open` échoue (erreur -600).
    for _ in $(seq 1 50); do pgrep -x Menage >/dev/null || break; sleep 0.1; done
    rm -rf "$HOME/Applications/Menage.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/Menage.app"
    echo "Installé et lancé : ~/Applications/Menage.app"
fi
