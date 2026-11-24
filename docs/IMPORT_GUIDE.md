# Import guide

Detailed behavior of the current implementation. See [building and testing](BUILDING.md)
and [architecture](ARCHITECTURE.md) for development details.

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

Current verification and outstanding manual checks are recorded in [RELEASE_READINESS.md](RELEASE_READINESS.md).

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

