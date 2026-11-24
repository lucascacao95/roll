# Roll — brand identity

Official product: **Roll** (`Roll.app`, executable `Roll`). Wordmark: **roll.**, lowercase system semibold,
with a small amber period. Tagline: **From capture to collection.** Philosophy:
**Your photographs. Your files. Your collection.**

A native photography utility for enthusiasts: simple, careful, independent, organized and trustworthy,
with a restrained analog reference. Use compact branding in the sidebar, empty state and About window.
Keep photographs prominent and native macOS conventions intact.

## Visual language

Use SF Pro and system symbols, no external fonts. Reference palette: Ivory #F4EBDD, Charcoal #242424,
Amber #C77736, Olive #8C9380. Keep semantic macOS backgrounds; do not spread beige textures across screens.
Amber identifies the wordmark and selected navigation, with Charcoal text. Olive is used sparingly for capacity.
Success, error, warning and information retain semantic colors. AccentColor variants are #985322 (light)
and #DEA36F (dark). Color assets are in `PhotoImporter/Assets.xcassets`.

## Language

English source keys/fallback and pt-BR translations live in Localizable.xcstrings. macOS selects the
preferred language; Roll has no independent language override. Use New Roll / Novo rolo, History /
Histórico, Previous Rolls / Rolos anteriores, Archive / Acervo, Settings / Ajustes, Import Roll / Importar rolo.
Keep technical and safety messages explicit. Existing recorded messages remain in their original language.

Localization.swift formats arguments separately from translated templates. Keep `%@` placeholders aligned;
never use filenames as format strings or translate actual paths. Run catalog tests in both languages.

## Compatibility

Project, target, scheme, module and source folder remain PhotoImporter. User-visible names are Roll.
Do not rename the bundle identifier, UserDefaults keys, app-scoped bookmarks, `PhotoImporter/Imports`,
JSON schemas, operation locks or `.photoimporter-*.partial` names for branding. Raw enum values remain
compatible and receive localized labels. A roll is a session, not a new on-disk data model.

## Icon

The current icon is original geometry authored for Roll in [GenerateAppIcon.swift](../scripts/GenerateAppIcon.swift),
rendered using Core Graphics and ImageIO, with no source images, fonts, logos, system symbol artwork or
external assets. The preview is [branding/roll-icon.png](branding/roll-icon.png). Native slots cover 16–1024 px
(including @2x). Xcode compiles AppIcon.icns and metadata; About displays the same application icon.
Both configurations retain ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon.

The generator and its outputs are covered by the project's approved MIT license. This replaces the supplied
attachment, whose provenance could not be established. Local history has been sanitized with explicit approval; the private remote update remains gated. See [ASSETS.md](ASSETS.md) and [migration inventory](ICON_MIGRATION.md).

Visual direction: charcoal 35 mm cartridge, amber label, ivory background, perforated strip, restrained
olive detail and subtle depth. No manufacturer logos, generic cameras, download arrows, external fonts or
long text. Small-size art can be refined later without changing the bundle identity or storage behavior.

Regenerate from the repository root with `xcrun swift scripts/GenerateAppIcon.swift`. Review the PNG diff,
Finder/Dock/About and small sizes in both appearances before shipping. Geometry is reproducible; exact PNG
encoding/rasterization may vary between platform releases. No download or image service is required.
