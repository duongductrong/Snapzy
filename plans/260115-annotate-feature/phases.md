# Implementation Phases

## Phase 1: Core Window Infrastructure
**Priority:** Critical
**Files:** 4

| File | Lines | Description |
|------|-------|-------------|
| `AnnotateWindow.swift` | ~40 | NSWindow subclass, dark mode styling |
| `AnnotateWindowController.swift` | ~60 | Window lifecycle, sizing, positioning |
| `AnnotateManager.swift` | ~50 | Singleton, open/track windows |
| `AnnotateState.swift` | ~80 | ObservableObject, all state properties |

**Deliverable:** Can open empty annotation window from floating card.

---

## Phase 2: Main View Layout
**Priority:** Critical
**Files:** 4

| File | Lines | Description |
|------|-------|-------------|
| `AnnotateMainView.swift` | ~60 | Container: toolbar + sidebar + canvas + bottom |
| `AnnotateToolbarView.swift` | ~150 | All tool buttons, stroke slider, save/done |
| `AnnotateSidebarView.swift` | ~180 | Background settings, sliders, color swatches |
| `AnnotateBottomBarView.swift` | ~80 | Zoom picker, drag handle, action buttons |

**Deliverable:** Full UI layout visible (non-functional tools).

---

## Phase 3: Canvas & Drawing Foundation
**Priority:** Critical
**Files:** 4

| File | Lines | Description |
|------|-------|-------------|
| `CanvasView.swift` | ~120 | NSViewRepresentable, mouse events, zoom/pan |
| `AnnotationTool.swift` | ~60 | Protocol + enum for all tools |
| `AnnotationLayer.swift` | ~80 | Annotation collection, rendering, hit testing |
| `CanvasRenderer.swift` | ~100 | Combine image + background + annotations |

**Deliverable:** Image displays in canvas, basic mouse event handling.

---

## Phase 4: Drawing Tools
**Priority:** High
**Files:** 8

| File | Lines | Description |
|------|-------|-------------|
| `SelectionTool.swift` | ~80 | Select, move, resize annotations |
| `PencilTool.swift` | ~60 | Freehand drawing paths |
| `ShapeTool.swift` | ~120 | Rectangle, Circle, Arrow, Line |
| `TextTool.swift` | ~100 | Text input, font/size settings |
| `HighlighterTool.swift` | ~50 | Semi-transparent strokes |
| `BlurTool.swift` | ~80 | Pixelate selected region |
| `CounterTool.swift` | ~60 | Auto-incrementing numbered markers |
| `CropTool.swift` | ~80 | Crop bounds, apply crop |

**Deliverable:** All drawing tools functional.

---

## Phase 5: Background System
**Priority:** Medium
**Files:** 3

| File | Lines | Description |
|------|-------|-------------|
| `BackgroundStyle.swift` | ~50 | Enum: none, gradient, wallpaper, color |
| `BackgroundPresets.swift` | ~80 | 8 gradients, color palette, wallpapers |
| `BackgroundRenderer.swift` | ~100 | Apply padding, shadow, corners, alignment |

**Deliverable:** Background customization works.

---

## Phase 6: State & Undo/Redo
**Priority:** Medium
**Files:** 3

| File | Lines | Description |
|------|-------|-------------|
| `AnnotationItem.swift` | ~60 | Model for each annotation |
| `UndoRedoManager.swift` | ~80 | Stack-based undo/redo |
| `ToolSettings.swift` | ~50 | Color, stroke width, font settings |

**Deliverable:** Undo/redo functional, Cmd+Z/Cmd+Shift+Z.

---

## Phase 7: Export & Actions
**Priority:** Medium
**Files:** 2

| File | Lines | Description |
|------|-------|-------------|
| `AnnotateExporter.swift` | ~80 | Save dialog, PNG/JPEG export |
| `ShareManager.swift` | ~60 | Share sheet, copy to clipboard |

**Deliverable:** Save, copy, share functional.

---

## Phase 8: Floating Card Integration
**Priority:** High
**Files:** 2 (modify existing)

| File | Changes |
|------|---------|
| `FloatingCardView.swift` | Double-tap gesture, blur on hover, border, text buttons |
| `CardTextButton.swift` | New file: text-based action buttons |

**Deliverable:** Double-tap opens annotation, improved card UI.

---

## Implementation Order

```
Phase 1 ──► Phase 2 ──► Phase 3 ──► Phase 4
   │                        │
   │                        ▼
   │                    Phase 5
   │                        │
   └────────────────────────┴──► Phase 6 ──► Phase 7 ──► Phase 8
```

**Recommended sequence:**
1. Phase 1 (window) → Phase 8 (integration) - Get end-to-end working first
2. Phase 2 (layout) - Full UI structure
3. Phase 3 (canvas) - Drawing foundation
4. Phase 4 (tools) - Core functionality
5. Phase 5 + 6 (background + state) - Polish
6. Phase 7 (export) - Final features
