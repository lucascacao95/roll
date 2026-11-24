# Roll — product scope

This document is the product source of truth. Implementation details and verified release evidence
live in [architecture](docs/ARCHITECTURE.md) and [release readiness](docs/RELEASE_READINESS.md).

## Identity and purpose

- Official name: **Roll**. Wordmark: **roll.**. Tagline: **From capture to collection.**
- Native macOS photography utility using Swift 6 and SwiftUI, with platform APIs first.
- For enthusiasts with dedicated cameras, personal files and RAW + JPEG captures.
- A modern digital tool with an analog soul: simplicity, care, autonomy, nostalgia, order and reliability.
- English interface keys and documentation, with Brazilian Portuguese localization selected by macOS.
- A roll is an import session; the metaphor does not change folder structures or grouping rules.
- **Your photographs. Your files. Your collection.**

Import photographs from cards and folders directly into a conventional file archive, preferably on an
external SSD. Select visually, filter, organize and copy safely. Files remain accessible in Finder/Preview.
This is not an editor, catalog or backup system.

## Principles

1. Originals are read-only: never modify, move or delete source files.
2. Preserve original filenames and bytes. Never silently overwrite existing content.
3. A partial copy must not be published under the final filename.
4. Verify size and SHA-256, handle failures explicitly and keep truthful per-file outcomes.
5. An old successful record is not proof that a destination still exists or is intact.
6. Keep the architecture small, asynchronous where appropriate, and proportional to the problem.
7. Never format drives, create partitions or recommend automatic deletion of a card.
8. A verified import is not an independent backup.

## Main flow

1. Connect the card/source and archive drive; manually choose authorized folders when needed.
2. Discover files recursively, including DCIM; group RAW/JPEG representations of each capture.
3. Filter by capture date, format and verified import state, then select photographs.
4. Optionally name an event and preview every destination with photo/file counts, size and free space.
5. Explicitly start the import, follow copy/verification progress, cancel if needed and review results.
6. Review history, verify current destination content and explicitly prepare recovery of incomplete imports.

## Supported files, grouping and dates

- JPEG (`.JPG`, `.JPEG`) and Panasonic RAW (`.RW2`), recognizing extension case variations.
- Pair by source relative directory + case-preserved filename stem. Equal names in different directories
  remain different captures. Retain every physical JPG/JPEG/RAW file; format filtering controls copying.
- Prioritize EXIF DateTimeOriginal across the group, then digitized time, creation and modification dates.
  At equal priority, prefer JPEG. Camera civil dates are not shifted by timezone conversion.
- Identify fallback dates and unavailable previews. Never invent a capture date for an undated file.
- RAW thumbnail/EXIF support depends on ImageIO and the camera; real-camera checks are separate from fixtures.
- Keep the UI responsive for hundreds of captures. Do not claim universal camera/RAW support.

## Interface

- **New Roll:** source and archive selectors, volume status, thumbnail grid, multi-selection, date/format
  and not-yet-imported filters, event name, organization, preview, progress and per-file result.
- **History / Previous Rolls:** recorded source/destination, dates, counts, states and errors; current
  destination verification, explicit recovery and carefully scoped temporary inspection/cleanup.
- **Settings:** authorized default archive/reconnection, default format/filter and year/format folder options.
- Technical and safety wording must remain explicit; analog terminology must not obscure operations.
- Use native SwiftUI controls, SF Pro, SF Symbols, semantic backgrounds, accessibility and light/dark support.
- Brand colors: Ivory #F4EBDD, Charcoal #242424, Amber #C77736, Olive #8C9380. Use accents sparingly;
  retain semantic success/error/warning colors. Photography remains the main visual content.
- Original film-cartridge artwork is generated from repository-owned geometry and covered by MIT.
  Cleanup of the superseded attachment from Git history needs separate approval.
  See [branding](docs/BRANDING.md) and [assets](docs/ASSETS.md).

## Archive layout

Default layout, relative to the selected archive root:

```text
2026/
└── 2026-11-21 - Photo walk/
    ├── RAW/P100001.RW2
    └── JPEG/P100001.JPG
```

The date folder is mandatory. Year and format subfolders are configurable; event naming is optional
and per session. No event means date only. Original names remain unchanged. Recovery preserves recorded
paths regardless of current settings. Do not add a roll index or proprietary archive metadata.

## Safety requirements

- Reject overlapping source/archive/journal roots and unsafe relative paths, links and naming collisions.
- Check permissions/capacity and root/file/volume identities before and during copying.
- Create an exclusive temporary file in the final parent; hash while copying, synchronize and reread it
  to verify size and SHA-256. Publish only with a rename that refuses replacement; require synchronization.
- Preserve conflicting files. Existing content needs full verification before marking it already imported.
- Journal intended paths before archive writes and record per-file results, including partial operations.
- Handle cancellation, disconnection, out-of-space errors and unexpected termination conservatively.
- Recovery/cleanup require explicit confirmation and identity checks; never remove unknown temporary files.
- Store permissions using native security-scoped bookmarks; never reconnect solely by volume name or path.
- Keep the existing bundle ID, preference keys, bookmark format, journal schemas and storage paths compatible.

## Implementation and acceptance

Current deployment target is macOS 27.0. The verified toolchain is documented in [BUILDING.md](docs/BUILDING.md).
Internal project/target/module remain PhotoImporter; app/executable are Roll. Use simple local JSON records
and UserDefaults, native volume monitoring and scoped access. No external EXIF or imaging tools required.

Use generated fixtures and disposable directories for recursive discovery, pairing, filters, counts,
collision handling, read-only preview, verified copying, source preservation, interruption/retry,
cleanup and reconnection tests. Simulated RAW files prove grouping, not decoding.
Manual real-camera checks and hardware fault testing must be distinguished from automated tests.
Future work remains incremental: one testable milestone at a time, with changes, evidence, limits and next step.

## Out of scope

Image editing or RAW development; proprietary catalogs; cloud, Google Photos, Apple Photos or iCloud
integration; synchronization; telemetry/analytics; automated backup; card deletion; drive formatting;
commercial distribution systems; broad unverified format support. Optional future ideas are not implemented
features and must not be advertised as such.
