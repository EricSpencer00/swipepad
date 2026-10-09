#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP=dist/Swipepad.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Swipepad "$APP/Contents/MacOS/Swipepad"
cp ThirdParty/* "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Swipepad</string>
<key>CFBundleIdentifier</key><string>com.ericspencer00.swipepad</string>
<key>CFBundleName</key><string>Swipepad</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf 'Built %s (unsigned, not notarized)\n' "$APP"
