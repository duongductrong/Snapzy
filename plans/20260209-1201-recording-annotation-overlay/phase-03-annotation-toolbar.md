# Phase 3: Floating Annotation Toolbar (Draggable + Snap + Direction)

- **Date**: 2026-02-09
- **Priority**: High
- **Status**: Pending

## Overview
Floating toolbar showing annotation tools. Draggable anywhere, auto-snaps to corners, auto-switches horizontal↔vertical layout based on screen edge proximity. Styled to match recording toolbar (NSVisualEffectView + hudWindow material).

## Key Insights
- Separate NSWindow from recording toolbar (independent positioning)
- NSVisualEffectView with `.hudWindow` material matches existing toolbars
- Corner snap grid: 4 corners + 2 center-edges (left/right)
- Horizontal default; vertical when near left/right center edges
- Drag handle at the end (right for horizontal, bottom for vertical)
- Window level: `.popUpMenu` (same as recording toolbar, above overlay)
- Must be EXCLUDED from screen capture (our app is already excluded)

## Requirements
1. Tool buttons matching recording toolbar style (ToolbarIconButton-like)
2. Stroke color picker (compact: 5 preset colors)
3. Stroke width: thin/medium/thick toggle
4. Clear all button
5. Drag handle for repositioning
6. Auto-snap to nearest corner/edge when released
7. Auto horizontal↔vertical based on position
8. Show/hide animated based on `isAnnotationEnabled`

## Architecture

### Layout (Horizontal):
```
[✏️] [▬] [○] [→] [╱] [🖊] [🖍] | [●●●] [─ ═ ━] [🗑] [⠿]
 tools                            colors  width  clear drag
```

### Layout (Vertical):
```
[⠿]  ← drag handle
[✏️]
[▬]
[○]
[→]
[╱]
[🖊]
[🖍]
 ─
[●●●]  ← color dots
[─═━]  ← width
[🗑]   ← clear
```

### Snap Grid Definition
```
snap zones (20% from each edge):
- Top-left, Top-right, Bottom-left, Bottom-right → horizontal
- Center-left, Center-right → vertical
```

### New Files
- `Snapzy/Features/Recording/Annotation/RecordingAnnotationToolbarWindow.swift` (~150 lines)
- `Snapzy/Features/Recording/Annotation/RecordingAnnotationToolbarView.swift` (~120 lines)

## Implementation Steps
1. Create `RecordingAnnotationToolbarWindow` (NSWindow, borderless, hudWindow material)
2. Create `RecordingAnnotationToolbarView` (SwiftUI view with tool buttons)
3. Implement drag gesture on handle area
4. Implement snap-to-corner logic on drag end
5. Implement horizontal↔vertical layout switching
6. Implement show/hide animation tied to `isAnnotationEnabled`
7. Add color presets row (red, blue, green, yellow, white)
8. Add stroke width toggle (2/4/8)
9. Add clear all button

## Success Criteria
- Toolbar appears/disappears with annotation toggle
- All 7 tools selectable
- Drag + snap works smoothly
- Layout switches based on position
- Colors and stroke width changeable
