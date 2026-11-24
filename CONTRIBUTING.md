# Contributing to Roll

Roll is a small native macOS utility. Discuss changes that affect data safety, architecture,
privacy or the product scope before implementing them. Read [PROJECT_SCOPE.md](PROJECT_SCOPE.md),
[architecture](docs/ARCHITECTURE.md) and [build instructions](docs/BUILDING.md).

## Development

Use Xcode 27.0 and Swift 6 mode, with the shared PhotoImporter scheme.
There are no external dependencies. Run `./scripts/check.sh` before submitting a change.
Keep English source strings and Brazilian Portuguese translations together in `Localizable.xcstrings`.
Use system controls, accessible labels, native semantic colors and both appearances.

## File safety

- Never modify, move or delete source files, even on cancellation or recovery.
- Never replace a destination file. Size, name or history alone cannot prove a duplicate.
- Preserve descriptor-based no-follow traversal, exclusive temporary creation, SHA-256 verification,
  required synchronization, and no-overwrite finalization.
- Keep recovery paths and journal schemas compatible; do not change the bundle ID or bookmark storage casually.
- Test errors using generated files and disposable folders. Never run destructive tests on a real archive.
- Add regression tests for concrete failures, especially around copy/verify/publish boundaries.

## Pull requests

Explain the problem, resulting behavior, validation performed and limits.
Keep changes focused. Do not include real photos, EXIF/GPS, absolute home paths, volume identifiers,
import records, access bookmarks, credentials, user-specific Xcode state or generated builds.
Do not claim a mock or synthetic RAW file validates camera decoding.

Code and documentation contributions must be compatible with MIT. Identify the origin and license of
any new asset; unresolved provenance is not acceptable. See [asset policy](docs/ASSETS.md).
