# Phase 2: Audio UI Controls

## Context

- [Plan](./plan.md)
- [Phase 1](./phase-01-audio-state.md)

## Overview

Add mute toggle button to VideoControlsView with visual indicator.

## Requirements

1. Mute/unmute button with speaker icon
2. Icon changes based on mute state (speaker.fill vs speaker.slash.fill)
3. Position: after play button, before time display
4. Keyboard shortcut: M key for quick toggle

## Implementation Steps

### Step 1: Add Mute Button to VideoControlsView

Insert after play button:

```swift
// Mute button
Button(action: { state.toggleMute() }) {
  Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
    .font(.system(size: 16))
    .foregroundColor(state.isMuted ? .red : .primary)
    .frame(width: 32, height: 32)
    .background(Color.white.opacity(0.1))
    .clipShape(Circle())
}
.buttonStyle(.plain)
.keyboardShortcut("m", modifiers: [])
.help(state.isMuted ? "Unmute (M)" : "Mute (M)")
```

## UI Layout

```
[Play] [Mute] | 00:15 / 02:30 |           [scissors icon] 01:45
```

## Todo List

- [ ] Add mute button after play button
- [ ] Use speaker.slash.fill when muted
- [ ] Add red color when muted
- [ ] Add M keyboard shortcut
- [ ] Add tooltip/help text

## Success Criteria

- Button visible next to play button
- Icon changes on toggle
- Red color indicates muted state
- M key toggles mute
