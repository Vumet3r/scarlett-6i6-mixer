#!/bin/bash
# Genera un .app con la app y el daemon empaquetado en Resources.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/fase-2-gui/dist/Scarlett 6i6 Mixer.app"

(cd "$ROOT/fase-1-daemon" && make >/dev/null)
(cd "$ROOT/fase-2-gui/scarlett-app" && swift build >/dev/null)

BIN="$ROOT/fase-2-gui/scarlett-app/.build/arm64-apple-macosx/debug/scarlett-app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/scarlett-app"
cp "$ROOT/fase-1-daemon/build/scarlett-daemon" "$APP/Contents/Resources/scarlett-daemon"
cp "$ROOT/fase-2-gui/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>scarlett-app</string>
    <key>CFBundleIdentifier</key><string>com.javierbleda.scarlett6i6</string>
    <key>CFBundleName</key><string>Scarlett 6i6 Mixer</string>
    <key>CFBundleDisplayName</key><string>Scarlett 6i6 Mixer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>0.3</string>
    <key>CFBundleVersion</key><string>0.3</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true
echo "OK: $APP"