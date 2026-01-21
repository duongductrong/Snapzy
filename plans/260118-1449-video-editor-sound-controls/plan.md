# Video Editor Sound Controls Implementation Plan

## Overview

Add audio/sound controls to the Video Editor allowing users to mute or adjust volume during preview and optionally export video without audio track.

## Architecture

```
VideoEditorState
    |-- isMuted: Bool (toggle for mute)
    |-- removeAudioOnExport: Bool (strip audio from export)
    |-- player.isMuted (sync with state)

VideoControlsView
    |-- Mute/Unmute toggle button
    |-- "Remove Audio" checkbox indicator

VideoEditorExporter
    |-- Export with/without audio based on state
```

## Files to Modify

| File | Changes |
|------|---------|
| `State/VideoEditorState.swift` | Add `isMuted`, `removeAudioOnExport` properties, sync with player |
| `Views/VideoControlsView.swift` | Add mute button and audio indicator |
| `Export/VideoEditorExporter.swift` | Add option to export without audio track |

## Implementation Phases

| Phase | Status | Description |
|-------|--------|-------------|
| [Phase 1](./phase-01-audio-state.md) | ✅ completed | Add audio state to VideoEditorState |
| [Phase 2](./phase-02-audio-ui.md) | ✅ completed | Add mute button to VideoControlsView |
| [Phase 3](./phase-03-export-without-audio.md) | ✅ completed | Modify exporter to strip audio |

## Success Criteria

- Mute button toggles audio during playback
- Visual indicator shows muted state
- "Remove Audio" option available for export
- Export without audio produces video-only file
- Audio changes tracked as unsaved changes

## Design Decision

**Simplified approach**: Single mute toggle that:
1. Mutes playback preview
2. When muted, exported video has no audio track
3. No volume slider (KISS principle - users want mute, not fine control)
