# macOS and architecture compatibility assessment

Assessment: 2026-11-24. **Analysis only: committed project settings and supported requirements remain unchanged.**
Current deployment target is 27.0; verified normal execution/tests remain macOS 27.0.1 on arm64.

## Why 27.0?

The earliest tracked commit already sets MACOSX_DEPLOYMENT_TARGET=27.0 for both configurations.
No implementation comment or recorded technical requirement explains this exact minimum; it matches
the available development/validation environment. Do not attribute it to a proven Xcode default or
an indispensable import API. A successful lower-target build shows it is not a fundamental requirement.
Xcode/SDK version, Swift language mode and the app's minimum runtime OS are separate requirements.

## Evidence from isolated diagnostic builds

The following command was executed with command-line overrides and a separate ignored derived-data path.
No pbxproj, shared scheme, CI, package script, Info.plist source or production deployment setting was changed.

```sh
xcodebuild -project PhotoImporter.xcodeproj -scheme PhotoImporter -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/CompatibilityProbe \
  MACOSX_DEPLOYMENT_TARGET=14.0 ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
```

Result: **BUILD SUCCEEDED** using Xcode 27.0/macOS 27 SDK, without production-source changes.
`lipo -archs` reports **x86_64 arm64**. `vtool -show-build` reports **minos 14.0** for both slices.
The diagnostic bundle is ignored and is not a release candidate or a supported binary download.
It was built before the icon replacement and must not be distributed.

A separate arm64 probe with MACOSX_DEPLOYMENT_TARGET=13.0 failed as expected: compiler diagnostics
identify Observable, Bindable and ObservationRegistrar/Tracked/Ignored as macOS 14+ APIs.
Logs remain local at /tmp/roll-compatibility-probe.log and /tmp/roll-compatibility-13-probe.log.
No macOS 14/13 system was booted and no Intel or Rosetta execution was attempted.

## Practical minimum and API boundaries

**macOS 14.0 is the technically viable minimum for the current architecture without UI/state rewrites**, based
on the successful two-architecture build and the macOS 13 failure. This is a compile/deployment assessment,
not a statement that runtime, camera or filesystem behavior has already passed on macOS 14.

| API / feature used | Runtime boundary / effect |
| --- | --- |
| Observation: @Observable, @ObservationIgnored, ObservationRegistrar; SwiftUI @Bindable integration | macOS 14; used throughout DiscoveryModel, HistoryModel, AppPreferences, LibraryAccess and views. Main blocker below 14. |
| ContentUnavailableView | macOS 14; New Roll/discovery/history empty states require fallback views below 14. |
| New onChange(of:initial:) zero-argument closure | macOS 14; organization-change invalidation uses it. Earlier OS needs an older overload without changing invalidation behavior. |
| NavigationSplitView, ViewThatFits, modern Window scene | macOS 13; further UI alternatives needed below 13. |
| SwiftUI Table | macOS 12; lower targets would need a replacement for plan/result/detail tables. |
| Button title + systemImage convenience | SDK marks this overload as macOS 11+, not a macOS 14/27 blocker. |
| Task/actors, Foundation/ImageIO/AppKit, CryptoKit SHA-256 and app-scoped bookmarks | Available below 14 for the uses exercised by the successful build. They do not impose macOS 27. Swift 6 language mode does not itself require a 27 runtime. |
| renameatx_np / RENAME_EXCL | SDK header marks renameatx_np as macOS 10.12+. Never replace this with unsafe rename to gain OS/filesystem compatibility. Runtime filesystem support still must be checked. |

Availability was checked in installed SDK Swift interfaces/C headers and by compiler diagnostics.
Apple documents [SwiftUI Observation starting at macOS 14](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro).

## Changes and maintenance cost if approved later

For macOS 14, no availability fallback or import-engine rewrite was required to compile. A future milestone
would change deployment settings, README/scope/build/package requirements, and validate production bundle
metadata. Keep CI on a compatible toolchain; a newer host alone does not test an older runtime. Validate a
minimum-OS machine/VM and sandboxed pickers/bookmarks, UI, real-camera ImageIO, permissions, APFS/exFAT,
disconnection, checksums, cancellation, journal/recovery/cleanup before broad support claims.

Code/configuration cost is low; ongoing validation cost is moderate because older runtime bugs, RAW decoder
support and storage behavior must be tested across versions. Do not invent a time estimate without access
to the required test systems.

For macOS 13, changing Observation to ObservableObject/Published/StateObject/ObservedObject (or maintaining
two state paths) affects model/view ownership and observation/invalidation. Empty-state and onChange fallbacks
are also needed. This is materially larger maintenance and regression risk for a small app and is not recommended
for the initial release. Below 13 adds navigation/window/layout work; below 12 also changes table presentation.
No such changes were made.

## Universal Apple Silicon / Intel

A universal Release compiled successfully with explicit ARCHS='arm64 x86_64' and ONLY_ACTIVE_ARCH=NO.
There is no architecture-specific assembly, vendored binary or package dependency to port. This supports
technical feasibility, not an Intel runtime-support claim. Apple describes the
[two-slice universal build and validation model](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary).

A later universal distribution milestone would explicitly set architectures for packaging, update DMG/ZIP
names and requirements, verify both Mach-O slices and signatures, and run tests on both architectures and
supported OS versions. Rosetta testing (if already installed and approved) is useful but cannot replace
native Intel/storage validation. No Rosetta installation, certificate use or binary publication was performed.
The normal package script remains arm64 and current minimum OS remains 27.0.

## Safety implications and recommendation

Lowering the minimum to 14 does not require weakening original preservation, no-follow traversal,
exclusive temporary files, size/SHA-256 verification, fsync, no-replacement publication, root/volume identity,
locks or journal/recovery semantics. Keep every one of those checks. Fail closed on filesystems that do not
support safe finalization. Older OS/filesystem/decoder behavior remains a runtime stability risk until tested;
compile success cannot establish absence of data-loss risks.

Recommendation: consider **macOS 14 + universal** as a separate approved milestone after history/asset cleanup,
with minimum-OS and Intel validation as acceptance gates. Do not advertise that support or automatically
change deployment/packaging settings during publication preparation.
