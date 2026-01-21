# Screen Recording MVP - Implementation Plan

## Context
- **Parent:** ZapShot macOS App
- **Type:** Menu Bar Agent (LSUIElement)
- **Tech:** SwiftUI, ScreenCaptureKit (macOS 12.3+)
- **Status:** Screenshot & Annotation implemented

## Summary
Add screen recording capability to ZapShot. User triggers via `Cmd+Shift+5`, selects area/fullscreen, records with optional mic audio, stops via menu bar or floating timer. Post-recording shows thumbnail with Copy/Save actions; click opens VideoEditorStub.

## Phases

| # | Phase | File | Status | Progress |
|---|-------|------|--------|----------|
| 1 | Core Recording Engine | [phase-01](./phase-01-core-recording-engine.md) | completed | 100% |
| 2 | Keyboard Shortcut Integration | [phase-02](./phase-02-keyboard-shortcut-integration.md) | completed | 100% |
| 3 | Recording Toolbar UI | [phase-03](./phase-03-recording-toolbar-ui.md) | completed | 100% |
| 4 | Active Recording State | [phase-04](./phase-04-active-recording-state.md) | completed | 100% |
| 5 | Post-Recording Flow | [phase-05](./phase-05-post-recording-flow.md) | completed | 100% |

## Dependencies
- Phase 1 must complete before 3, 4
- Phase 2 can run parallel with 1
- Phase 3 depends on 1 (needs ScreenRecorderManager)
- Phase 4 depends on 1, 3
- Phase 5 depends on 1, 4

## Files to Create
- `ZapShot/Core/ScreenRecorderManager.swift`
- `ZapShot/Features/Recording/RecordingToolbarView.swift`
- `ZapShot/Features/Recording/RecordingToolbarController.swift`
- `ZapShot/Features/Recording/RecordingTimerView.swift`
- `ZapShot/Features/Recording/VideoEditorStubView.swift`
- `ZapShot/Features/Recording/VideoThumbnailGenerator.swift`

## Files to Modify
- `ZapShot/Core/KeyboardShortcutManager.swift` - Add recording shortcut
- `ZapShot/Features/Preferences/Tabs/ShortcutsSettingsView.swift` - Add shortcut row
- `ZapShot/Features/Onboarding/Views/ShortcutsView.swift` - Display new shortcut
- `ZapShot/App/ZapShotApp.swift` - Add menu item, handle recording state
- `ZapShot/Features/FloatingScreenshot/FloatingCardView.swift` - Support video type

## Estimated Effort
- Phase 1: 4-6 hours (complex - AVAssetWriter, audio mixing)
- Phase 2: 1-2 hours (straightforward - existing patterns)
- Phase 3: 2-3 hours (UI + window management)
- Phase 4: 2-3 hours (state management, timer)
- Phase 5: 2-3 hours (thumbnail gen, routing)
- **Total:** 11-17 hours

## Risk Summary
1. **Audio sync** - System + mic audio timing can drift
2. **Permission UX** - Both screen + mic permissions needed
3. **Memory** - Long recordings need efficient buffer handling
4. **File size** - H.264 compression settings critical

## Unresolved Questions
1. Should `AreaSelectionController` be extended or create separate `RecordingSelectionController`?
2. Max recording duration limit for MVP?
3. Should timer view be optional preference or always shown?
