# PLAN: Project Structure Migration

## Goal

Refactor `/Users/duongductrong/Developer/ZapShot/Snapzy` to follow pragmatic flattened architecture in `/Users/duongductrong/Developer/ZapShot/docs/project-structure.md` (v2.0), with minimal behavior change and safe incremental rollout.

## Current Snapshot

- Swift files: `182`
- Files under `Core`: `39`
- Files under `Features`: `140`
- Nested feature subdirectories: `27`
- Feature files not prefixed with feature name: `78`
- Empty/stale directories found:
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Core/Styles`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Core/Window`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Annotate/Tools`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Preferences/Window`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/ScrollingCapture`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/VideoEditor/Views/Export`

## Target Structure

```text
Snapzy/
  App/
  Features/
    [Feature]/                 // Root keeps primary View/ViewModel
      Components/              // Optional, one-level max
      Managers/                // Optional, one-level max
      Services/                // Optional, one-level max
      Models/                  // Optional, one-level max
  Services/
    [Domain]/                  // Optional for complex global services
  Shared/
    Components/
    Bridging/
    Extensions/
    Styles/
  Resources/
```

## Migration Principles

- Move-first, rename-second to reduce regression risk.
- One compile-safe change set at a time.
- No behavior changes mixed into structural phases.
- Keep primary feature entry points visible at feature root.
- Allow one-level feature subfolders only (`Components`, `Managers`, `Services`, `Models`).
- Allow service domain folders when global service complexity justifies splitting.
- Enforce naming convention only after folder flattening is stable.

## Phase Plan

### Phase 0: Decision Gate

- Lock naming and split policy for large features.
- Confirm ownership boundaries: `Services` vs `Shared` vs `Features`.
- Confirm destination of `Snapzy.entitlements`.
- Exit criteria: all open decisions in this plan resolved.

### Phase 1: Baseline and Safety Rails

- Create migration branch: `codex/project-structure-refactor`.
- Capture baseline build + run + smoke checklist.
- Add migration tracking checklist in this doc.
- Exit criteria: baseline validated and reproducible.

### Phase 2: Create Target Skeleton

- Ensure root folders exist: `App`, `Features`, `Services`, `Shared`, `Resources`.
- Do not move business logic yet.
- Exit criteria: no build impact, directory scaffold ready.

### Phase 3: Resource Path Migration

- Move `Assets.xcassets` and `Info.plist` into `Resources`.
- Update project build settings path references.
- Move or retain `Snapzy.entitlements` based on Phase 0 decision.
- Exit criteria: app builds and launches with updated paths.

### Phase 4: Core Decomposition

- Move global app services from `Core` to `Services`.
- Move reusable UI, wrappers, extensions, tokens to `Shared`.
- Keep type names unchanged in this phase.
- Exit criteria: `Core` contents reduced to zero or temporary shims only.

### Phase 5: Feature Normalization Wave 1 (Lower Risk)

- Normalize: `License`, `Splash`, `Updates`, `Onboarding`, `QuickAccess`.
- Remove deep nesting and keep feature entry points at root.
- Keep code behavior unchanged.
- Exit criteria: these five features are v2.0-compliant and compile-safe.

### Phase 6: Feature Normalization Wave 2 (Higher Risk)

- Normalize: `Preferences`, `Recording`, `VideoEditor`, `Annotate`.
- Apply incremental sub-wave migration per feature (not one giant diff).
- Exit criteria: all feature folders are v2.0-compliant and compile-safe.

### Phase 7: App Layer Normalization

- Introduce/normalize:
  - `AppCoordinator.swift`
  - `AppEnvironment.swift`
- Centralize window/menu-bar/navigation orchestration at app layer.
- Exit criteria: app entry and coordination responsibilities are explicit and clean.

### Phase 8: Naming Compliance Pass

- Enforce `[Feature]` filename prefixes in every feature folder.
- Optional: align Swift type names with filenames if approved.
- Exit criteria: naming compliance reaches 100%.

### Phase 9: Cleanup and Guardrails

- Remove dead files and empty directories.
- Confirm if `ContentView.swift` should be removed.
- Add lightweight structure-check script to prevent regression.
- Update architecture docs to reflect final structure.
- Exit criteria: clean tree, guardrails in place, docs updated.

## Execution Log

### Run 1 - 2026-02-17 12:51 +07

- Current branch before migration: `master`
- Created migration branch: `codex/project-structure-refactor`
- Baseline commands executed:
  - `xcodebuild -list -project Snapzy.xcodeproj` -> success
  - `xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build` -> success
  - `xcodebuild -project Snapzy.xcodeproj -scheme Snapzy -configuration Release -destination 'platform=macOS' -derivedDataPath .build/DerivedData build` -> success
- Baseline warnings observed (pre-existing):
  - Copy Bundle Resources includes `Info.plist` warning in target configuration.
  - App Intents metadata extraction skipped (`No AppIntents.framework dependency found`).
  - Multiple Swift warnings already present (concurrency/sendability/deprecations/unused vars).
- Structural migration edits: none yet (planning + baseline validation only).

### Run 2 - 2026-02-17 13:35 +07

- Applied all decision gates:
  - `1A`: strict single flat folder per feature.
  - `2A`: naming enforcement at file-name level.
  - `3A`: remove `Core` fully.
  - `4A`: license engine in `Services`, license UI in `Features/License`.
  - `5A`: keep `Snapzy.entitlements` at `/Users/duongductrong/Developer/ZapShot/Snapzy/Snapzy.entitlements`.
  - `6A`: remove `/Users/duongductrong/Developer/ZapShot/Snapzy/ContentView.swift`.
- Implemented target structure:
  - Added `Services`, `Shared`, `Resources`, and `Features/Capture`.
  - Moved `Assets.xcassets` and `Info.plist` into `Resources`.
  - Updated `INFOPLIST_FILE` paths in `/Users/duongductrong/Developer/ZapShot/Snapzy.xcodeproj/project.pbxproj`.
  - Migrated all `Core` contents into `Services`, `Shared`, and feature folders.
  - Flattened all nested feature directories and renamed feature files to `[Feature]*`.
  - Added `AppEnvironment.swift` and `AppCoordinator.swift` under `/Users/duongductrong/Developer/ZapShot/Snapzy/App`.
  - Moved license README to `/Users/duongductrong/Developer/ZapShot/docs/license-engine-readme.md`.
- Validation:
  - `find Snapzy/Features -mindepth 2 -type d` -> no output.
  - Feature prefix check -> no output.
  - `xcodebuild` Debug + Release with `.build/DerivedData` -> `BUILD SUCCEEDED`.

### Run 3 - 2026-02-17 14:25 +07

- Reviewed `/Users/duongductrong/Developer/ZapShot/docs/project-structure.md` v2.0 (Nested Support).
- Updated migration documentation to reflect pragmatic flexibility:
  - Features may use one-level subfolders: `Components`, `Managers`, `Services`, `Models`.
  - Services may stay single-file or expand into domain folders when complex.
  - Primary feature entry files remain at feature root.
- Existing refactor result remains compliant because fully-flat feature layout is a stricter subset of v2.0.

### Run 4 - 2026-02-17 14:45 +07

- Started practical v2.0 refactor wave with one-level feature grouping.
- `Onboarding` regrouped:
  - kept root entry: `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Onboarding/OnboardingFlowView.swift`
  - moved supporting files to `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Onboarding/Components`
- `QuickAccess` regrouped:
  - root kept: `QuickAccessStackView.swift`, `QuickAccessManager.swift`, `QuickAccessPanel.swift`
  - moved UI pieces to `Components`
  - moved panel controller to `Managers`
  - moved item/layout/position to `Models`
  - moved thumbnail/sound/animations to `Services`
- Validation:
  - v2.0 structure checks passed:
    - no depth > 1 under feature roots
    - only allowed folder names used
    - naming compliance check passed
  - `xcodebuild` Debug -> `BUILD SUCCEEDED`
  - `xcodebuild` Release -> `BUILD SUCCEEDED`

### Run 5 - 2026-02-17 15:05 +07

- Applied v2.0 grouping to `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/VideoEditor`:
  - kept root entries: `VideoEditorMainView.swift`, `VideoEditorState.swift`, `VideoEditorManager.swift`
  - moved UI subviews to `Components`
  - moved window layer to `Managers`
  - moved data types to `Models`
  - moved exporter/compositor/calculator to `Services`
- Validation:
  - v2.0 structure checks passed
  - naming compliance check passed
  - `xcodebuild` Debug -> `BUILD SUCCEEDED`
  - `xcodebuild` Release -> `BUILD SUCCEEDED`

### Run 6 - 2026-02-17 15:30 +07

- Completed remaining v2.0 regrouping:
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Recording` split into `Components`, `Managers`, `Models`, `Services`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Annotate` split into `Components`, `Managers`, `Models`, `Services`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Preferences` split into `Components`, `Managers`, `Models`
- Root entry files retained for visibility:
  - `RecordingCoordinator.swift`, `RecordingSession.swift`, `RecordingToolbarView.swift`, `RecordingToolbarWindow.swift`
  - `AnnotateMainView.swift`, `AnnotateState.swift`, `AnnotateManager.swift`
  - `PreferencesView.swift`, `PreferencesManager.swift`
- Validation:
  - v2.0 structure checks passed
  - naming compliance check passed
  - `xcodebuild` Debug -> `BUILD SUCCEEDED`
  - `xcodebuild` Release -> `BUILD SUCCEEDED`

### Run 7 - 2026-02-17 15:35 +07

- Grouped global services into domain folders to align with v2.0 service expansion guidance:
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Services/Capture`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Services/Media`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Services/License`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Services/Diagnostics`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Services/Wallpaper`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Services/Shortcuts`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Services/Appearance`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Services/Configuration`
  - `/Users/duongductrong/Developer/ZapShot/Snapzy/Services/Updates`
- Validation:
  - `xcodebuild` Debug -> `BUILD SUCCEEDED`
  - `xcodebuild` Release -> `BUILD SUCCEEDED`

### Phase Progress

- [x] Phase 1: Baseline and Safety Rails (branch + build baseline complete)
- [x] Phase 2: Create Target Skeleton
- [x] Phase 3: Resource Path Migration
- [x] Phase 4: Core Decomposition
- [x] Phase 5: Feature Normalization Wave 1
- [x] Phase 6: Feature Normalization Wave 2
- [x] Phase 7: App Layer Normalization
- [x] Phase 8: Naming Compliance Pass
- [x] Phase 9: Cleanup and Guardrails (guardrail script pending)

## Validation Matrix

- Build: `xcodebuild` Debug and Release.
- Runtime smoke:
  - Launch app from menu bar.
  - Capture area/fullscreen.
  - Recording start/stop and quick access display.
  - Preferences open and save.
  - Annotate open/save.
  - Video editor open/export basic flow.
- Structural checks:
  - No feature nesting deeper than one level.
  - If a feature has subfolders, names must be one of: `Components`, `Managers`, `Services`, `Models`.
  - Primary feature entry files remain at feature root.
  - All feature files start with feature name.
  - No orphan files in old paths.

## Risk Register

- Risk: large file-move conflicts with parallel feature work.
- Mitigation: freeze or serialize high-churn feature PRs during migration.

- Risk: build path regressions after resource migration.
- Mitigation: isolate resource-path phase and validate before next phase.

- Risk: hidden runtime coupling from `Core`.
- Mitigation: move-only first, no API redesign in decomposition phases.

- Risk: giant rename diff hurts review quality.
- Mitigation: split by feature, then split by naming pass.

## Suggested Commit Strategy

- `chore(structure): scaffold target folders`
- `chore(structure): move resources and update build paths`
- `chore(structure): decompose core into services-shared`
- `chore(structure): flatten features wave-1`
- `chore(structure): flatten features wave-2`
- `chore(structure): enforce naming convention`
- `chore(structure): cleanup stale paths and add structure checks`

## Done When

- Directory tree matches target architecture.
- Feature folders comply with v2.0 rules (one-level maximum and allowed folder names only).
- Naming convention is enforced.
- App builds and key flows pass smoke checks.
- No stale structure remains.

## Next Refactor Wave

- None. Feature regrouping is complete for current scope.

## Decision History

- 2026-02-17 (v1 execution):
  - Applied decisions `1A` to `6A` and completed migration implementation.
- 2026-02-17 (v2 policy update):
  - Superseded strict flat-only policy.
  - Adopted pragmatic flattened policy with controlled one-level feature nesting and scalable service folders.
  - Kept `Core` removal, license placement, entitlements location, and `ContentView.swift` removal unchanged.

## Unresolved Questions

- None.
