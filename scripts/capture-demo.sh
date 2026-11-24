#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --keep-fixtures ) ]]; then
  printf 'Usage: %s [--keep-fixtures]\n' "$0" >&2
  exit 2
fi
# No access to the installed app, its preferences, journals or external volumes.
output="$PWD/build/DemoCapture"
mkdir -p "$output/RollDemo.app/Contents/MacOS" "$output/RollDemo.app/Contents/Resources"
xcodebuild -project PhotoImporter.xcodeproj -scheme PhotoImporter \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$output/DerivedData" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build > "$output/build.log" 2>&1
resources="$output/DerivedData/Build/Products/Debug/Roll.app/Contents/Resources"
for item in Assets.car AppIcon.icns en.lproj pt-BR.lproj; do
  ditto "$resources/$item" "$output/RollDemo.app/Contents/Resources/$item"
done
cat > "$output/RollDemo.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RollDemo</string>
<key>CFBundleIdentifier</key><string>org.roll.demo-capture</string>
<key>CFBundleName</key><string>Roll Demo Capture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>NSAccentColorName</key><string>AccentColor</string>
</dict></plist>
PLIST
sources=()
for source in PhotoImporter/*.swift; do
  [[ "$source" == PhotoImporter/PhotoImporterApp.swift ]] || sources+=("$source")
done
xcrun swiftc -swift-version 6 "${sources[@]}" scripts/demo/DemoCapture.swift \
  -o "$output/RollDemo.app/Contents/MacOS/RollDemo" > "$output/compile.log" 2>&1
"$output/RollDemo.app/Contents/MacOS/RollDemo" "$output/screenshots" "$@" -AppleLanguages '(en)' -AppleLocale en_US
printf 'Generated captures: %s/screenshots\n' "$output"
