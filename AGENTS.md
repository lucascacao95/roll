# Working on Roll

Read PROJECT_SCOPE.md before implementation. Product: Roll; wordmark: roll.; tagline:
From capture to collection. English documentation and interface keys, with pt-BR localization.

Preserve the current native SwiftUI architecture and source-only SD access. No overwriting,
source deletion, cloud integrations, catalog, editor, analytics or automatic backup.
Keep mandatory size/SHA-256 verification, exclusive temp files, no-follow descriptors,
no-replacement rename, durable records, operation locks and explicit recovery confirmation.

Keep bundle identifier, bookmark keys, persistence paths and schemas compatible. Internal
PhotoImporter module/target names are intentional. Do not rename them for appearance alone.
Use disposable directories and generated fixtures for tests; never mutate a user's archive.
Run ./scripts/check.sh for source changes and report what was actually validated.
Never commit user data, private paths, signing credentials, bookmarks, import journals or build output.
Do not publish, push, tag, rewrite history or change repository visibility without explicit authorization.
Check repository-local Git identity; never change the global configuration.
