# Phase 3: Timeline Scrubbing and Trim Handles

## Context

- [Plan](./plan.md)
- [Phase 2](./phase-02-timeline-with-frame-previews.md)
- [SwiftUI Timeline Research](./research/researcher-02-swiftui-timeline-ui.md)

## Overview

Add interactive scrubbing (drag playhead to seek) and trim handles (adjust start/end points). Users can drag the playhead to scrub through video and use trim handles to define export range.

## Requirements

1. Drag playhead to scrub video position
2. Trim handles at start and end of timeline
3. Visual feedback for trim region (highlighted/dimmed areas)
4. Handles constrain to valid range (start < end, minimum duration)
5. Track trim changes for unsaved state

## Architecture Decisions

- **Gesture Priority**: Use `.highPriorityGesture` on handles to prevent conflicts
- **Minimum Trim**: Enforce 1 second minimum between start and end
- **Visual Feedback**: Dim areas outside trim range, highlight active region
- **Handle Size**: 12pt width, 60pt height for easy targeting
- **Debounce Seeks**: During scrub, limit seek calls to prevent stuttering

## Related Files

| File | Action |
|------|--------|
| `ZapShot/Features/VideoEditor/Views/VideoTrimHandlesView.swift` | Create |
| `ZapShot/Features/VideoEditor/Views/VideoTimelineView.swift` | Modify |
| `ZapShot/Features/VideoEditor/State/VideoEditorState.swift` | Modify |

## Implementation Details

- [State Changes](./phase-03-state-changes.md) - Trim state and scrubbing methods
- [Trim Handles View](./phase-03-trim-handles-view.md) - UI component implementation

## Todo List

- [ ] Add trimStart, trimEnd, isScrubbing to state
- [ ] Implement setTrimStart/setTrimEnd with constraints
- [ ] Implement scrub() and endScrubbing() methods
- [ ] Create TrimHandle subview
- [ ] Create VideoTrimHandlesView with gestures
- [ ] Add dimmed overlay for trimmed regions
- [ ] Add scrubbing gesture to timeline
- [ ] Integrate trim handles into VideoTimelineView
- [ ] Test handle constraints (min duration)
- [ ] Test scrubbing performance

## Success Criteria

- Drag playhead seeks video smoothly
- Trim handles draggable with visual feedback
- Cannot drag start past end (and vice versa)
- Minimum 1 second between handles enforced
- hasUnsavedChanges set when trim modified

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Gesture conflicts | Use highPriorityGesture on handles |
| Seek stuttering | Debounce during drag, use zero tolerance |
| Handle too small | 12x60pt handle, larger hit area with padding |
