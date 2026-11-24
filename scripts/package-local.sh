#!/bin/bash
set -euo pipefail

# Local, ad hoc signed build for Apple Silicon. No upload or notarization.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
release_build="$project_root/build/ReleaseDerivedData"
release_output="$project_root/build/releases"
mkdir -p "$release_output"

xcodebuild -project "$project_root/PhotoImporter.xcodeproj" \
  -scheme PhotoImporter -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$release_build" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build > "$release_output/build-release.log" 2>&1 || {
    tail -n 60 "$release_output/build-release.log"
    exit 1
  }

release_app="$release_build/Build/Products/Release/Roll.app"
codesign --verify --strict "$release_app"
release_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$release_app/Contents/Info.plist")
release_image="$release_output/Roll-$release_version-macOS-arm64.dmg"
if [[ -e "$release_image" ]]; then
  printf 'Arquivo já existe; preserve ou renomeie antes de gerar novamente: %s\n' "$release_image" >&2
  exit 1
fi

release_staging=$(mktemp -d "${TMPDIR:-/tmp}/RollPackage.XXXXXX")
trap 'rm -rf "$release_staging"' EXIT
ditto "$release_app" "$release_staging/Roll.app"
ln -s /Applications "$release_staging/Applications"
cat > "$release_staging/Installation.txt" <<'EOF'
Roll — From capture to collection.

Local installation / Instalação local

1. Quit Roll before installing, with no imports running.
2. Drag Roll.app to Applications.
3. Eject this image and open Roll from Applications.

Requires macOS 27 or later and an Apple Silicon Mac (M1 or later).
Locally signed build, without Apple Developer ID signing or notarization.
You may need to authorize your archive folder again.

1. Encerre o Roll antes de instalar, sem importações em andamento.
2. Arraste Roll.app para Applications (Aplicativos).
3. Ejete esta imagem e abra Roll pela pasta Aplicativos.

Requer macOS 27+ e Apple Silicon. Assinatura local, sem notarização da Apple.
O macOS pode pedir nova autorização para a pasta do acervo.
Os originais no cartão SD são sempre preservados pelo aplicativo.
EOF

hdiutil create -volname 'Roll' -srcfolder "$release_staging" \
  -format UDZO "$release_image"
hdiutil verify "$release_image"
(
  cd "$release_output"
  shasum -a 256 "$(basename "$release_image")" > "$(basename "$release_image").sha256"
)
printf '\nInstalador local: %s\n' "$release_image"
