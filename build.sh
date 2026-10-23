#!/bin/zsh
# Build Mac Butler → build/MacButler.app
#   ./build.sh              ad-hoc signed (macOS asks for permissions again after each rebuild)
#   SIGN_ID="Apple Development: You (TEAMID)" ./build.sh   keeps permissions across rebuilds
# Optional local overrides (not committed): local.env  (APP_NAME, BUNDLE_ID, SIGN_ID)
set -e
cd "${0:a:h}"
[[ -f local.env ]] && source local.env
APP_NAME=${APP_NAME:-MacButler}
BUNDLE_ID=${BUNDLE_ID:-com.macbutler.app}
SIGN_ID=${SIGN_ID:--}
VERSION=$(cat VERSION 2>/dev/null || echo 0.1.0)
APP=build/$APP_NAME.app

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>Mac Butler</string>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Mac Butler listens for its wake word. Audio never leaves your Mac.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>On-device speech recognition turns your voice into text.</string>
<key>NSAppleEventsUsageDescription</key><string>To open and control apps when you ask.</string>
</dict></plist>
PLIST

echo "› compiling app"
swiftc -O -swift-version 5 Sources/MacButler/*.swift -o "$APP/Contents/MacOS/$APP_NAME" \
  -framework AppKit -framework AVFoundation -framework Speech -framework QuartzCore -framework ApplicationServices
echo "› compiling tools"
swiftc -O Tools/jax.swift -o "$APP/Contents/Resources/bin/jax"
swiftc -O Tools/butler.swift -o "$APP/Contents/Resources/bin/butler"
cp Tools/jclick Tools/jtype "$APP/Contents/Resources/bin/"
cp -R Resources/prompts "$APP/Contents/Resources/"
codesign --force --deep --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$APP" >/dev/null
echo "✓ $PWD/$APP ($VERSION, $BUNDLE_ID)"
