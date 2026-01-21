# Phase 1: Audio State Properties

## Context

- [Plan](./plan.md)

## Overview

Add audio control properties to VideoEditorState and sync with AVPlayer.

## Requirements

1. Add `isMuted` property to toggle audio
2. Sync mute state with AVPlayer.isMuted
3. Track audio changes for unsaved state detection

## Implementation Steps

### Step 1: Add Audio Properties

Add to VideoEditorState after Trim Range section:

```swift
// MARK: - Audio Control

@Published var isMuted: Bool = false {
  didSet {
    player.isMuted = isMuted
  }
}
private var initialIsMuted: Bool = false
```

### Step 2: Add Toggle Method

```swift
func toggleMute() {
  isMuted.toggle()
}
```

### Step 3: Update Change Tracking

Modify `setupTrimChangeTracking` to include audio state:

```swift
private func setupChangeTracking() {
  Publishers.CombineLatest3($trimStart, $trimEnd, $isMuted)
    .dropFirst()
    .sink { [weak self] start, end, muted in
      guard let self = self else { return }
      let startChanged = CMTimeCompare(start, self.initialTrimStart) != 0
      let endChanged = CMTimeCompare(end, self.initialTrimEnd) != 0
      let muteChanged = muted != self.initialIsMuted
      self.hasUnsavedChanges = startChanged || endChanged || muteChanged
    }
    .store(in: &cancellables)
}
```

### Step 4: Update markAsSaved

```swift
func markAsSaved() {
  hasUnsavedChanges = false
  initialTrimStart = trimStart
  initialTrimEnd = trimEnd
  initialIsMuted = isMuted
}
```

## Todo List

- [ ] Add isMuted property with didSet
- [ ] Add initialIsMuted for change tracking
- [ ] Add toggleMute() method
- [ ] Update change tracking to include audio
- [ ] Update markAsSaved to reset audio initial state

## Success Criteria

- isMuted toggles player audio immediately
- hasUnsavedChanges reflects audio changes
- markAsSaved resets audio initial state
