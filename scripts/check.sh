#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# These settings require no Apple account, team or provisioning profile.
common=(-project PhotoImporter.xcodeproj -scheme PhotoImporter
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/CheckDerivedData
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-)
xcodebuild -version
xcrun swift --version
xcodebuild "${common[@]}" clean test -testLanguage pt-BR -testRegion BR
xcodebuild "${common[@]}" test -testLanguage en -testRegion US \
  -only-testing:PhotoImporterTests/BrandingLocalizationTests
# Restore normal Debug entitlements after hosted tests.
xcodebuild "${common[@]}" build
xcodebuild "${common[@]}" -configuration Release \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
codesign --verify --strict build/CheckDerivedData/Build/Products/Release/Roll.app
# The sandboxed XCTest host cannot create /private/tmp files. Run this targeted
# Foundation path-alias regression with production scanner code in a standalone process.
xcrun swiftc -swift-version 6 PhotoImporter/Localization.swift PhotoImporter/Photo.swift \
  PhotoImporter/PhotoMetadata.swift PhotoImporter/PhotoScanner.swift \
  scripts/tests/DiscoveryAlias.swift -o build/CheckDerivedData/discovery-alias-test
build/CheckDerivedData/discovery-alias-test
