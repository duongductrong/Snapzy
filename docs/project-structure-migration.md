# Project Structure Migration Guide

## Purpose

This guide defines and records the migration of `/Users/duongductrong/Developer/ZapShot/Snapzy` to the pragmatic flattened architecture in `/Users/duongductrong/Developer/ZapShot/docs/project-structure.md` (v2.0).

## Decisions (Updated for v2.0)

1. Feature entry points stay visible at feature root (`[Feature]View.swift`, `[Feature]ViewModel.swift`).
2. One-level nesting is allowed inside features for `Components`, `Managers`, `Services`, `Models`.
3. Global services stay single-file by default, and may expand into domain folders when complex.
4. Naming enforcement remains at file-name level first, using `[Feature]` prefixes for feature files.
5. `Core` remains fully removed, no compatibility shims.
6. License engine stays in `Services`, while license UI remains in `Features/License`.
7. `Snapzy.entitlements` remains at `/Users/duongductrong/Developer/ZapShot/Snapzy/Snapzy.entitlements`.
8. `ContentView.swift` remains removed.

## Target Structure

```text
Snapzy/
  App/
  Features/
    [Feature]/                  // Root keeps main View/ViewModel
      Components/               // Optional (one-level max)
      Managers/                 // Optional (one-level max)
      Services/                 // Optional (one-level max)
      Models/                   // Optional (one-level max)
  Services/
    [Domain]/                   // Optional for complex global services
  Shared/
    Components/
    Bridging/
    Extensions/
    Styles/
  Resources/
```

## Migration Sequence

1. Baseline build in Debug and Release.
2. Scaffold target root folders.
3. Move resources to `Resources/` and update project build paths.
4. Decompose `Core` into `Services`, `Shared`, and feature-local files.
5. Flatten legacy deep nesting and keep feature entry points at feature root.
6. Rename feature files with strict `[Feature]` prefix.
7. Normalize app entry orchestration in `App/` with coordinator + environment.
8. Remove dead files and stale folders.
9. Rebuild and run structure checks.
10. Apply optional one-level grouping only when it improves readability.

## Implemented Moves (Summary)

- `Snapzy/Assets.xcassets` -> `Snapzy/Resources/Assets.xcassets`
- `Snapzy/Info.plist` -> `Snapzy/Resources/Info.plist`
- `Snapzy/Core/*` -> split into:
  - `Snapzy/Services/*` (global services, diagnostics, config, license engine)
  - `Snapzy/Shared/*` (extensions, reusable components, style tokens)
  - `Snapzy/Features/Annotate/AnnotateShortcutManager.swift`
  - `Snapzy/Features/Recording/RecordingSession.swift`
  - `Snapzy/Features/Capture/CaptureViewModel.swift`
- Legacy deep feature subfolders removed across all features.
- Feature files renamed with strict feature prefix.
- `Snapzy/ContentView.swift` removed.
- `Snapzy/Core/License/README.md` -> `/Users/duongductrong/Developer/ZapShot/docs/license-engine-readme.md`
- Current feature layout remains fully flat, which is a valid stricter subset of v2.0.
- v2.0 foldering wave applied:
  - `Features/Onboarding/Components/*` (supporting onboarding views + style tokens)
  - `Features/QuickAccess/Components/*` (UI pieces)
  - `Features/QuickAccess/Managers/*` (panel controller)
  - `Features/QuickAccess/Models/*` (item/layout/position)
  - `Features/QuickAccess/Services/*` (thumbnail/sound/animations)
  - `Features/VideoEditor/Components/*` (UI subviews and sidebars)
  - `Features/VideoEditor/Managers/*` (window + window controller)
  - `Features/VideoEditor/Models/*` (export settings + zoom segment)
  - `Features/VideoEditor/Services/*` (exporter + zoom calculators/compositor)
  - `Features/Recording/Components/*` (toolbar/annotation views)
  - `Features/Recording/Managers/*` (overlay/annotation windows)
  - `Features/Recording/Models/*` (annotation state/config)
  - `Features/Recording/Services/*` (annotation factory)
  - `Features/Annotate/Components/*` (canvas/mockup/sidebar views)
  - `Features/Annotate/Managers/*` (window layer + mockup manager)
  - `Features/Annotate/Models/*` (annotation/mockup data types)
  - `Features/Annotate/Services/*` (rendering/export/factory helpers)
  - `Features/Preferences/Components/*` (tab views + shared settings rows/cards)
  - `Features/Preferences/Managers/*` (login item manager)
  - `Features/Preferences/Models/*` (settings keys)
  - `Services/Capture/*` (capture, record, area select, post-capture handling)
  - `Services/Media/*` (GIF + OCR processing)
  - `Services/License/*` (license engine + provider + security + state)
  - `Services/Diagnostics/*` (logging + crash sentinel + cleanup)
  - `Services/Wallpaper/*` (wallpaper and desktop icon handling)
  - `Services/Shortcuts/*` (shortcut manager)
  - `Services/Appearance/*` (theme manager)
  - `Services/Configuration/*` (secret config)
  - `Services/Updates/*` (updater manager)
  - Root entry visibility retained:
    - `Features/Onboarding/OnboardingFlowView.swift`
    - `Features/QuickAccess/QuickAccessStackView.swift`
    - `Features/QuickAccess/QuickAccessManager.swift`
    - `Features/VideoEditor/VideoEditorMainView.swift`
    - `Features/VideoEditor/VideoEditorState.swift`
    - `Features/VideoEditor/VideoEditorManager.swift`
    - `Features/Recording/RecordingCoordinator.swift`
    - `Features/Recording/RecordingSession.swift`
    - `Features/Recording/RecordingToolbarView.swift`
    - `Features/Recording/RecordingToolbarWindow.swift`
    - `Features/Annotate/AnnotateMainView.swift`
    - `Features/Annotate/AnnotateState.swift`
    - `Features/Annotate/AnnotateManager.swift`
    - `Features/Preferences/PreferencesView.swift`
    - `Features/Preferences/PreferencesManager.swift`

## Verification Commands

```bash
# No nesting deeper than one level under a feature root (expects no output)
find Snapzy/Features -mindepth 3 -type d

# Allowed immediate subfolders under a feature root (expects no output)
find Snapzy/Features -mindepth 2 -maxdepth 2 -type d | awk -F/ '$NF !~ /^(Components|Managers|Services|Models)$/ {print}'

# Naming compliance: expects no output
for f in $(rg --files Snapzy/Features | sort); do
  feat=$(echo "$f" | awk -F/ '{print $3}')
  base=$(basename "$f")
  case "$base" in
    ${feat}*.swift|${feat}*.metal|${feat}*.plist|${feat}*.md) ;;
    *) echo "$f" ;;
  esac
done

# Build
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Release -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
```

## Current Status

- Migration is implemented and compile-safe in Debug and Release.
- Feature structure is v2.0-compliant.
- Pragmatic one-level grouping is now used in `Onboarding`, `QuickAccess`, `VideoEditor`, `Recording`, `Annotate`, and `Preferences`.
- Services are grouped into domain folders and no longer kept as one large flat list.
- Naming compliance is complete at file-name level.
- `Core` is removed.
- v2.0 flexibility is now documented for controlled one-level nesting and service domain folders.

## Follow-up Items

1. Resolve target warning about `Info.plist` in Copy Bundle Resources.
2. Triage existing Swift warnings (concurrency/sendability/deprecations) in separate cleanup passes.
3. Add a lightweight structure-check script/CI gate for v2.0 allowed folder names and feature-file naming policy.
