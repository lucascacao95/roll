# Building, testing and local distribution

## Verified toolchain

The project declares macOS deployment target **27.0**, Swift language version **6.0** and
complete strict concurrency checking. Release preparation uses macOS **27.0.1**, Xcode **27.0**
(build 27A266a), Apple Swift **6.4**, and the **arm64** destination.
The shared scheme is **PhotoImporter**, with app and hosted XCTest targets.
There are no Swift Package Manager, CocoaPods, Carthage or vendored dependencies.

The project does not explicitly restrict ARCHS, but only Apple Silicon execution is verified.
An isolated macOS 14 universal build probe succeeded; that is not advertised runtime support.
See [compatibility assessment](COMPATIBILITY.md); production deployment remains 27.0.
The packaging script explicitly builds arm64. Intel, universal builds and lower deployment targets
are not supported claims; evaluate them separately rather than changing the target for CI convenience.

## Build and run

From the checkout root:

```sh
xcodebuild -project PhotoImporter.xcodeproj -scheme PhotoImporter \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- clean build
open build/DerivedData/Build/Products/Debug/Roll.app
```

Ad hoc signing needs no developer account or provisioning profile. The sandbox, user-selected
folder access, app-scoped bookmarks and hardened runtime remain enabled.
Do not run old PhotoImporter.app and Roll.app simultaneously: they have the same bundle identity.

## Automated validation

```sh
./scripts/check.sh
```

This performs a clean build/test in pt-BR, the localization/identity tests in English, a normal
Debug build restoring production entitlements after hosted tests, and a Release build with strict
signature verification, plus a standalone production-scanner regression for /private/tmp aliases. Traditional tests contain Portuguese message assertions; running the whole
suite only in English is not an equivalent validation. Both languages share the same core code.

For the complete suite alone:

```sh
xcodebuild -project PhotoImporter.xcodeproj -scheme PhotoImporter \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/TestDerivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  clean test -testLanguage pt-BR -testRegion BR
```

Tests use temporary directories, generated JPEGs with controlled EXIF, synthetic RAW grouping files
and isolated UserDefaults. They exercise real copying, hashing and filesystem operations.
Injected capacity/identity readers and copy checkpoints simulate faults; they do not substitute
for hardware disconnection or real RAW decoding tests.

Coverage includes discovery/grouping, date/format selection, path collisions, overlap and symlinks,
source preservation, SHA-256, destination races, cancellation, disk-full errors, simulated disconnection,
journal failures, operation locks, interrupted recovery, temporary cleanup and bookmark identity.
Run tests as a normal user; root can bypass permission fixtures and invalidate the test assumptions.
Do not upload local build logs or xcresult bundles without reviewing them for private paths.

## CI

`.github/workflows/ci.yml` runs the same check script on pushes and pull requests, with read-only
repository permissions and no distribution, secrets or artifact uploads. Checkout is pinned to a
commit and does not persist its credentials. The runner label is `xcode-27`, with
`DEVELOPER_DIR=/Applications/Xcode_27.0.app/Contents/Developer` to match local verification.

Runner availability and the installed Xcode path were checked against GitHub's
[runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
and [Xcode 27 availability notice](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/).
Images may change; a removed toolchain should cause an explicit CI failure, not silently test an older OS.
The [first remote run](https://github.com/lucascacao95/roll/actions/runs/45623132133) passed on 2026-11-25, using Xcode 27.0 and Swift 6.4.
Push/CI authorization did not authorize public visibility, releases or binary distribution.
No larger runner or automatic release is configured.

## Release application and ZIP

```sh
xcodebuild -project PhotoImporter.xcodeproj -scheme PhotoImporter -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/ReleaseDerivedData \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
codesign --verify --strict build/ReleaseDerivedData/Build/Products/Release/Roll.app
# Optional local ZIP, only if the destination does not already exist:
test ! -e build/Roll-0.1.0-macOS-arm64.zip && \
  ditto -c -k --sequesterRsrc --keepParent \
  build/ReleaseDerivedData/Build/Products/Release/Roll.app build/Roll-0.1.0-macOS-arm64.zip
```

Release uses the bundle's version for About: marketing **0.1.0**, build **3**.
Build 3 follows earlier private builds without changing persisted data or permissions.

## Local DMG

```sh
./scripts/package-local.sh
```

This creates `build/releases/Roll-0.1.0-macOS-arm64.dmg`, its SHA-256 file and a local build log.
The script refuses to replace an existing image. Previous private DMGs may already exist;
preserve or rename them manually before packaging again. Never delete an installed app or archive
as part of packaging. `build/` is ignored by Git.

To install locally, quit Roll with no import running, open the DMG, drag Roll.app into Applications,
eject the image and launch it. Folder authorization may need to be renewed.

Ad hoc signing is neither Developer ID signing nor notarization. Other Macs may block a downloaded
build through Gatekeeper. No Gatekeeper bypass or system setting change is part of this project.
A later public binary process would need a separately approved Developer ID/notarization setup,
credentials and costs, or clearly documented unsigned distribution. Source publication is the priority.
ZIP/DMG creation alone does not make a build trusted by Apple. No certificate was used or requested here.
