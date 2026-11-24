# Changelog

Changes follow Semantic Versioning where practical. Before 1.0, behavior may evolve;
original-file preservation and explicit conflict handling remain requirements.

## [0.1.0] - Unreleased

First public release candidate. Earlier local packages used 0.1.0/0.1.1;
they were not public releases. The public baseline is 0.1.0 (build 3), keeping the build number increasing.
No Git tag or GitHub release has been created.

### Added

- Native SwiftUI import, history, settings and About views with Roll branding.
- Recursive JPEG/RW2 discovery, paired capture grouping, thumbnails and date/format filters.
- Read-only planning, event naming and configurable year/date/format organization.
- Exclusive temporary copies, mandatory size/SHA-256 verification, no-overwrite finalization and cancellation.
- Content-based existing-file checks, local operation records, reconciliation and recovery previews.
- Identity-checked temporary cleanup, scoped archive bookmarks and volume notifications.
- English and Brazilian Portuguese localization, light and dark appearances.
- Import safety tests, local DMG packaging, contributor documentation and a proposed CI workflow.

### Asset and compatibility review

- Replace the unverified supplied icon with original MIT-licensed code-generated artwork and sanitize only the seven old icon blobs with explicit approval, preserving development commit metadata.
- Confirm an analysis-only macOS 14 universal build and macOS 13 Observation availability failure; supported requirements remain unchanged.

### Fixed during release preparation

- Normalize enumerated source URLs consistently so /private/tmp sources are not silently skipped.
- Cover a simulated device-disconnection error during copying and successful retry.

### Known publication gate

- Obtain separate approval for the reviewed exact-lease private push, pass remote CI, and complete maintainer review before public visibility.
