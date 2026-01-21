# Phase 05: Recording Integration

**Date:** 2026-01-17
**Priority:** High
**Status:** Pending

## Context Links

- [Plan Overview](./plan.md)
- [Scout Report](./scout/scout-01-codebase-analysis.md)

## Overview

Integrate RecordingCoordinator with QuickAccessManager to show video recordings in quick access stack after recording stops.

## Requirements

### Functional
- After recording stops, add video to QuickAccess stack
- Replace current Finder reveal behavior
- Play sound feedback on completion

### Non-Functional
- Non-blocking async integration
- Maintain existing cleanup flow

## Related Code Files

### Files to Modify
| File | Action | Description |
|------|--------|-------------|
| `/Users/duongductrong/Developer/ZapShot/ZapShot/Features/Recording/RecordingCoordinator.swift` | MODIFY | Add QuickAccess integration |

## Implementation Steps

### Step 1: Update stopRecording method

Replace current implementation in `RecordingCoordinator.swift`:

**Current code (lines 188-201):**
```swift
private func stopRecording() {
  Task {
    let url = await recorder.stopRecording()

    if let url = url {
      // Play sound
      NSSound(named: "Glass")?.play()

      // Show in Finder
      NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    cleanup()
  }
}
```

**New code:**
```swift
private func stopRecording() {
  Task {
    let url = await recorder.stopRecording()

    if let url = url {
      // Play sound
      NSSound(named: "Glass")?.play()

      // Add to QuickAccess stack
      await QuickAccessManager.shared.addVideo(url: url)
    }

    cleanup()
  }
}
```

## Todo List

- [ ] Update `stopRecording()` in RecordingCoordinator
- [ ] Replace Finder reveal with QuickAccessManager.addVideo()
- [ ] Verify video appears in QuickAccess after recording
- [ ] Test full recording flow end-to-end

## Success Criteria

- [ ] Recording completes and video appears in QuickAccess
- [ ] Thumbnail shows first frame of video
- [ ] Duration badge displays correct time
- [ ] Copy/Save actions work
- [ ] Double-click opens video editor placeholder
- [ ] Sound plays on completion

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Thumbnail generation fails | Low | QuickAccess handles gracefully |
| Video not added to stack | Low | Guard checks in addVideo() |

## Testing Checklist

1. Start area recording
2. Record for 5-10 seconds
3. Stop recording
4. Verify:
   - Sound plays
   - Video card appears in QuickAccess
   - Thumbnail shows video frame
   - Duration badge shows correct time
   - Hover shows Copy/Save buttons
   - Copy puts video URL in clipboard
   - Save reveals in Finder
   - Double-click opens placeholder editor

## Next Steps

After completing all phases:
1. Run full test suite
2. Delegate to `code-reviewer` agent
3. Update documentation if needed
