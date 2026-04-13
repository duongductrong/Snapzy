# Localization Architecture

This doc describes how Snapzy localizes user-facing text today. Keep it synced with source, not with intended future work.

## Current State

- Source language: `en`
- Supported app locales: `en`, `vi`
- Language selection: native macOS app language selection. Snapzy does not ship a custom language picker.
- Coverage: menu bar, onboarding, preferences, capture flows, recording flows, Quick Access, Annotate, Video Editor, cloud dialogs, alerts, toasts, and scrolling capture HUD/status text

## Runtime Model

```mermaid
flowchart LR
    A["SwiftUI views"] --> B["Localizable.xcstrings"]
    C["AppKit alerts, open panels, menus"] --> D["Shared/Localization/L10n.swift"]
    E["Shared displayName/errorDescription/status copy"] --> D
    D --> B
    F["Privacy permission copy"] --> G["Resources/en.lproj + vi.lproj/InfoPlist.strings"]
```

## File Map

| Path | Owns |
| --- | --- |
| `Snapzy/Shared/Localization/L10n.swift` | Shared localization bridge for AppKit strings, alerts, toasts, `displayName`, `errorDescription`, and text that does not auto-extract cleanly from SwiftUI |
| `Snapzy/Resources/Localizable.xcstrings` | Main String Catalog for `en` and `vi` |
| `Snapzy/Resources/en.lproj/InfoPlist.strings` | English privacy usage descriptions |
| `Snapzy/Resources/vi.lproj/InfoPlist.strings` | Vietnamese privacy usage descriptions |
| `Snapzy.xcodeproj/project.pbxproj` | Project regions and String Catalog related build settings |

## Working Rules

- Localize all user-facing copy.
- Prefer `L10n` for AppKit, service-layer errors, toasts, open-panel prompts, and shared model labels.
- Keep raw ids and persisted values stable. Localize at the display layer, not in storage models.
- Use `Text(verbatim:)` or other explicit verbatim rendering for tokens that should stay raw.
- Keep these intentionally unlocalized unless product behavior changes:
  - Brand names like `Snapzy`
  - File formats such as `PNG`, `JPEG`, `WebP`, `MOV`, `MP4`
  - Keyboard glyphs and shortcut key labels
  - MIME types, UTType ids, URL fragments, and file-name templates
- If a short technical token stays verbatim in UI, add localized accessibility text when needed.

## Coverage Notes

- Capture and recording flows route their user-facing status, toast, and alert copy through `L10n`.
- Scrolling capture uses localized HUD labels, guidance copy, preview captions, and toast messages.
- Annotate and Video Editor surfaces are localized, including shared tool labels, dialogs, export messaging, and empty states.
- Preferences, onboarding, Quick Access, menu bar, and cloud flows are localized.
- Privacy permission prompts come from `InfoPlist.strings`, not from `Localizable.xcstrings`.

## Verification

- Drift check between `L10n.swift` and `Localizable.xcstrings` should stay `missing=0` and `extra=0`.
- Build with:

```bash
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug -derivedDataPath /tmp/SnapzyDerivedData build CODE_SIGNING_ALLOWED=NO
```

- Hardcoded user-facing copy check should come back empty for app code outside previews/tests.

## Unresolved Questions

- None right now.
