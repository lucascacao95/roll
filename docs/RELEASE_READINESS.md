# Roll — first public release readiness

Audit date: **2026-11-24**. Proposed first public source release: **v0.1.0**, build **3**.

**Verdict: READY WITH KNOWN LIMITATIONS — awaiting final approval for public visibility.**

On **2026-11-25**, the maintainer authorized the exact-lease push and remote CI. The sanitized history was
pushed with an explicit lease on the previously verified b9be783 remote SHA. Remote main now contains
that sanitized history, and the repository remains **PRIVATE**. Normal local fetch/upstream tracking was
restored only after the successful push; the temporary negative main-fetch refspec was removed.

[First remote CI run](https://github.com/lucascacao95/roll/actions/runs/45623132133) **passed** on dfe07cd:
95 tests in pt-BR, 4 localization/identity tests in English, normal Debug and Release builds,
strict signature verification and the standalone discovery regression. The runner used Xcode 27.0 and
Swift 6.4. A nonblocking checkout-action Node 20 deprecation annotation remains; GitHub ran it with Node 24.
No application dependency or workflow change was made to silence this annotation.

No tags, releases, binaries or public-visibility change were published. Public visibility requires final
maintainer review. Historical caches/external copies and the documented manual/hardware limitations
remain outside the guarantees of this preparation. The following sections retain the audit evidence.

## Inspection and audit scope

Reviewed the root scope, previous README/branding documentation, production Swift files, tests, Xcode
project/shared scheme, entitlements/privacy manifest, localization, asset catalog, packaging script,
tracked files, both reachable commits, all branches/remotes and reachable historical file blobs.
GitHub CLI/API checks confirmed the existing destination and account; the follow-up private-visibility
restoration is recorded above. Audit scripts did not inspect/export personal photo content, real journals
or bookmark payloads. Hosted tests can perform normal app startup, including saved-access restoration;
test models/fault operations use isolated preferences and generated disposable fixtures, never a real archive.

Initial state: 63 tracked files, two commits, clean main tracking origin/main; no tags or other branches.
Historical inspection covered 60 unique blob versions (identical file contents share Git objects), commit
metadata and messages. The remote already exists and is private. No new remote needs to be created.

The local content scan searched private home paths, mounted-volume paths, common GitHub/OpenAI/AWS token
and private-key formats, email addresses, sensitive file types and generated outputs. This was a local
pattern/inspection audit, not a third-party secret-scanner certification. It cannot prove the absence of
all possible secrets. File lists, source/configuration review and image metadata inspection complement it.
No repository contents or private findings were submitted to an external scanning service.

## Privacy and publication findings

| Finding | Evidence / action | Status |
| --- | --- | --- |
| Personal Git author/committer identity | Both existing commits use the configured personal email; maintainer explicitly approved keeping the name/email public. No professional email found. | Accepted |
| Private home or actual mounted-volume paths | None found in reachable historical blobs or current publication candidates. Generic fixture paths and toolchain paths are intentional. | Pass within scan scope |
| Credentials/signing material | No matching tokens, private keys, provisioning profiles, team ID or bundled certificates found. DEVELOPMENT_TEAM is empty; signing is ad hoc. | Pass within scan scope |
| Original scope's hardware context | Historical scope mentions a camera model and nonunique storage capacities. Current scope removes machine-specific context; old text remains in history. No serial numbers, volume UUIDs or real import data found. | Documented |
| Legacy bundle identifier | local.lucas.PhotoImporter intentionally remains for sandbox, preferences and bookmark compatibility. It is not a credential; changing it would risk data/access continuity. | Accepted compatibility choice |
| Personal photographs / EXIF / GPS | The original pre-cleanup history contained only icon PNGs; sanitized local image history now uses the original repository artwork. Current tree has 11 original icon PNGs and seven generated native captures, including About. Final metadata inspection found no GPS, serial, artist, owner, user-comment, IPTC or MakerNote fields. Legacy icon EXIF was dimensions/color only. | Pass within metadata inspection scope |
| Local imports/bookmarks/preferences | No real records, bookmark payloads or user defaults files are tracked. Tests construct their own state. App records do contain private paths at runtime and must remain local. | Pass |
| Ignored generated files | Existing local DMGs/build products stay under ignored build/. Expanded ignore rules protect logs, app bundles, caches, personal Xcode state, signing material and local data. No existing tracked build/user-state file needed removal. | Corrected |
| Current icon origin and rights | Replaced all native slots and the README preview with original Core Graphics geometry defined in scripts/GenerateAppIcon.swift. No input images/external artwork. Source and outputs covered by approved MIT. | Resolved in current tree |
| Historical icon bytes | Approved replacement completed locally: seven old blobs absent from all reachable refs and the cleaned object database; metadata/code invariants verified. Original remote/backup copies remain private and excluded from publication. | Resolved locally; remote update gated |
| Repository visibility | Found PUBLIC on follow-up, restored PRIVATE under explicit instruction, confirmed via API and SSH remote SHA. Unknown earlier exposure; cannot revoke external copies. | Contained; residual exposure documented |

Audit only covers reachable history/current candidates. Before publication, review any newly added branches,
tags, artifacts or release attachments. Ignoring a file does not remove an already tracked historical copy.
No history rewrite is necessary for the approved Git identity. The approved narrow icon-blob replacement
was completed locally and verified as documented in ICON_MIGRATION.md. Any push needs separate approval.

## Operational safety and code quality

The reviewed import protocol retains read-only source opens, no-follow descriptor traversal, root/volume
identity checks, exclusive temporary files, mandatory size and SHA-256 verification, synchronization,
no-overwrite rename, durable local journal states and operation locks. A matching name, size or history
entry alone never proves a duplicate. Recovery rechecks actual content and keeps recorded destinations.
Temporary cleanup is explicit and restricted to recorded, revalidated ownership; unknown and linked files
are preserved. No safety check was weakened for this preparation.

Concrete issue corrected: Foundation enumeration can return /private/tmp while a standardized root is /tmp,
causing valid files to be silently skipped by a prefix check. Enumerated URLs now use the same standardization.
A standalone regression using the production scanner verifies relative paths, file discovery and unchanged
source bytes in that actual location. It runs outside the app because the sandboxed XCTest host correctly
refused arbitrary /private/tmp writes in the first attempted fixture. Sandbox permissions were not expanded.

Added XCTest coverage injects ENODEV after a real copied chunk. It verifies that the operation stops,
remaining files stay pending, no final/temporary file remains, source snapshots match and retry succeeds.
Existing tests already cover ENOSPC, source changes, corrupt copies, rename-time competitors, symlink swaps,
journal failure, partial pairs, cancellation and recovery. No extensive refactor or unrelated feature was added.

No TODO/FIXME, print/NSLog debug logging, fatalError/try! or network client was found in production Swift.
No Swift compiler warnings were found in the final validation log. Xcode reports optional App Intents
metadata extraction skipped (there is no AppIntents dependency); the test host also reports system
AutoShortcut service diagnostics. These did not fail builds/tests. Do not treat them as validated app features.
Safe fallback/error handling and owned-descriptor cleanup remain in place; resource-leak instrumentation
and full performance profiling were not run.

Main-actor UI state delegates discovery, image decoding, planning and file copy/hash loops to actors.
Bookmark restoration, UserDefaults and volume metadata queries still perform synchronous main-actor work;
slow/unresponsive storage can stall UI and should be profiled before broader use. No claim of fully
nonblocking storage access or formal concurrency verification is made.

## Build and test evidence

Reran `./scripts/check.sh` in the sanitized isolated clone successfully, exit status 0, on macOS **27.0.1** (26A434), Apple Silicon **arm64**,
Xcode **27.0** (27A266a), Apple Swift **6.4**, macOS 27 SDK and Swift 6 language mode.

| Check | Actual result |
| --- | --- |
| Clean Debug build + entire XCTest suite, pt-BR/BR | 95 tests, 0 failures |
| Identity/localization suite, en/US | 4 tests, 0 failures |
| Normal Debug build after hosted tests | BUILD SUCCEEDED |
| Release build without injected test entitlements | BUILD SUCCEEDED |
| Strict Release signature check | codesign --verify --strict passed |
| Standalone /private/tmp scanner regression | PASS; relative paths and source bytes preserved |
| Demo harness build and execution | Seven native captures including About/new icon; 12 generated files copied/verified plus one progress-copy file |
| macOS 14 universal diagnostic | Release compile/link succeeded with arm64 + x86_64 and minos 14.0 in both slices; analysis-only override, not runtime support validation |
| macOS 13 diagnostic | Expected availability failure in Observation/Bindable; no source/configuration changes to bypass it |
| Xcode project, manifest, entitlements, shared scheme/catalogs | Parsed successfully; bundle/catalog tests passed |
| Workflow | YAML/local validation passed; remote run 45623132133 passed on 2026-11-25 |
| Shell scripts and whitespace | bash -n and git diff --check passed |

The compiled Release is thin **arm64**, Roll.app / executable Roll, version **0.1.0 (3)**, minimum macOS **27.0**,
with AppIcon metadata/resources and both en/pt-BR localizations. Its signature is ad hoc, has no signing team,
and inspection shows the runtime flag plus sandbox, user-selected read/write and app-scope bookmark
entitlements, without get-task-allow or temporary test access exceptions. About reads its version from the bundle.

Local full-check log: /tmp/roll-clean-history-check.log (not committed; contains machine paths).
Generated build/results stay in ignored build/CheckDerivedData. Initial failed fixture log is also local;
only the final corrected script run is counted as passing. Do not upload raw logs or xcresult bundles blindly.
Build reproducibility here means source + documented toolchain + shared scheme + no unpinned package dependencies;
it does not mean byte-identical signed bundles across machines.

Not verified: Intel/universal execution (compile/link only), older macOS runtime, all camera models/filesystems, device power loss,
forced kill during writes, real unplug during copying, permission revocation and full accessibility interaction.
Fault checkpoints simulate error paths over real files; they do not certify hardware fault behavior.

## Follow-up audit evidence

The final local scan examined **89 current publication candidates** and **60 unique reachable historical blob
versions**. It found no private home paths, literal mounted personal-volume paths, matching common token/key
formats or non-asset email strings in file contents. Personal name/email in commit metadata remain explicitly
approved. Pattern scans are limited; no external scanner or reverse-image service was used.

All **18 current PNGs** (11 new icon/source files and 7 captures) and the 11 legacy icon files in the ignored
backup decoded through ImageIO without detected GPS, serial, artist, owner, user-comment, IPTC or MakerNote
fields. No old-image blob exists in current publication files. The newly approved history cleanup removes all
seven from every local reachable ref and the cleaned object database; original remote/backup copies remain private. Initial scan details are in ignored build/IconAudit/final-privacy-audit.json; post-rewrite verification is
in build/IconAudit/clean-history-audit.json, with the history map stored separately from the publication refs.

Regenerating the new icon reproduced all eleven PNG checksums on this toolchain. Rebuilt normal Release and
demo bundles share the new compiled icon fingerprint, different from the old one. Existing old DMGs remain
unchanged. The production Release still declares minimum macOS 27.0, while only the diagnostic universal
bundle declares 14.0. Repository API now confirms PRIVATE, disabled=false and zero listed forks; that does
not establish absence of previous downloads/clones. Remote main is unchanged.

## Documentation, screenshots, assets and licensing

- README is now a concise English product presentation: icon, tagline, origin, features, actual native
  captures, import flow, requirements, build, limits, philosophy and license status.
- Root PROJECT_SCOPE.md stays the source of truth, now English and free of machine-specific setup details.
  It was not moved, avoiding broken instructions and links.
- docs/IMPORT_GUIDE.md preserves detailed behavior previously crowding the README.
- docs/ARCHITECTURE.md and BUILDING.md describe real components, integrity/access/persistence, testing,
  CI and local app/ZIP/DMG distribution. Branding and asset provenance are documented separately.
  COMPATIBILITY.md records the minimum-OS/universal assessment without changing supported targets;
  ICON_MIGRATION.md records complete old-asset occurrences and the history plan.
- CONTRIBUTING.md, SECURITY.md and AGENTS.md protect future changes and sensitive reports.
- CHANGELOG.md prepares unreleased 0.1.0 from implemented behavior only. Build 3 increases past private
  builds; no public version/tag/release exists. Local older DMGs are preserved, not overwritten/rebranded.
- MIT code/documentation license and Lucas Cacao Souza copyright holder were explicitly approved.
  Canonical reference: [MIT](https://opensource.org/license/mit). Current original icon code/outputs are included;
  the grant does not assert rights in the superseded attachment retained in private legacy backups/caches. No external packages,
  fonts or vendored libraries require new dependency notices.
- docs/screenshots contains seven native production-view captures in an isolated harness, using original
  code-generated illustrations and actual imports. They are labeled as view captures without window chrome,
  not screenshots of a shipped release or real camera photographs. Source/harness and manual instructions
  are included; no mockup is presented as real app output.

## GitHub and name review

Verified `gh` is installed/authenticated with active personal account **lucascacao95**. Repository owner type
is **User**, not an organization. Existing repository: **lucascacao95/roll**, private, default branch **main**,
origin using SSH. Local Git email is personal, and matches both author and committer in both existing commits.
No global Git configuration was changed. Preparation and the cleanup report are committed locally with the approved personal email. The authorized exact-lease remote update and first passing CI are recorded above.
The follow-up visibility restoration is explicitly recorded above; the earlier private-state snapshot was stale.

Prepared metadata (not applied remotely):

- Name: roll (already exists).
- Description: A native macOS app for importing, organizing and preserving photographs. Built for photography enthusiasts, inspired by analog photography.
- Topics: macos, swift, swiftui, photography, photo-importer, raw-photography, photo-management, macos-app, open-source, file-management.
- Visibility: private now; public only after final approval; the local/branch-history asset gate is resolved.
- License: MIT for current code/documentation/original art; superseded art removed from local and advertised remote main history.
- Default branch: main. Initial release: v0.1.0, still unreleased.

Preliminary public-name search found other photography products using Roll, including
[Roll: Shared Photo Albums](https://apps.apple.com/us/app/roll-shared-photo-albums/id6802082212) and
[Roll Disposable Camera](https://apps.apple.com/gb/app/roll-disposable-camera/id6759272118).
The account-scoped GitHub name already exists for this project; that is distinct from trademark,
commercial or domain availability. No trademark clearance or legal exclusivity is claimed. Assess potential
confusion before commercial distribution; no rename or paid legal work was initiated.

## Remaining gates and checklist

| Priority | Item | Closure criterion |
| --- | --- | --- |
| RESOLVED | Local historical icon cleanup | Explicit approval received; seven blobs replaced, commit metadata/code preserved, local object/ref checks and sanitized-clone validation passed. |
| APPROVAL | Public visibility | Private push/CI were authorized and completed; final public visibility still requires explicit maintainer approval. Tags/releases/binaries remain separate decisions. |
| RESOLVED | First remote CI | [Run 45623132133](https://github.com/lucascacao95/roll/actions/runs/45623132133) passed on dfe07cd; real tests/build/signature checks, not an inferred result. |
| OPTIONAL | Checkout action runtime | GitHub emitted a Node 20 deprecation annotation and forced checkout v4 onto Node 24. The run passed; review the pinned checkout version during routine CI maintenance. |
| IMPORTANT | Private security reporting | Enable GitHub private vulnerability reporting before public launch, or confirm the documented private contact channel works. |
| IMPORTANT | Manual UI/accessibility | Verify folder pickers, navigation, focus/keyboard/VoiceOver, selection/scrolling and recovery transitions in both appearances. |
| IMPORTANT | Hardware faults | Use disposable media/fixtures for drive removal, permission revocation and abrupt termination; inspect copies/journals before claiming coverage. |
| IMPORTANT | Name confusion | Review existing Roll photography names; do not equate GitHub ownership with brand exclusivity. |
| OPTIONAL | Artistic refinement / full-window screenshots | Review the new original icon visually; keep the documented MIT provenance. Full-window captures can replace labeled native-view captures later. |
| OPTIONAL | Wider compatibility/performance | Assessment complete: macOS 14 + universal compiles; macOS 13 blocked by Observation. Runtime support needs a separately approved validation milestone. Deployment remains 27.0. |
| OPTIONAL | Public binary | Decide separately on Developer ID, notarization, costs, Gatekeeper messaging and ZIP/DMG assets. |

Before publication: review the completed historical icon cleanup; review the new art and current diff; rerun validation
after any source/asset changes; verify local Git identity; approve remote actions; run CI; enable private
reporting; review public README/license/rendered links; only then approve visibility change. No automatic
release, binary distribution, paid service or certificate use is configured.

## Publication sequence — current status and remaining approval

The initial cleanup required the precise [ICON_MIGRATION.md](ICON_MIGRATION.md) exact-lease update;
a new tip commit alone would not have removed the old history. That update is now complete. Subsequent
changes use ordinary commits/pushes on sanitized main; do not repeat the historical force-push procedure.

1. Review the new artwork, final diff, approved personal Git identity and validation evidence.
2. Completed: explicit authorization, private backup, isolated seven-blob replacement, exact metadata/code
   comparisons and checks of every reachable ref/current files. No unrelated source changes were introduced.
3. Completed on 2026-11-25: authorized exact-lease push while PRIVATE; the expected old SHA matched.
4. Completed: the actual first GitHub CI run passed. Documentation updates are also checked by the same workflow.
5. Stop for maintainer review after passing CI. Public visibility requires explicit final approval.
6. Tags, GitHub releases and binaries are separate decisions and are not automatic outcomes of any prior approval.

Read-only checks useful before the authorized push:

```sh
git status --short
git diff --check
git config --local user.email
git log --all --format='%h %ae %ce %s'
gh repo view lucascacao95/roll --json visibility,nameWithOwner
git ls-remote origin refs/heads/main
./scripts/check.sh
```

After the approved push, inspect the real CI run rather than inferring its status:

```sh
gh run list --repo lucascacao95/roll --limit 5
# gh run watch RUN_ID --repo lucascacao95/roll --exit-status
```

Topics/description/private reporting remain prepared but unapplied. Do not publish an old local DMG;
the 0.1.1 image still contains the supplied icon and all existing packages are local-only.

## Compatibility conclusions — no target change

See [COMPATIBILITY.md](COMPATIBILITY.md) for APIs, exact diagnostic commands and maintenance implications.
The first tracked configuration already used 27.0 without a documented technical reason. Current code
builds unchanged with minimum 14.0 for both architectures; 13.0 fails on Observation/Bindable. ContentUnavailableView
and the zero-argument onChange also impose 14; navigation/layout features impose 13 below that.

Adopting 14 has low source/configuration cost, but moderate runtime-testing/maintenance cost. Supporting 13
would require observation/state and UI fallbacks and is not recommended for this release. Neither 14 nor
universal compilation requires weakening import checks. Older OS/Intel/volume behavior remains unvalidated
at runtime. No production deployment, architecture, CI runner or packaging setting was changed by this analysis.

## Files changed

Existing: .gitignore; PROJECT_SCOPE.md; README.md; docs/BRANDING.md; PhotoImporter/BrandIdentity.swift (comment only);
all ten AppIcon PNGs; removed superseded docs/branding/roll-provisional-source.png from current tree;
PhotoImporter.xcodeproj/project.pbxproj (version/build only); PhotoImporter/PhotoScanner.swift;
PhotoImporterTests/ImportTests.swift.

New: LICENSE; CHANGELOG.md; CONTRIBUTING.md; SECURITY.md; AGENTS.md;
.github/workflows/ci.yml; docs/ARCHITECTURE.md; docs/ASSETS.md; docs/BUILDING.md;
docs/IMPORT_GUIDE.md; docs/ICON_MIGRATION.md; docs/COMPATIBILITY.md; this report;
docs/branding/roll-icon.png; docs/screenshots/README.md and seven PNGs; scripts/GenerateAppIcon.swift;
scripts/check.sh; scripts/capture-demo.sh; scripts/demo/DemoCapture.swift;
scripts/tests/DiscoveryAlias.swift.

Intentionally unchanged: Bundle Identifier, internal module/target/scheme names, source/archive layout rules,
bookmark and preference formats, persisted raw values, JSON schema versions, journal path, safe-copy engine,
user original files and import behavior. Icon pixels were replaced with original art; historical image
blobs were replaced under explicit approval, preserving all commit metadata and non-image trees. The earlier
visibility restoration was followed by the explicitly approved exact-lease private push on 2026-11-25.
No public visibility, tags, releases or binary uploads were performed.

## Authorized history cleanup verification

The two development commits are retained as a3af6e0 (formerly 7ca1cd0) and 9ab4ae7 (formerly b9be783).
The preparation commit is aba477f (formerly 5928c79); its final tree is byte-identical before/after filtering.
Only the eleven historical icon paths changed. Messages, author/committer names, approved personal email,
author/committer timestamps and file modes were compared exactly. Seven old blobs are not reachable and
cannot be loaded from the clean object database. git fsck passed. The complete map is in ICON_MIGRATION.md.

An offline verified bundle, original Git directory and working-tree snapshot are stored outside publication
refs in a separate private backup. The publication repository has no backup/replace/old-origin ref containing those blobs. The origin URL
is unchanged and origin/main now tracks the sanitized remote after the authorized push.

A real remote CI result is now available: [first passing run](https://github.com/lucascacao95/roll/actions/runs/45623132133). Final public approval is still
required, and this cannot remove copies from earlier external downloads or GitHub caches.

### Local fetch safeguard — completed

The temporary negative main-fetch refspec protected the old remote-history interval. After the approved
exact-lease push succeeded, that single negative refspec was removed, main was fetched and upstream
tracking restored to origin/main. Both refs point into the sanitized history. No global configuration changed.

Post-rewrite validation passed on the clean serialized checkout: **95 XCTest cases**, **4 English
localization cases**, the standalone /private/tmp regression, Debug/Release builds and strict Release
signature verification. The privacy scan before the documentation status commit covered 94 reachable
unique blob versions and 89 current files; no configured token/key, private home/volume path or file-content
email pattern matched. All commit author and committer emails are the approved personal address.
The seven old blob IDs are absent from both reachable refs and the clean object database.
