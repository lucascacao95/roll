# Native demonstration captures

Captured on macOS 27.0.1 using the current production SwiftUI views, English resources and brand
asset catalog, inside a separate native AppKit/NSHostingView harness. These are **native view captures**,
not mockups and not screenshots of an independently installed release. Window chrome is omitted.
The views, localization and import engine come directly from the application source.

| File | What it shows |
| --- | --- |
| import-light.png | New Roll, six selected RAW/JPEG groups and destination controls |
| import-dark.png | The same actual interface in dark appearance |
| selection-light.png | JPEG-only selection, inclusive date filtering and six eligible files |
| progress-light.png | Real copy progress held at a test checkpoint before temporary verification |
| history-light.png | A completed real import of the twelve synthetic files |
| settings-light.png | The native settings view and temporary authorized archive |
| about-light.png | Actual About view with the new original icon from the rebuilt bundle |

The JPEG thumbnails are original geometric illustrations generated with Core Graphics.
RAW files are deliberately synthetic grouping fixtures, not valid camera RAWs. Fixed artificial EXIF
contains only capture time; there are no personal photographs, GPS or third-party images.
Source/archive paths are freshly generated disposable /tmp folders, not a personal library or SD card.
Capacity and the generic system volume label reflect the temporary folders' host filesystem;
no drive serial numbers, volume UUIDs, usernames or bookmarks appear in the images.

## Reproduce

From the repository root with Xcode 27.0 installed:

```sh
./scripts/capture-demo.sh
```

Results and logs are in ignored `build/DemoCapture/`. The script compiles a separate demo executable
with a different bundle identity, isolated UserDefaults and its own temporary journal. It does not launch,
terminate or modify the installed Roll app or its archive. It copies and verifies twelve generated
files, plus a separate one-file progress example. All temporary data and preferences are removed on normal
completion. A crash can leave only the harness's uniquely named temporary fixtures.
No Accessibility or screen-recording permission is needed for this native bitmap capture method.
Review output before copying PNGs into this directory; do not copy logs, fixtures, journals or the demo app.

## Manual full-window capture

For screenshots with real macOS chrome, run `./scripts/capture-demo.sh --keep-fixtures`.
The script prints a newly created temporary root containing **Demo Card** and **Demo Archive**;
only these generated files are retained. All demo preferences are still isolated and cleared.

1. Launch the normal Roll build, with no real import running.
2. Choose the printed Demo Card and Demo Archive folders using the native pickers. This changes
   the normal app's saved archive preference; remember to choose your usual archive again afterward.
3. Check New Roll, RAW + JPEG/JPEG format changes, date filtering, selected counts and the preview.
   The existing demonstration copies should verify without overwriting.
4. For a fresh copy/progress capture, create another empty demo archive outside Demo Card and select it.
   These small files finish quickly; the automatic checkpoint capture above is more reliable for progress.
5. Capture the window using macOS Shift-Command-5. Exclude other windows, volume menus and private paths.
6. Review History and Settings, and repeat in dark appearance. Check keyboard focus and VoiceOver manually.
7. Restore your archive preference. Remove only the exact temporary root printed by the demo script
   once you no longer need the generated files; never apply cleanup instructions to a real library.

The captured views do not prove complete interaction accessibility, real camera support or drive-removal
behavior. No screenshots from a personal SD card or real import history are part of this repository.

The first six captures contain no app-icon artwork (wordmark/SF Symbols only). After replacing the icon,
the demo bundle and all captures were rebuilt, and About was added to exercise the new bundle icon.
The icon in About is the original repository-generated artwork documented in [ASSETS.md](../ASSETS.md).
