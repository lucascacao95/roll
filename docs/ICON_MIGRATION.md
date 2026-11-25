# App icon replacement and history cleanup plan

Status: **authorized local cleanup and exact-lease private push completed; first remote CI passed**.

## Execution result

The maintainer explicitly approved replacing only the seven old image blobs while preserving commit
metadata, with no push. Preparation was committed locally as 5928c79, then a fresh isolated clone was
filtered using a pinned upstream git-filter-repo tool. No shared object alternates were used.

| Original commit | Sanitized commit | Verification |
| --- | --- | --- |
| 7ca1cd0d51e3f32791b4adb0c738980bfc6a20c5 | a3af6e00ab4744ec3f5634201b10b42e4aa03842 | Only eleven icon paths changed; author/committer identities, dates and message identical. |
| b9be783d46f7dbae0101a83e10b26a7e69077541 | 9ab4ae7202a4a6a66df97f701ba067e5d0219960 | Only eleven icon paths changed; author/committer identities, dates and message identical. |
| 5928c79524ba62fb092f45e021ff34163526b309 | aba477f858bb8bf98bf17f1cf8c6a53380c362a3 | Preparation tree unchanged; parent hashes necessarily changed; commit metadata identical. |

Raw commit metadata was compared byte-for-byte after excluding only tree/parent headers. Every path,
file mode and non-icon object ID was compared. The final preparation tree ID is identical before/after.
All seven old IDs are absent from reachable refs and cannot be found with git cat-file in the cleaned
object database. git fsck passed. A private verified Git bundle and working-tree snapshot were created
outside the publication repository; the original Git directory is retained there when installing the
clean history. Backups are deliberately not represented by a branch, tag or replace ref in the clean repo.

Pinned tool source: newren/git-filter-repo at d7b75aca907380f608892cc289e616f195427b99.
No global tool installation or Git configuration change was made. Tool/check details and verification
maps are in ignored build/IconAudit and the separate private backup. Backup paths are not public documentation.

On 2026-11-25, the maintainer separately authorized the private push and CI. The command
`git push --force-with-lease=refs/heads/main:b9be783d46f7dbae0101a83e10b26a7e69077541 origin refs/heads/main:refs/heads/main`
succeeded, updating main to dfe07cd. The [first CI run](https://github.com/lucascacao95/roll/actions/runs/45623132133) passed. No public visibility,
release, tag or binary publication was authorized or performed. Normal local fetch and origin/main tracking
were restored only after that successful push; no old blob is reachable from the restored tracking ref.

The inventory and plan below record the pre-cleanup state and approved strategy, not a claim that old
pixels still exist in the local publication history. Historical provisional filenames/text remain, but
those image bytes are now the original repository artwork. Old remote/backup copies are not a license grant.

## Decision and provenance

The prior conversation attachment has no verifiable creator/source/redistribution record in the available
project evidence. No external reverse-image service was used. Instead of assuming rights, the current tree
uses original Core Graphics artwork defined in scripts/GenerateAppIcon.swift, under the approved MIT license.
All ten native PNG slots were replaced, the README now uses docs/branding/roll-icon.png, the old source PNG
was removed from the current tree, and brand/license documentation was updated. Bundle identity, AppIcon
slot filenames, persistence and import behavior remain unchanged.

The previous files were copied into ignored build/IconAudit/previous-artwork for local reference before
replacement. This is a quarantine/reference copy, not a release input. It must not be staged or distributed.
The old artwork and local installers were not destructively deleted, during the initial icon replacement. The subsequent local rewrite is recorded above.

## Pre-cleanup occurrence inventory

| Location | Finding and disposition |
| --- | --- |
| AppIcon.appiconset | Ten PNG paths, seven distinct old blobs; now replaced in place with new original art. Contents.json and Xcode AppIcon settings remain valid. |
| docs/branding/roll-provisional-source.png | Former 1024px source; identical to the old largest app slot. Removed from current tree, retained in both historical commits. |
| README.md | Former HTML img pointed at the attachment source. Current img points at roll-icon.png. Both old README versions remain in history. |
| PROJECT_SCOPE.md, docs/BRANDING.md | Historical prose described the attachment as provisional; current prose describes the original generator. Prose is not embedded image data. |
| docs/ASSETS.md, LICENSE, release report | Prepared local provenance notices updated to distinguish current original art from unlicensed historical copies. These documents were not yet committed. |
| BrandIdentity.swift | About reads NSApplication.applicationIconImage; no independent image bytes or copied illustration in SwiftUI source. Its comment now matches the new artwork. |
| Sidebar/empty states/history | Wordmark and native SF Symbols, not embedded app-icon pixels. |
| Existing six screenshots | Inspected via the capture implementation and native images: no old app icon; they contain wordmark/system symbols and generated fixtures. |
| New About capture | Uses the replacement AppIcon from the rebuilt isolated demo bundle. |
| Derived assets | Xcode compiles AppIcon.icns and Assets.car in build products/intermediates. Stale ignored builds retain old compiled art until rebuilt; never distribute them. |
| Git history | The same eleven old PNG paths occur in both existing commits, through the seven blobs below. No other historical image content was found. |

### Exact old blobs

Before cleanup, every blob below was reachable from both original commits:
`7ca1cd0d51e3f32791b4adb0c738980bfc6a20c5` and
`b9be783d46f7dbae0101a83e10b26a7e69077541`.

| Old blob ID | Historical paths |
| --- | --- |
| `21ce3e34829d74a67cf1b415aa9309be5c5483ed` | `PhotoImporter/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png`; `PhotoImporter/Assets.xcassets/AppIcon.appiconset/icon_512x512.png` |
| `26f305ab410a9b1f379e15e1c3a98046c6e2b9c8` | `PhotoImporter/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png`; `PhotoImporter/Assets.xcassets/AppIcon.appiconset/icon_256x256.png` |
| `90267f3d30c2b4712d0a6022fa46a4707f60ba44` | `PhotoImporter/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png` |
| `91efd3a09154946a419e9ebf0a12959d6edd5910` | `PhotoImporter/Assets.xcassets/AppIcon.appiconset/icon_128x128.png` |
| `b6cd5e1235bcc39ea6f68056a932299863020be4` | `PhotoImporter/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`; `docs/branding/roll-provisional-source.png` |
| `cd6b97c2ec22ddfd232ea427944fbb8cd07e9dca` | `PhotoImporter/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png`; `PhotoImporter/Assets.xcassets/AppIcon.appiconset/icon_32x32.png` |
| `e7f5d1e83407f070ef71f4a1ea4c75ba6d163924` | `PhotoImporter/Assets.xcassets/AppIcon.appiconset/icon_16x16.png` |

### Ignored local distribution artifacts

The three existing DMGs were mounted read-only, inspected and detached; none was executed or changed.

| File | Old app icon found? |
| --- | --- |
| `build/releases/PhotoImporter-0.1.0-macOS-arm64.dmg` | No AppIcon.icns in the packaged application. |
| `build/releases/Roll-0.1.1-macOS-arm64.dmg` | Yes; compiled AppIcon.icns matches the old build fingerprint. |
| `build/releases/Roll-0.1.0-macOS-arm64.dmg` | No AppIcon.icns in the packaged application. |

The old compiled AppIcon.icns SHA-256 is
`8e584688eea7b7f890b9b87d3fd7a39cb26c0d663dbfded290649ce4c20b2d92`.
Before replacement, it was found in these local bundles:

- `build/DemoCapture/RollDemo.app/Contents/Resources/AppIcon.icns`
- `build/DemoCapture/DerivedData/Build/Products/Debug/Roll.app/Contents/Resources/AppIcon.icns`
- `build/ReleaseDerivedData/Build/Products/Release/Roll.app/Contents/Resources/AppIcon.icns`
- `build/CheckDerivedData/Build/Products/Debug/Roll.app/Contents/Resources/AppIcon.icns`
- `build/CheckDerivedData/Build/Products/Release/Roll.app/Contents/Resources/AppIcon.icns`
- `build/CompatibilityProbe/Build/Products/Release/Roll.app/Contents/Resources/AppIcon.icns`
- `build/ReadinessDerivedData/Build/Products/Debug/Roll.app/Contents/Resources/AppIcon.icns`

These paths are ignored and absent from both Git trees. The full local artifact hashes are in ignored
build/IconAudit/before-replacement.json. Current CheckDerivedData and DemoCapture outputs are rebuilt;
other paths listed above may still contain stale art. Existing DMGs remain unchanged and must not be
uploaded. No replacement binary is published or automatically packaged in this stage.

Installed apps, Dock/Finder caches and earlier /tmp development bundles are outside the repository.
They may retain cached art, but are not Git publication inputs. Do not remove installed applications,
clear system icon caches or restart a running import as part of this cleanup. Only a separately approved
install of the new build should replace an installed bundle. No system-wide cache or application search
was performed; this inventory covers project files, known project build outputs and reachable Git content.

## Visibility discrepancy discovered during review

GitHub reported this repository as PUBLIC during the follow-up, despite the previous private-state
snapshot. Following the maintainer's explicit instruction to keep it private, visibility was restored to
PRIVATE and confirmed via the API. No code was pushed and no Git history was changed. The repository
API reports disabled=false; a transient SSH read immediately after transition failed, then the same read
succeeded and confirmed main still points at b9be783. SSH identifies the approved personal account.

The period of public exposure is unknown. Making the repository private does not revoke possible existing
clones, downloads, forks or cached views. The cleanup below can remove old art from the history we publish
next; it cannot prove the old bytes were never downloaded or erase someone else's copy.

## Approved narrow historical cleanup strategy

Because there are only two existing commits and no tags, retain the development chronology rather than
squashing into a new orphan root. Use git-filter-repo in a fresh isolated local clone, with a callback that
replaces exactly the seven old binary blobs by the corresponding new original PNG data. A single old blob
can appear at several paths of the same size; the mapping is unambiguous. This keeps old asset-catalog paths
and README image links buildable while removing the previous image bytes. Historical text/filenames still
identify an earlier provisional asset; the cleanup commit/report must explain that its pixels were sanitized.

Preserve commit messages, author/committer name/email and dates, order and code changes. Both commit IDs
and descendant IDs necessarily change because their trees/parents change. This is a history rewrite even
when development content is otherwise retained. Do not silently use a normal push to avoid this approval.

Alternative: strip the seven exact old blobs with git-filter-repo. It preserves code chronology but removes
historical PNG files while Contents.json still references them; old revisions may fail asset builds or show
broken README images. Do not delete the entire catalog path indiscriminately, which would also remove new art.
An orphan/squashed initial commit is simpler but discards useful development history, so it is not preferred.
A new tip commit alone leaves every old blob reachable and does not close the publication gate.

### Execution sequence after explicit approval

1. Review and commit the current preparation locally with the approved personal identity, without pushing.
2. Recheck the remote refs and current visibility. Create a verified offline Git bundle backup outside the
   future publication clone, plus an ignored snapshot of uncommitted work if any remains. Keep the backup private.
3. Use a fresh clone with no shared object alternates. Prepare a pinned one-off git-filter-repo tool locally
   if unavailable; no global Git config change or application dependency is needed.
4. Snapshot the seven new replacement PNGs and the mapping outside the filtered clone. Run only the
   approved binary-blob callback, preserving other files and commit metadata. No credentials/image data
   need be sent to an external service.
5. Validate metadata and code diffs old versus new, commit count/order, both historical catalogs/README links,
   and current build/tests. Confirm all seven old IDs are absent from `git rev-list --objects --all`, not just HEAD.
   Inspect every branch/tag/remote-tracking/replace ref; do not create a backup ref in the publication clone.
6. Audit privacy again and inspect available GitHub refs (including PRs/forks) before any push. Keep the backup
   in separate private storage, not a repository branch that could reintroduce old objects.
7. Only after separate authorization, update the single main branch with an exact expected-old-SHA lease.
   Never use an unrestricted force/mirror push. Confirm remote main, then wait for the real CI run while private.
8. Stop for maintainer review after passing CI. A public visibility change requires another explicit decision.
   No tag, release or binary upload is included.

The upstream tool documents this exact type of
[binary blob replacement](https://github.com/newren/git-filter-repo/blob/main/Documentation/examples-from-user-filed-issues.md).
GitHub documents the [limits and side effects of history cleanup](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).
Do not promise global erasure: support does not generally purge non-sensitive cached content, and outside
copies cannot be controlled. No support request or third-party message is authorized by this plan.

A future force-with-lease command must use the freshly verified old remote SHA. Its shape is:

```text
git push --force-with-lease=refs/heads/main:<approved-old-remote-sha> origin refs/heads/main:refs/heads/main
```

The narrow local rewrite and its separately authorized exact-lease push are complete. The command above records the approved strategy; do not repeat it against a changed remote SHA.

### Temporary local fetch safeguard — removed after approved push

The negative refspec protected the old remote-history interval. After the exact-lease update succeeded,
it was removed and normal fetch/upstream tracking to origin/main was restored. This repository-local
cleanup did not change global Git configuration. Do not merge a legacy clone or restore an old backup
branch into the sanitized history; those copies still contain the superseded artwork.
