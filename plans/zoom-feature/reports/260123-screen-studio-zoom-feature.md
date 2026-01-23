# Research Report: Screen Studio Zoom Feature Analysis

**Date:** 2026-01-23
**Topic:** Adding/Editing Zooms in Screen Studio
**Sources Consulted:** 4

---

## Executive Summary

Screen Studio implements a sophisticated zoom system for screen recordings with two core modes: **Auto Zoom** (click-detection based) and **Manual Zoom** (user-defined areas). Zooms are visualized as purple blocks on a dedicated timeline track, enabling intuitive drag-to-edit functionality. The system supports up to 400% magnification with smooth easing animations.

Key differentiators: automatic click detection for intelligent zoom placement, timeline-integrated editing, and customizable zoom levels per instance.

---

## Key Findings

### 1. Zoom System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    VIDEO PREVIEW                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │                                                  │    │
│  │         Zoom Preview Area                        │    │
│  │         (shows zoom effect in real-time)         │    │
│  │                                                  │    │
│  └─────────────────────────────────────────────────┘    │
├─────────────────────────────────────────────────────────┤
│                    TIMELINE EDITOR                       │
├─────────────────────────────────────────────────────────┤
│ Video Track   │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│   │
├─────────────────────────────────────────────────────────┤
│ Zoom Track    │   ▓▓▓▓▓   ▓▓▓▓▓▓▓▓   ▓▓▓│             │   │
│               │   (purple zoom blocks)                   │
├─────────────────────────────────────────────────────────┤
│ Audio Track   │▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒│   │
└─────────────────────────────────────────────────────────┘
```

### 2. Zoom Types

| Type | Description | Trigger |
|------|-------------|---------|
| **Auto Zoom** | Automatically zooms to cursor/click location | Mouse clicks during recording |
| **Manual Zoom** | User selects specific area to zoom | Manual placement on timeline |

### 3. Zoom Controls & Interactions

**Adding Zooms:**
- Click on zoom timeline at desired timestamp
- New zoom block appears at click position
- Auto-zooms generated from click events during recording

**Editing Zooms:**
- **Duration:** Drag left/right edges of zoom block
- **Level:** Select zoom → settings bar appears → adjust slider (up to 400%)
- **Position:** Drag zoom block horizontally on timeline
- **Area:** Select zoom region in preview for manual zooms

**Removing Zooms:**
- Right-click → "Disable" (keeps but ignores)
- Right-click → "Remove" (deletes entirely)

### 4. Timeline Integration

```
Zoom Block Structure:
┌────────────────────────────────────┐
│  ◀─ drag edge    ZOOM BLOCK    drag edge ─▶  │
│     (resize)     (purple)       (resize)     │
└────────────────────────────────────┘
         ↓ click to select
    ┌─────────────────────┐
    │  ZOOM SETTINGS BAR  │
    │  [Zoom Level: ───●──] 200%  │
    │  [Area Selection]    │
    └─────────────────────┘
```

### 5. Animation & Easing

- Smooth zoom transitions between normal and zoomed states
- Easing functions for natural motion (likely cubic-bezier)
- Cursor following during zoom (camera tracks mouse movement)
- Consistent visual boundaries across zoom levels

### 6. UI/UX Patterns

**Visual Feedback:**
- Purple color coding for zoom elements (distinct from other tracks)
- Real-time preview of zoom effect
- Edge handles visible on hover for resize

**Interaction Model:**
- Click to add
- Drag edges to resize duration
- Select to reveal settings
- Right-click for context menu (disable/remove)

---

## Implementation Recommendations for ClaudeShot

### Data Model

```swift
struct ZoomSegment: Identifiable {
    let id: UUID
    var startTime: TimeInterval      // start position on timeline
    var duration: TimeInterval       // zoom duration
    var zoomLevel: CGFloat           // 1.0 to 4.0 (100% to 400%)
    var zoomCenter: CGPoint          // normalized 0-1 for x,y
    var zoomType: ZoomType           // .auto or .manual
    var isEnabled: Bool              // for disable without delete
}

enum ZoomType {
    case auto      // generated from click detection
    case manual    // user-defined
}
```

### Timeline Track Component

```swift
struct ZoomTimelineTrack: View {
    @Binding var zooms: [ZoomSegment]
    @Binding var selectedZoomId: UUID?
    let totalDuration: TimeInterval
    let trackWidth: CGFloat

    // Convert time to x position
    func xPosition(for time: TimeInterval) -> CGFloat {
        CGFloat(time / totalDuration) * trackWidth
    }

    // Zoom block view with drag handles
    // Settings popover on selection
    // Right-click context menu
}
```

### Auto-Zoom Detection (Recording Phase)

```swift
class ClickEventRecorder {
    var clickEvents: [(timestamp: TimeInterval, location: CGPoint)] = []

    func recordClick(at location: CGPoint, timestamp: TimeInterval) {
        clickEvents.append((timestamp, location))
    }

    func generateAutoZooms() -> [ZoomSegment] {
        clickEvents.map { event in
            ZoomSegment(
                startTime: event.timestamp - 0.3,  // slight lead-in
                duration: 2.0,                      // default duration
                zoomLevel: 2.0,                     // default 200%
                zoomCenter: normalizedPoint(event.location),
                zoomType: .auto,
                isEnabled: true
            )
        }
    }
}
```

### Zoom Animation

```swift
// Apply zoom effect during video export/preview
func applyZoom(to frame: CGImage, segment: ZoomSegment, progress: Double) -> CGImage {
    // Easing function for smooth transition
    let easedProgress = easeInOutCubic(progress)

    // Interpolate zoom level (1.0 = no zoom)
    let currentZoom = 1.0 + (segment.zoomLevel - 1.0) * easedProgress

    // Calculate crop rect based on zoom center and level
    let cropRect = calculateCropRect(
        center: segment.zoomCenter,
        zoom: currentZoom,
        frameSize: CGSize(width: frame.width, height: frame.height)
    )

    // Crop and scale
    return frame.cropping(to: cropRect)?.scaled(to: originalSize)
}

func easeInOutCubic(_ t: Double) -> Double {
    t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}
```

---

## Feature Priority Matrix

| Feature | Priority | Complexity | Impact |
|---------|----------|------------|--------|
| Manual zoom add/edit on timeline | P0 | Medium | High |
| Zoom level slider | P0 | Low | High |
| Drag to resize duration | P0 | Medium | High |
| Auto-zoom from clicks | P1 | High | Medium |
| Zoom area selection preview | P1 | Medium | High |
| Disable/Remove context menu | P1 | Low | Medium |
| Smooth easing animations | P2 | Medium | Medium |
| Cursor following in zoom | P2 | High | Medium |

---

## Common Pitfalls

1. **Performance:** Real-time preview of zoom requires efficient frame cropping
2. **Overlapping zooms:** Define behavior when zoom segments overlap (blend or priority?)
3. **Edge cases:** Zoom extending past video end, zooming outside frame bounds
4. **Undo/Redo:** Zoom edits need proper undo stack integration

---

## Resources & References

### Official Documentation
- [Screen Studio - Adding & Editing Zooms](https://screen.studio/guide/adding-editing-zooms)
- [Screen Studio Official Site](https://screen.studio/)

### Animation Patterns
- [Medium - Timeline UI Scaling Patterns](https://medium.com)
- Easing functions: cubic-bezier for natural motion
- GSAP/Framer Motion concepts applicable to Swift animations

---

## Unresolved Questions

1. Does Screen Studio support zoom keyframes (multiple zoom levels within one segment)?
2. What's the exact easing curve used for zoom transitions?
3. How does cursor-following camera work during zoomed playback?
4. Are there keyboard shortcuts for quick zoom add/remove?
