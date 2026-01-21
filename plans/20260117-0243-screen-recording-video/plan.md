# Screen Recording Video Feature - Implementation Plan

## Overview
Add screen recording with area selection to ZapShot. Uses ScreenCaptureKit SCStream + AVAssetWriter for video capture, reuses existing area selection system, adds recording UI components and preferences.

## Status Tracking
| Phase | Status | Description |
|-------|--------|-------------|
| 1 | ✅ completed | Core Recording Engine |
| 2 | ✅ completed | Keyboard Shortcut Integration |
| 3 | ✅ completed | Recording UI Components |
| 4 | ✅ completed | Preferences Tab |
| 5 | ✅ completed | Onboarding Updates |
| 6 | ✅ completed | Integration Testing |
| 7 | ✅ completed | Code Review |

## Code Review (2026-01-17)
**Status:** ✅ All high-priority issues fixed
**Build:** ✅ SUCCESS
**Reports:**
- [Full Review Report](./reports/260117-code-review-report.md)
- [Executive Summary](./reports/260117-review-summary.md)
- [Issue Tracker](./reports/260117-issue-tracker.md)

**Key Findings:**
- 0 critical bugs
- 4 high-priority issues (concurrency, missing implementations) - **ALL FIXED**
- 6 moderate issues (optimizations, edge cases)
- Build succeeds, no compilation errors
- Strong architecture, clean code structure

**Fixes Applied:**
1. ✅ Moved frame processing off main thread to processingQueue
2. ✅ Added NSLock for thread-safe sessionStarted/isCapturing flags
3. ✅ Implemented VideoQuality enum with bitrate multipliers
4. ✅ Added user-facing error alerts in RecordingCoordinator

## Phase Documents
- [Phase 1: Core Recording Engine](./phase-01-core-recording-engine.md)
- [Phase 2: Keyboard Shortcut Integration](./phase-02-keyboard-shortcut-integration.md)
- [Phase 3: Recording UI Components](./phase-03-recording-ui-components.md)
- [Phase 4: Preferences Tab](./phase-04-preferences-tab.md)
- [Phase 5: Onboarding Updates](./phase-05-onboarding-updates.md)
- [Phase 6: Integration Testing](./phase-06-integration-testing.md)

## Architecture Summary
```
ScreenRecordingManager (SCStream + AVAssetWriter)
    |
    v
RecordingToolbarWindow --> RecordingToolbarView (pre-record)
    |                      RecordingStatusBarView (during-record)
    v
AreaSelectionController (reuse, add SelectionMode)
    |
    v
KeyboardShortcutManager (add .recordVideo action)
```

## Key Dependencies
- macOS 12.3+ (ScreenCaptureKit)
- Existing: AreaSelectionController, KeyboardShortcutManager, PreferencesKeys

## New Files
| Path | Purpose |
|------|---------|
| `Core/ScreenRecordingManager.swift` | SCStream + AVAssetWriter recording engine |
| `Features/Recording/RecordingToolbarView.swift` | Pre-record toolbar UI |
| `Features/Recording/RecordingStatusBarView.swift` | During-record status bar |
| `Features/Recording/RecordingToolbarWindow.swift` | Floating window controller |
| `Features/Preferences/Tabs/RecordingSettingsView.swift` | Recording preferences |

## Modified Files
| Path | Changes |
|------|---------|
| `Core/KeyboardShortcutManager.swift` | Add recordVideo action, recording shortcut |
| `Core/AreaSelectionWindow.swift` | Add SelectionMode enum |
| `App/ZapShotApp.swift` | Add Record Screen menu item |
| `Features/Preferences/PreferencesView.swift` | Replace placeholder with RecordingSettingsView |
| `Features/Preferences/PreferencesKeys.swift` | Add recording keys |
| `Features/Onboarding/*` | Mention recording feature |

## Research References
- [Screen Recording APIs](./research/researcher-01-screen-recording-apis.md)
- [Recording UI Patterns](./research/researcher-02-recording-ui-patterns.md)
- [Codebase Analysis](./scout/scout-01-codebase-analysis.md)

## Risk Summary
1. **Audio sync issues** - Mitigate with proper CMSampleBuffer timing
2. **Permission handling** - Reuse existing SCShareableContent flow
3. **Memory pressure** - Use background queue for frame processing
4. **Multi-monitor** - Test area selection across displays

## Estimated Effort
- Phase 1: 4-6 hours (most complex)
- Phase 2: 1-2 hours
- Phase 3: 3-4 hours
- Phase 4: 1-2 hours
- Phase 5: 1 hour
- Phase 6: 2-3 hours
- **Total: 12-18 hours**
