# Phase 2: Annotation Toggle in Recording Toolbar/StatusBar

- **Date**: 2026-02-09
- **Priority**: High
- **Status**: Pending

## Overview
Add a pencil/markup icon button to `RecordingStatusBarView` (during recording) that toggles annotation mode on/off. When active, shows the floating annotation toolbar and transparent overlay.

## Key Insights
- Button goes in `RecordingStatusBarView` only (not pre-record toolbar)
- Uses existing `ToolbarIconButton` component for consistent style
- Toggle state lives in `RecordingAnnotationState.isAnnotationEnabled`
- RecordingToolbarState needs reference to annotation state

## Requirements
1. Add annotate toggle button to RecordingStatusBarView
2. Button icon: `pencil.tip.crop.circle` (inactive) / `pencil.tip.crop.circle.fill` (active)
3. Position: after pause button, before restart button
4. Visual: highlighted when active (matches existing hover pattern)

## Implementation Steps

### 1. Update RecordingStatusBarView.swift
Add annotation toggle between pause and restart buttons:
```swift
// After pause/resume button divider
ToolbarIconButton(
  systemName: annotationState.isAnnotationEnabled
    ? "pencil.tip.crop.circle.fill"
    : "pencil.tip.crop.circle",
  action: { annotationState.isAnnotationEnabled.toggle() },
  accessibilityLabel: annotationState.isAnnotationEnabled
    ? "Disable annotations"
    : "Enable annotations"
)
```

### 2. Pass RecordingAnnotationState
- RecordingStatusBarView gets `@ObservedObject var annotationState: RecordingAnnotationState`
- RecordingToolbarWindow holds reference, passes to status bar view

## Related Code Files
- `Snapzy/Features/Recording/RecordingStatusBarView.swift` (modify)
- `Snapzy/Features/Recording/RecordingToolbarWindow.swift` (modify — pass annotation state)
- `Snapzy/Features/Recording/Components/ToolbarIconButton.swift` (reuse as-is)

## Success Criteria
- Toggle button visible during recording
- Button toggles `isAnnotationEnabled` state
- Visual feedback shows active/inactive state
