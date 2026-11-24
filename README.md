# Roll

**roll.** — *From capture to collection.*

A native macOS utility for importing photos from SD cards and folders into a conventional file archive.
English is the development language, with Brazilian Portuguese localization. Branding guidelines,
compatibility decisions and the direction for the final icon are documented in [docs/BRANDING.md](docs/BRANDING.md).
The product scope is defined in [PROJECT_SCOPE.md](PROJECT_SCOPE.md).

## Current status: Roll identity and localization

Version 0.1.1 includes the approved provisional icon: the first film cartridge image,
with all native sizes in `PhotoImporter/Assets.xcassets/AppIcon.appiconset`.
Finder, Dock and About use the same icon. The final artwork is still pending.

- Manual folder or card selection through the native picker, with a list of detected external volumes.
- Persistent defaults for format, imported-file filtering and folder organization.
- Default archive saved with an access bookmark and identity verification on reconnection.
- Recursive discovery of JPG, JPEG and RW2 files, including inside DCIM.
- One visual card per relative directory and filename stem, with RAW/JPEG indicators.
- Filename stems preserve case. Extensions are recognized without case sensitivity.
- JPG and JPEG files sharing a stem are both retained; grouping never discards a file.
- Asynchronous, orientation-aware thumbnails with serial decoding and a bounded cache.
- Preview attempts every JPEG in the group before trying RAW through ImageIO; failures use a placeholder.
- Per-file date reading, with one representative date per visual photo and an identified date source.
- Card selection, select-visible/clear actions, and photo, file and byte counts.
- Combined format and inclusive date-range filters.
- Read errors displayed alongside partial results.
- Cancellation and source switching; hidden files, packages and symbolic links are skipped.
- Archive folder selection, an optional event name and a per-file import preview.
- Checks for paths, existing files, conflicts, availability and free space.
- A read-only preview. The Import Roll button starts verified copying into the archive.
- Block-based copying, exclusive destination temporary files, SHA-256, finalization without overwriting and progress.
- Cancellation, individual RAW/JPEG results and retries that verify existing content.
- One local JSON record per operation, including state, root/volume identities and per-file results.
- Visual history showing recorded results and current destination checks by size and SHA-256.
- Recovery preparation after confirming source and archive, preserving paths and intact copies.
- Inspection and confirmed removal of temporary files with recorded identities, protecting active operations.
- A filter for files not yet imported into the archive, including partially imported pairs.

## Dates, filters and selection

Date priority applies to the entire group: EXIF `DateTimeOriginal`, EXIF `DateTimeDigitized`,
file creation and file modification. At the same priority, JPEG is preferred;
files of the same format are ordered by relative path. This allows RAW EXIF, for example,
to take precedence over a JPEG's creation date. Invalid dates are ignored and fallback dates
are identified on the card. The tooltip shows the time, date source and file used.

EXIF date and time are preserved as the camera's civil date/time values, without time zone conversion,
even when an EXIF offset is present. Filesystem dates use the Mac's local time zone at scan time.
The date filter compares Gregorian calendar days and includes both endpoints.
Photos without a valid date appear when date filtering is disabled and are hidden when it is enabled.
The initial range covers all available dates from the scan.

Format determines eligible files without splitting a pair into separate cards: 10 selected pairs
represent 10 photos/20 files with RAW + JPEG, or 10 photos/10 files with JPEG or RAW.
If a group contains both JPG and JPEG files, both remain eligible in JPEG mode.
The card's RAW/JPEG indicators show the available formats regardless of the filter.

Selection starts empty. Changing filters deselects photos that are no longer visible;
broadening a filter does not select them again. Switching sources clears selection and resets filters.
There is no hidden selection. All counts and sizes reflect eligible files.

### Not yet imported into this archive

After choosing an archive, enable **Not yet imported into this archive**. Roll reads local records,
calculates source SHA-256 checksums when candidate references exist, and verifies the content currently
at the destination. Only files with matching source and destination content are hidden. A matching name,
size or recorded success alone is insufficient. Errors, files without references, corrupt records,
and missing or changed files remain visible; verification notes appear below the filter.
There is no scan or catalog of the entire archive: verification uses recorded paths.

The filter works per physical file. If a pair's JPEG is intact but its RAW is missing, the card
remains visible with only RAW eligible in RAW + JPEG/RAW mode; it is hidden in JPEG mode.
Counts, sizes and planning consider only eligible files. The pair's original representative date
is retained even when filtering excludes its JPEG.

Verification runs when the filter is enabled and again before generating an import preview.
After external changes, use **Refresh Verification**. Files remain visible until they have been verified.
The displayed time identifies when verification occurred; external file changes are not monitored.

## Archive and import preview

Choose an existing folder through the archive selector. This folder is the archive root;
Roll does not add another `Fotografias` directory. Local folders are allowed for testing,
and the preview identifies internal or external volumes when that information is available.
The archive picker does not allow folder creation at this stage.

With photos selected, optionally enter an event name and click **Review Roll**.
The window shows each file's relative source, destination relative to the archive, format, size and state.
For example, with an archive already named `Fotografias` and an event named `Passeio`:

```text
Fotografias/2026/2026-11-21 - Passeio/RAW/P100001.RW2
Fotografias/2026/2026-11-21 - Passeio/JPEG/P100001.JPG
```

Without an event, the session folder contains only the date. A selection spanning multiple days creates
one folder per day. A pair uses the same representative date even when only RAW or JPEG is eligible.
Photos without a valid date are flagged without inventing a destination; deselect them to continue.

Original filenames are preserved. Leading and trailing event-name whitespace is trimmed, and unsafe or
incompatible names are rejected without automatically replacing characters. A conservative policy applies
to separators, control characters, trailing periods/spaces and length limits
(255 UTF-8 bytes per component; an event name can use up to 242 bytes to fit alongside the date).

Per-file states:

- **New:** the path was available when inspected.
- **Exists — verify:** a destination file exists; name and size do not prove a duplicate.
- **Needs attention:** a collision between selected files, symbolic link, inaccessible/incompatible path,
  missing date, or source file removed or changed in size since discovery.

Planning rejects a source and archive that are identical or nested inside one another, resolving ancestor
links and comparing path components. Overlap comparisons are conservative about case.
Links at the selected root or in existing destination components are blocked, including broken links.
Files occupying folder paths are also blocked. Destination names are compared using Unicode normalization
and the volume's case rules; if case sensitivity cannot be determined, comparisons are case-insensitive.

The estimated size includes all eligible files, including existing files, until their content is verified.
Unknown/insufficient space and read-only volumes are reported in the preview. Actual write access is not
tested during preview. The preview creates no test file or folder, reserves no space and changes no
destination metadata.

Changing selection, filters, event, source or archive discards the preview and cancels any calculation
in progress. Volume mount, unmount and rename events discard previous scans and previews;
choose the source again. Changes to files within a volume are not monitored. Importing revalidates
paths, permissions, identities and space. Planning does not calculate checksums or declare files
already imported.

## Importing and retrying

In a preview without unresolved issues, click **Import Roll**. Selection and controls are disabled during
the operation; you can cancel and follow the current file through the copy and verification stages.
The import service runs serially and is shared across application windows.

Before copying, Roll revalidates folder identities (device/inode), volume UUIDs when available,
source file presence, size, identity and change timestamps, overlap, and current capacity.
Changes since preview require a new scan/preview. Creating the actual temporary file tests write access;
permission, disconnection and space failures are recorded. Available space is also checked per file.
On retry, files that now exist are excluded from the copy-space estimate but still undergo content comparison.

Directories and files are accessed through descriptors with `O_NOFOLLOW`; source files are opened read-only.
An exclusive hidden temporary file is created in the final destination directory. Copying uses a 1 MiB buffer
and calculates the source SHA-256 checksum; writes are synchronized and the entire temporary file is read
again to compare size and SHA-256. Source and paths are revalidated before publishing the file with
`renameatx_np(RENAME_EXCL)`, which refuses to replace an existing name. There is no fallback to a rename
that could overwrite a file. If the filesystem does not support this finalization, the operation fails explicitly.
Directory synchronization is required before recording a file as copied.

Existing files are opened without following links. Roll compares source and destination sizes and full
SHA-256 checksums, checking that the files remained unchanged while being read. Matching content is recorded
as **Already Imported — content verified**; different content is a conflict, and the existing file remains
unchanged. Per-file failures allow partially imported pairs to be represented accurately. Serious I/O,
space or recording failures stop the operation; the summary distinguishes failed, cancelled and unstarted files.

**Verify and Retry** repeats the operation using the preview, revalidating existing files.
After changing the source, selection or organization, generate a new preview. Intact final files are not
copied again when their content matches the source. RAW files are copied as bytes: preview support is not
required. EXIF dates are preserved; source filesystem timestamps, permissions and additional attributes
are not replicated to the destination.

### Import records

Records are stored in the application container's Application Support directory under `PhotoImporter/Imports`,
with one versioned JSON file per operation. They are written atomically and synchronized before writing
to the archive, after verifying the temporary file and after publishing each file. Each record contains
paths, sizes, temporary filenames, SHA-256 checksums when available, states and errors. The operation ID
appears in its summary. There is no proprietary catalog in the archive. New records use version 2,
including source state, temporary-file identity and a link to the operation being resumed. Reading supports
versions 1 and 2 without silently rewriting older records. Local `.lock` files protect active operations
across windows and instances; the operating system releases locks when the process terminates.

A recording failure before copying prevents the operation. A failure after publication can leave an intact
final file with a pending/error state: retry checks actual content instead of relying on the record alone.

On cancellation or handled failures, Roll attempts to remove only the temporary file created by that operation.
Abrupt termination or disconnection can leave hidden `.photoimporter-<operation>-<index>.partial` files,
identified in the record without presenting them as complete final files. History identifies interrupted
new operations when the record is still running but its lock is no longer active.
Physical power loss has not been tested. Synchronization is not an absolute guarantee of device durability
and does not constitute an independent backup. Originals are never removed from the card.

## History, verification and recovery

Open **History** in the sidebar. Each operation shows its date, source, destination, photo/file counts,
and individual RAW/JPEG results. Corrupt records or records with unknown versions are reported without
hiding other records or modifying their JSON files.

Select an operation and use **Confirm Archive…** to grant access to the current folder. The volume UUID
and folder identity are checked; another drive or folder is not accepted merely because it has the same name.
When a stable UUID is available, a device identifier change after remounting does not prevent recognition
of the same folder/inode. Without sufficient identity information, write actions are blocked.

**Verify Destination** only reads files and does not require the card to be connected. The **Recorded result**
column preserves what happened during the operation; **Destination now** shows content as intact, missing,
different, without a reference checksum, or unavailable. A copy can be confirmed even if the process ended
after publication but before recording success. The verification time is displayed; refresh after external
changes. File presence alone is not treated as proof without SHA-256 verification.

To resume an import:

1. Confirm the source and archive through the native pickers.
2. Click **Prepare Recovery**. Original destination paths are preserved, and intact files are excluded
   from the new copy. The remaining source files are checked against recorded state/checksums.
   Changed sources, content conflicts and insufficient space are flagged as issues.
3. Click **Open Recovery Preview**, review the files, then click **Import Roll**.

Recovery creates a new operation linked to the previous one. The original result is not overwritten.
History provides navigation between attempts and can use checksums from linked recovery operations
when identities, sources and destinations match, always rereading the current destination. Cyclic or
excessively deep chains are handled conservatively without inferring content.

Older records without source state/checksums do not authorize automatic recovery of pending files:
scan the source again. Running version 1 records without a lock have unknown activity;
recovery and cleanup are blocked because they may belong to an older instance that is still active.
No copying starts automatically when the app launches or history opens.

### Recorded temporary files

With the archive confirmed, click **Inspect Temporary Files**. The list shows only the exact names expected
by the record. **Remove Verified Temporary Files** requests confirmation and revalidates identities before
removing anything. Only regular files with recorded identity, compatible size, the same recorded creation
time and no additional hard links are eligible. If the creation time is unavailable, the temporary file is
preserved. This avoids relying solely on an inode that the filesystem might have reused. Symbolic links,
unexpected names, files replaced after inspection and older temporary files without recorded identities
remain untouched. Final files and originals are never cleanup targets. Active operations are protected by locks.

If inspection or cleanup is cancelled, or a drive becomes unavailable, verify the destination again.
The default archive has persistent access. Source and archive confirmation in history remains explicit
and per operation before recovery or cleanup actions.

## Interface and navigation

The window uses a sidebar with **New Roll**, **History** and **Settings**, inspired by the supplied mockups.
New Roll displays source and destination cards, format/organization and event controls, a photo selection
grid with filters, and a fixed summary of photos, files and size. Content scrolls, and thumbnails continue
to load lazily. **Review Roll** opens the existing preview; copying requires confirmation through
**Import Roll** in that preview. Preview errors and cancellation are located alongside the primary action.

History displays cards with the date, session extracted from the recorded path, counts, source,
destination and actual state. Period and status filters are available. Opening a card preserves access
to content verification, folder confirmation, linked recovery attempts and confirmed temporary-file cleanup.
Cards use icons: photos are not automatically read without authorization to illustrate records.
The recovery transition closes the details before opening the preview in New Roll.

Settings contains sections for the archive, organization, format, already imported files and safety.
The date folder remains mandatory, the event is set per import, overwriting is unavailable and SHA-256
verification remains mandatory. Capacity figures come from the selected volume rather than fixed mockup
values; the footer identifies that capacity was checked at connection. Copying revalidates space and access.
Branding uses the `roll.` wordmark, amber accents and native semantic backgrounds. About Roll and Settings
are available from the application menu. The window starts at 1280 × 880 and can be resized down to 1040 × 740.

The user reported validating the previous manual workflow with a real card, SSD and RW2 files, including
reopening/reconnection and a large session. This confirmation applies to the workflow before the visual
reorganization; the new navigation and controls still need verification in the updated app.

## Settings and volumes

Open **Settings…** (⌘,) to choose the default archive, initial format (RAW + JPEG/RAW/JPEG),
initial not-yet-imported filter, and whether year and format folders are included. The date folder,
optional event and original filenames are always preserved. Initial defaults retain the previous layout.
Format and filter defaults apply to new scans; **Apply Defaults to Current Filters** updates the current session.
Organization applies to new previews; changes require recalculating the preview. Recovery preserves recorded paths.
Existing files remain subject to content comparison, without an option to silently overwrite them.

Settings use UserDefaults in the local application container. The archive is remembered through a
security-scoped bookmark with an app-scoped bookmark entitlement. At launch or reconnection, the bookmark
is resolved without mounting drives or showing automatic dialogs; the volume UUID, folder inode and creation
time are checked when available. Without a UUID, the device must also match.
A saved path is for display only and is never used to grant access or select another folder.
Stale bookmarks are renewed only after identity validation. If a bookmark is invalid, permission is missing,
or identity differs, choose the folder again. Renaming or moving a folder may require confirmation if the
native resolver cannot find the original folder. **Forget Folder** removes only the preference;
no archive files are deleted.

The source selection menu lists external/removable/ejectable volumes visible to the sandbox. Choosing one
opens the native picker at that volume to authorize the source. Manual folder selection remains available.
NSWorkspace monitors mounting, unmounting and renaming: the archive attempts to reconnect, and the previous
scan/preview is discarded, requiring source selection again. No event starts a copy.
During an import, the engine retains its own access and verification; access refresh is deferred until
completion, preserving the summary. Physical removal remains subject to manual validation.
Read/write access and availability are shown for the archive; capacity and required space are checked
in the preview and again during copying. Reconnection does not create a write-test file.

## Requirements and running

macOS 27+, Xcode 27+ and Swift 6. No external dependencies, Apple account or provisioning profile required.
The project uses local ad hoc signing and App Sandbox with read/write access to selected folders,
as required for the destination. Source access remains read-only and never creates, modifies, moves
or removes files on the card. Writing local records is rejected if their directory overlaps the source
or archive.
`PrivacyInfo.xcprivacy` declares local capacity and file metadata access according to the
[categories and reasons documented by Apple](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

Open `PhotoImporter.xcodeproj`, select the shared **PhotoImporter** scheme and run on your Mac.
Alternatively, from the repository root:

```sh
xcodebuild -project PhotoImporter.xcodeproj \
  -scheme PhotoImporter -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/PhotoImporterDerivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- test -testLanguage pt-BR -testRegion BR

xcodebuild -project PhotoImporter.xcodeproj \
  -scheme PhotoImporter -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/PhotoImporterDerivedData \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build

open /tmp/PhotoImporterDerivedData/Build/Products/Debug/Roll.app
```

A normal build after tests restores the normal entitlements: Xcode adds temporary access exceptions
when hosting tests in the app. Those exceptions are not part of the project's entitlements file.

## Local installer (DMG)

To generate a Release build for this Mac:

```sh
./scripts/package-local.sh
```

The project, target, scheme and module remain `PhotoImporter`; the product and executable are `Roll`.
The bundle identifier and `PhotoImporter/Imports` are unchanged, without data migration.
Do not run the old `PhotoImporter.app` and `Roll.app` simultaneously: they share the same identity.

The script builds for Apple Silicon (`arm64`), verifies the ad hoc signature and creates
`build/releases/Roll-0.1.1-macOS-arm64.dmg`, alongside its SHA-256 checksum and build log.
The `build/` directory is already ignored. Existing images are not overwritten: preserve or rename
the previous DMG before packaging again. No Apple account is required and no files are sent to Apple.

With no imports running, quit the open app. Open the DMG, drag `Roll.app` into **Applications**,
eject the image and open the installed app. Requires macOS 27+ and Apple Silicon.
The archive folder may need to be authorized again.

This image is for local installation. An ad hoc signature is not Developer ID signing or notarization;
distributing it to others may trigger Gatekeeper blocking. Notarized distribution requires your own
Apple Developer Program credentials and certificate, plus a separate signing/notarization process.
The script does not change the Mac's security settings.

## Validation

The 94 tests create and remove only their own temporary directories. They do not require a card or SSD.
Coverage includes recursion, formats, pairs and repeated names across directories, simultaneous JPG+JPEG,
case-sensitive filename stems, hidden files and links, empty folders and invalid sources,
permission errors, cancellation, source switching, and 360 pairs/720 files.
Generated JPEGs with controlled EXIF validate date reading, priority and fallback, offsets without day
shifts, orientation, decoding and thumbnail size. Tests also cover inclusive date limits, combined filters,
selection, format-specific counts/sizes, removal of hidden selections and reset on source changes.
Source file content, creation and modification timestamps are compared before and after reading.
Fake RW2 files validate extension recognition and grouping, not the RAW format itself.

Planning tests use real directories simulating an SD card and archive. They cover organization with/without
an event, multiple days, formats, existing files, filename and Unicode collisions, overlap,
broken links/links escaping the destination, missing access, missing destinations, removed/changed sources,
cancellation and preview invalidation. Insufficient/unknown capacity, case rules and read-only volumes
are simulated through an injectable volume reader; other filesystem access is real.
Content and timestamp snapshots of files/folders confirm that preview changes neither source nor archive.

Import tests copy real files between directories, checking bytes and SHA-256, read-only source files,
JSON records and retry without recopying. They cover same-size content conflicts, partial pairs,
temporary-file corruption, cancellation during copying and before publication, a concurrent file appearing
at rename time, source changes, folder replacement by symlink, archive replacement, mismatched volume UUIDs,
insufficient space, write failures and recording failures. Checkpoints simulate failures over real files;
ENOSPC/disconnection has not been triggered on hardware. A simulated post-publication error confirms
that retry verifies an intact final file.

History tests construct interruptions using running records and partial temporary files on disk.
They cover older versions, corrupt JSON, active locks, missing/changed destinations, partial and repeated
recovery attempts, changed sources, wrong folders, tampered paths, cleanup cancellation, and preservation
of unknown, replaced, symbolic, hard-linked temporary files or files with reused identifiers.
Filtering is verified per file, including counts and dates for partial pairs, same-name files with different
content, and reimporting after destination loss.

Settings tests use isolated UserDefaults domains. They cover persistence, invalid values, discovery defaults,
native bookmarks across access-service instances, missing folders, mismatched identity, replacement folders
at old paths, links, mount notifications and preview/selection invalidation.
All four organization combinations and collisions are checked; a real copy confirms the alternate layout
and preservation of originals. Organization changes require a new preview before copying.
No process was forcibly terminated, and physical disconnection/power loss has not been tested.

Manual verification in the app:

1. Choose a folder with JPG/RW2 files, including DCIM subfolders.
2. Check grouping, thumbnails, dates, indicators, and photo versus file counts.
3. Select pairs, switch between RAW + JPEG/JPEG/RAW, and check eligible files and size.
4. Enable date filtering, check endpoints and selection removal when narrowing the filter.
5. Choose another source, cancel a scan and test an empty folder.
6. Select a real card and verify sandboxed reading without changing originals.
7. Use real G100D RW2 files, standalone and paired, and check EXIF and RAW previews.
8. Choose the archive, enter an event and generate the preview. Check paths, volume, space and counts.
9. Close the preview, change selection/format/event and regenerate it; check updated destinations and files.
10. Test an archive containing existing files and confirm they require verification,
    without overwriting or creating folders/files during preview.
11. Start with test directories, click Import Roll and check destinations, SHA-256 and the Finder summary.
12. Repeat the import and check that matching content is identified without being copied again.
13. Cancel a larger selection and confirm no final file is incomplete; prepare another attempt.
14. Open History, confirm the archive and compare **Recorded result** with **Destination now**.
15. In test directories, remove/change a copy and verify again; the original must remain intact.
16. Prepare recovery for an incomplete operation, confirm both folders and review the preview before importing.
17. Inspect recorded temporary files, review the listed paths and confirm only eligible cleanup.
18. Enable **Not yet imported into this archive**, test a partially imported pair and check eligible files.
19. Change settings, reopen the app and check that format, filter, organization and archive persist under normal sandboxing.
20. With test drives, disconnect/reconnect the SSD and verify archive status and restoration; select the source again.
21. Connect another drive with the same name: it must not automatically replace the original archive.
22. Check detected volumes and manual selection with a real card and SSD; test revoked permission and reauthorization.

Branding tests verify the Roll product while preserving the bundle identifier/history path,
reading older format values, and matching English/pt-BR catalog placeholders.
Traditional tests run in pt-BR to preserve message assertions; localization tests cover both languages.
Builds and automated tests have been run locally. The user confirmed the previous manual workflow
with a real card and SSD. The three new screens were rendered natively using simulated directories
at 1280 × 880 and 1040 × 740, including a real import of six test JPEGs.
These renderings check layout without replacing manual interaction: UI automation does not have
Accessibility permission in this environment. Check navigation, pickers, filters and recovery in the
reorganized interface.

## Limitations and next step

The user confirmed manual validation of real RW2 files, reopening/reconnection and a large session
in the previous workflow. Physical removal during copying and power loss have not been validated.
Bookmarks have been tested using temporary directories and multiple access-service instances.
Revoked permissions and the reorganized visual workflow still need manual testing.

The next step is to check the new navigation, selection/scrolling, history filters, and opening details
and recovery in the app, then prepare a local Release build for everyday use.
