#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP=${SWIPEPAD_BUILD_APP:-dist/Swipepad.app}
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Swipepad "$APP/Contents/MacOS/Swipepad"
cp ThirdParty/* "$APP/Contents/Resources/"
swift scripts/make-icon.swift Assets
iconutil -c icns Assets/Swipepad.iconset -o "$APP/Contents/Resources/Swipepad.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Swipepad</string>
<key>CFBundleIdentifier</key><string>com.ericspencer00.swipepad</string>
<key>CFBundleName</key><string>Swipepad</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>Swipepad</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
SIGN_IDENTITY=${SWIPEPAD_SIGN_IDENTITY:--}
codesign --force --sign "$SIGN_IDENTITY" --identifier com.ericspencer00.swipepad "$APP"
printf 'Built %s (not notarized; inspect signing with doctor)\n' "$APP"
