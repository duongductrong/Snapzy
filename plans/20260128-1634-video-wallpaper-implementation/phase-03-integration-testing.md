# Phase 3: Integration & Testing

**Date:** 2026-01-28
**Status:** Pending
**Priority:** Medium
**Estimated:** 1 hour

## Context Links

- [Main Plan](./plan.md)
- [Phase 2: Wallpaper Sidebar](./phase-02-wallpaper-sidebar-section.md)

## Overview

Verify wallpaper backgrounds render correctly in video preview, test undo/redo functionality, and ensure no performance regression during video playback.

## Key Insights

1. Video rendering likely uses same `BackgroundStyle` switch logic as Annotate
2. Undo/redo already implemented via `EditorAction.updateBackground`
3. Performance concern: wallpaper images should be cached for video export

## Requirements

- [ ] Verify wallpaper renders in video preview canvas
- [ ] Test undo/redo with wallpaper changes
- [ ] Verify export includes wallpaper background
- [ ] Check playback performance with wallpaper

## Related Code Files

| File | Purpose |
|------|---------|
| `/ClaudeShot/Features/VideoEditor/Views/VideoPreviewCanvas.swift` | Preview rendering |
| `/ClaudeShot/Features/VideoEditor/Export/VideoExporter.swift` | Export logic |

## Implementation Steps

### Step 1: Verify Preview Canvas Handles Wallpaper

Check if `VideoPreviewCanvas` or equivalent handles `BackgroundStyle.wallpaper(URL)`.

**Expected location:** Look for switch on `backgroundStyle` in preview view.

If missing, add wallpaper rendering case:

```swift
case .wallpaper(let url):
  AsyncImage(url: url) { phase in
    if case .success(let image) = phase {
      image
        .resizable()
        .aspectRatio(contentMode: .fill)
    }
  }
```

### Step 2: Test Scenarios

#### Manual Test Cases

| Test | Steps | Expected |
|------|-------|----------|
| Select system wallpaper | Click wallpaper thumbnail | Preview shows wallpaper, padding auto-applies |
| Select custom wallpaper | Click +, pick image | Image appears in grid and preview |
| Change wallpaper | Select different wallpaper | Preview updates immediately |
| Undo wallpaper | Cmd+Z after wallpaper select | Reverts to previous background |
| Redo wallpaper | Cmd+Shift+Z after undo | Wallpaper reapplied |
| Export with wallpaper | Export video | Wallpaper visible in output |
| Playback performance | Play video with wallpaper | Smooth playback, no stuttering |

### Step 3: Performance Verification

1. **Image caching:** Wallpaper should load once, not per frame
2. **Memory usage:** Monitor with Instruments during playback
3. **Export time:** Should not significantly increase

### Step 4: Edge Cases

| Scenario | Expected Behavior |
|----------|-------------------|
| Wallpaper file deleted | Graceful fallback (show placeholder or none) |
| Very large image (8K) | Should downscale for preview |
| Network path wallpaper | Handle timeout gracefully |
| Rapid wallpaper switching | No crashes, last selection wins |

## Success Criteria

- [ ] Wallpaper visible in video preview
- [ ] Wallpaper renders correctly with padding/shadow/corners
- [ ] Undo/redo cycles work correctly
- [ ] Export produces video with wallpaper
- [ ] No frame drops during playback
- [ ] Memory usage stable over time

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Export not including wallpaper | Medium | High | Verify VideoExporter handles .wallpaper case |
| Slow preview with large images | Low | Medium | Use thumbnail for preview, full for export |
| Memory leak with AsyncImage | Low | Medium | Test with Instruments |

## Compile & Run Commands

```bash
# Build project
xcodebuild -scheme ClaudeShot -configuration Debug build

# Run tests if available
xcodebuild -scheme ClaudeShot -configuration Debug test
```

## Post-Implementation Checklist

- [ ] All manual tests pass
- [ ] No compiler warnings related to new code
- [ ] Code follows existing patterns
- [ ] No memory leaks detected
- [ ] Export quality verified
