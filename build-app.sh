#!/bin/bash
# Builds LightCodes.app (release) into ./dist. Requires Xcode 15+ / Swift 5.9+ on macOS 14+.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=dist/LightCodes.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/LightCodes" "$APP/Contents/MacOS/LightCodes"
# SwiftPM's default build system can record the deployment target as the SDK version,
# which makes macOS run the app in compatibility mode (no Liquid Glass). Record the real SDK.
vtool -set-build-version macos 14.0 "$(xcrun --show-sdk-version)" -replace \
      -output "$APP/Contents/MacOS/LightCodes" "$APP/Contents/MacOS/LightCodes"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>LightCodes</string>
  <key>CFBundleDisplayName</key><string>LightCodes</string>
  <key>CFBundleIdentifier</key><string>com.lightcodes.app</string>
  <key>CFBundleExecutable</key><string>LightCodes</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>LightCodes sends Art-Net to lighting nodes on your network.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP — drag it to /Applications."
