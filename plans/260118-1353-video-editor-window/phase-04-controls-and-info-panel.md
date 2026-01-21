# Phase 4: Controls and Info Panel

## Context

- [Plan](./plan.md)
- [Phase 3](./phase-03-timeline-scrubbing-and-trim.md)
- [Codebase Scout](./scout/scout-01-codebase-structure.md)

## Overview

Add playback controls (play/pause button, time display) and essential info panel showing video metadata. Controls appear below timeline, info panel shows filename, duration, resolution, and format.

## Requirements

1. Play/pause toggle button with icon state
2. Time display: current time / total duration
3. Info panel with: filename, trimmed duration, resolution, format
4. Keyboard shortcut: Space to toggle playback
5. Clean dark theme styling matching existing UI

## Architecture Decisions

- **Time Format**: MM:SS for videos under 1 hour, HH:MM:SS otherwise
- **Layout**: Controls centered below timeline, info panel below controls
- **Icons**: SF Symbols (play.fill, pause.fill)
- **Keyboard**: Monitor keyDown in window controller, forward to state

## Related Files

| File | Action |
|------|--------|
| `ZapShot/Features/VideoEditor/Views/VideoControlsView.swift` | Create |
| `ZapShot/Features/VideoEditor/Views/VideoInfoPanel.swift` | Create |
| `ZapShot/Features/VideoEditor/Views/VideoEditorMainView.swift` | Modify |
| `ZapShot/Features/VideoEditor/State/VideoEditorState.swift` | Modify |

## Implementation Details

- [Controls View](./phase-04-controls-view.md) - Play/pause and time display
- [Info Panel](./phase-04-info-panel.md) - Metadata display component
- [Keyboard Shortcuts](./phase-04-keyboard-shortcuts.md) - Space key handling

## Todo List

- [ ] Add play/pause/toggle methods to state
- [ ] Add end-of-playback observer
- [ ] Create VideoControlsView with play button and time
- [ ] Implement time formatting (MM:SS / HH:MM:SS)
- [ ] Create InfoItem helper view
- [ ] Create VideoInfoPanel with metadata display
- [ ] Integrate controls and info into main view
- [ ] Add Space key handler for play/pause
- [ ] Test playback controls
- [ ] Test info panel updates with trim changes

## Success Criteria

- Play/pause button toggles playback with icon update
- Time display shows current/total and updates during playback
- Info panel shows accurate file metadata
- Duration updates when trim range changes
- Space key toggles playback

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Time display flicker | Use monospaced font for stable width |
| Key event not received | Ensure window is key, use local monitor |
| End notification missed | Re-register observer if player item changes |
