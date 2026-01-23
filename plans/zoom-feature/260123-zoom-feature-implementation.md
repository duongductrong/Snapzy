# Implementation Plan: Zoom Feature for ClaudeShot Video Editor

**Date:** 2026-01-23
**Status:** Pending Approval
**Complexity:** High (multi-phase, affects state, UI, and export pipeline)

---

## Executive Summary

Add Screen Studio-style zoom editing to ClaudeShot VideoEditor. Features include: interactive zoom blocks on dedicated timeline track, drag-to-resize duration, click-to-add zooms, zoom level slider, real-time preview, and zoom application during export.

**Key Constraints:**
- Must integrate with existing `VideoEditorState` pattern
- Must follow current SwiftUI + AVFoundation architecture
- Must apply zooms during export via AVFoundation composition
- Must support undo/redo through existing change tracking

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    VideoEditorMainView                       │
├─────────────────────────────────────────────────────────────┤
│  VideoPlayerSection                                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  AVPlayerView + ZoomPreviewOverlay (NEW)            │    │
│  │  (shows zoom effect in real-time)                   │    │
│  └─────────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────────┤
│  VideoTimelineView (MODIFIED)                                │
│  ├── VideoTimelineFrameStrip                                 │
│  ├── VideoTrimHandlesView                                    │
│  ├── ZoomTimelineTrack (NEW) ◄── Purple zoom blocks         │
│  └── Playhead                                                │
├─────────────────────────────────────────────────────────────┤
│  ZoomSettingsPopover (NEW) ◄── Appears on zoom selection    │
├─────────────────────────────────────────────────────────────┤
│  VideoControlsView + ZoomToggleButton (MODIFIED)             │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Data Model & State (Foundation)

### 1.1 Create Zoom Models

**File:** `ClaudeShot/Features/VideoEditor/Models/ZoomSegment.swift`

```swift
struct ZoomSegment: Identifiable, Codable, Equatable {
    let id: UUID
    var startTime: TimeInterval      // seconds
    var duration: TimeInterval       // seconds
    var zoomLevel: CGFloat           // 1.0 to 4.0
    var zoomCenter: CGPoint          // normalized 0-1
    var zoomType: ZoomType
    var isEnabled: Bool

    var endTime: TimeInterval { startTime + duration }

    static let defaultDuration: TimeInterval = 2.0
    static let defaultZoomLevel: CGFloat = 2.0
    static let minDuration: TimeInterval = 0.5
    static let maxZoomLevel: CGFloat = 4.0
}

enum ZoomType: String, Codable {
    case auto    // from click detection
    case manual  // user-defined
}
```

### 1.2 Extend VideoEditorState

**File:** `ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift`

Add properties:
```swift
// MARK: - Zoom Segments
@Published var zoomSegments: [ZoomSegment] = []
@Published var selectedZoomId: UUID? = nil
@Published var isZoomTrackVisible: Bool = true

// Track initial state for change detection
private var initialZoomSegments: [ZoomSegment] = []
```

Add methods:
```swift
// MARK: - Zoom Management
func addZoom(at time: TimeInterval) -> UUID
func removeZoom(id: UUID)
func updateZoom(id: UUID, ...)
func selectZoom(id: UUID?)
func toggleZoomEnabled(id: UUID)
func zoomSegment(at time: TimeInterval) -> ZoomSegment?
```

Update change tracking to include zooms.

### 1.3 Create ZoomCalculator Utility

**File:** `ClaudeShot/Features/VideoEditor/Utils/ZoomCalculator.swift`

```swift
enum ZoomCalculator {
    static func calculateCropRect(
        center: CGPoint,
        zoomLevel: CGFloat,
        frameSize: CGSize
    ) -> CGRect

    static func easeInOutCubic(_ t: Double) -> Double

    static func interpolateZoom(
        segment: ZoomSegment,
        currentTime: TimeInterval
    ) -> (level: CGFloat, center: CGPoint, progress: Double)
}
```

---

## Phase 2: Zoom Timeline Track (Core UI)

### 2.1 Create ZoomBlockView

**File:** `ClaudeShot/Features/VideoEditor/Views/Zoom/ZoomBlockView.swift`

Purple rounded rectangle showing:
- Zoom icon + level (e.g., "2x")
- Type indicator (Auto/Manual badge)
- Drag handles on edges (visible on hover)
- Selected state styling

Interactions:
- Click to select
- Drag edges to resize duration
- Drag center to move position
- Right-click context menu (Disable/Remove)

### 2.2 Create ZoomTimelineTrack

**File:** `ClaudeShot/Features/VideoEditor/Views/Zoom/ZoomTimelineTrack.swift`

```swift
struct ZoomTimelineTrack: View {
    @ObservedObject var state: VideoEditorState
    let timelineWidth: CGFloat
    let trackHeight: CGFloat = 32

    // Click on empty area → add new zoom
    // Render zoom blocks at correct positions
    // Handle overlapping zooms (later zoom takes priority)
}
```

### 2.3 Modify VideoTimelineView

Add zoom track below frame strip:
```swift
VStack(spacing: 4) {
    // Existing frame strip + trim handles + playhead
    ZStack { ... }

    // NEW: Zoom track
    if state.isZoomTrackVisible {
        ZoomTimelineTrack(state: state, timelineWidth: timelineWidth)
    }
}
```

Increase total height to accommodate zoom track.

---

## Phase 3: Zoom Settings UI

### 3.1 Create ZoomSettingsPopover

**File:** `ClaudeShot/Features/VideoEditor/Views/Zoom/ZoomSettingsPopover.swift`

Appears when zoom is selected. Contains:
- Zoom level slider (100% - 400%)
- Zoom center picker (preview with draggable point)
- Duration display
- Type badge (Auto/Manual)
- Enable/Disable toggle
- Delete button

### 3.2 Create ZoomCenterPicker

**File:** `ClaudeShot/Features/VideoEditor/Views/Zoom/ZoomCenterPicker.swift`

Mini video frame preview with:
- Crosshair at current zoom center
- Draggable to reposition
- Shows zoom boundary rectangle

---

## Phase 4: Real-Time Preview

### 4.1 Create ZoomPreviewLayer

**File:** `ClaudeShot/Features/VideoEditor/Views/Zoom/ZoomPreviewOverlay.swift`

Overlay on VideoPlayerSection that:
- Monitors `currentTime` from state
- Checks if any zoom segment is active
- Applies visual zoom effect (scale + translate) to preview area
- Uses smooth easing during zoom-in/out transitions

### 4.2 Modify VideoPlayerSection

Wrap AVPlayerView with zoom preview capability:
```swift
ZStack {
    AVPlayerViewWrapper(player: player)
        .scaleEffect(currentZoomScale)
        .offset(zoomOffset)
        .animation(.easeInOut(duration: 0.3), value: currentZoomScale)
}
```

---

## Phase 5: Export with Zoom Effects

### 5.1 Create ZoomCompositor

**File:** `ClaudeShot/Features/VideoEditor/Export/ZoomCompositor.swift`

```swift
class ZoomCompositor {
    func createZoomedComposition(
        asset: AVAsset,
        zooms: [ZoomSegment],
        timeRange: CMTimeRange
    ) async throws -> AVMutableComposition

    func createVideoComposition(
        for composition: AVMutableComposition,
        zooms: [ZoomSegment],
        renderSize: CGSize
    ) -> AVMutableVideoComposition
}
```

Uses `AVMutableVideoCompositionInstruction` with custom compositor or `AVVideoCompositionCoreAnimationTool` for zoom transforms.

### 5.2 Modify VideoEditorExporter

Update `exportTrimmed` to:
1. Check if zooms exist
2. If yes, use ZoomCompositor to create composition
3. Apply zoom transforms via AVVideoComposition
4. Export with video composition

---

## Phase 6: Polish & Edge Cases

### 6.1 Keyboard Shortcuts
- `Z` - Add zoom at playhead
- `Delete/Backspace` - Remove selected zoom
- `Escape` - Deselect zoom

### 6.2 Edge Case Handling
- Zoom extending past trim boundaries → clamp to trim range
- Overlapping zooms → later zoom takes priority
- Zoom center outside frame → clamp to valid area
- Very short zooms (< 0.5s) → enforce minimum

### 6.3 Undo/Redo Integration
- Track zoom changes in change tracking
- Add to hasUnsavedChanges computation

---

## File Structure

```
ClaudeShot/Features/VideoEditor/
├── Models/
│   └── ZoomSegment.swift (NEW)
├── State/
│   └── VideoEditorState.swift (MODIFIED)
├── Utils/
│   └── ZoomCalculator.swift (NEW)
├── Views/
│   ├── VideoTimelineView.swift (MODIFIED)
│   ├── VideoPlayerSection.swift (MODIFIED)
│   └── Zoom/ (NEW DIRECTORY)
│       ├── ZoomTimelineTrack.swift
│       ├── ZoomBlockView.swift
│       ├── ZoomSettingsPopover.swift
│       ├── ZoomCenterPicker.swift
│       └── ZoomPreviewOverlay.swift
└── Export/
    ├── VideoEditorExporter.swift (MODIFIED)
    └── ZoomCompositor.swift (NEW)
```

---

## Implementation Order

| Phase | Tasks | Est. Effort | Dependencies |
|-------|-------|-------------|--------------|
| **1** | Data model + State extension | 2-3 hours | None |
| **2** | ZoomTimelineTrack + ZoomBlockView | 4-5 hours | Phase 1 |
| **3** | ZoomSettingsPopover | 2-3 hours | Phase 2 |
| **4** | Real-time preview | 3-4 hours | Phase 1, 2 |
| **5** | Export with zooms | 4-6 hours | Phase 1-4 |
| **6** | Polish + edge cases | 2-3 hours | Phase 1-5 |

**Total Estimated:** 17-24 hours

---

## Acceptance Criteria

### P0 (Must Have)
- [ ] Click on zoom track adds new zoom at position
- [ ] Drag zoom block edges to resize duration
- [ ] Zoom level slider (100-400%)
- [ ] Select/deselect zooms
- [ ] Remove zoom via right-click menu
- [ ] Export applies zoom effects to output video

### P1 (Should Have)
- [ ] Real-time preview of zoom effect during playback
- [ ] Drag zoom block to reposition
- [ ] Zoom center picker in settings
- [ ] Enable/disable zoom without deleting

### P2 (Nice to Have)
- [ ] Keyboard shortcuts
- [ ] Auto-zoom from click detection (recording phase)
- [ ] Cursor following during zoom

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| AVVideoComposition complexity | Medium | High | Start with simple crop-scale, iterate |
| Real-time preview performance | Medium | Medium | Use layer transforms, not frame processing |
| Overlapping zooms behavior | Low | Medium | Define clear priority rules upfront |
| Export quality with zooms | Medium | High | Use HighestQuality preset, test early |

---

## Unresolved Questions

1. **Zoom transition duration:** Fixed (0.3s) or user-configurable?
2. **Multiple zooms at same time:** Blend or priority-based?
3. **Auto-zoom scope:** Include in Phase 1 or defer to future?

---

## Next Steps

1. Approve plan
2. Implement Phase 1 (Data Model)
3. Implement Phase 2 (Timeline Track UI)
4. Test interactions before proceeding to export
