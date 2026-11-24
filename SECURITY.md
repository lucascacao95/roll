# Security and privacy

Roll reads originals and writes verified copies into a folder you authorize.
There is no application telemetry, account, cloud integration or network client in the current implementation.
A verified import is not a backup and does not protect against later drive failure or external modification.

## Reporting a problem

For suspected data loss, overwrite, path traversal, credential exposure or privacy issues, do not include
sensitive details in a public issue. Use **Security → Report a vulnerability** on this repository
if private vulnerability reporting is available. Enabling that feature is a publication checklist item.
If it is unavailable, contact the maintainer through the personal address in the Git author metadata
and request a private reporting channel. No response-time guarantee or support policy is implied.

Share a minimal reproduction using generated files, macOS/Xcode versions and sanitized error messages.
Do not send personal photos, location metadata, security-scoped bookmarks, volume UUIDs, certificates,
complete local logs or import JSON records. Logs and records may contain paths and filenames.

## Local data

Preferences and the archive bookmark are stored in UserDefaults in the app's sandbox.
Import records live under its Application Support `PhotoImporter/Imports` directory and include
absolute source/archive paths, volume/file identities, hashes and outcomes. These records stay local;
do not commit or publicly upload them. Thumbnails are cached in memory.

Copies preserve the original bytes, including embedded EXIF and GPS. Roll does not remove private
metadata from photographs. The privacy manifest declares local preferences, capacity and timestamp access.

## Limits

Safety checks reduce accidental corruption and unsafe path changes; they are not protection against
another privileged process actively modifying files or hardware that lies about durable writes.
Physical unplugging, power loss, all filesystem types and manual permission revocation have not been
fully validated. Keep independent backups and review [known limits](docs/RELEASE_READINESS.md).
