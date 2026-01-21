# Scout Report: Annotate Canvas Architecture

## Overview
ZapShot's annotation canvas uses NSView-based rendering with Core Graphics for drawing. Performance issues likely stem from redraw patterns and blur effect computation.

## Key Files Analyzed

### 1. CanvasDrawingView.swift (809 lines)
- **Architecture**: `NSViewRepresentable` wrapping `DrawingCanvasNSView` (NSView subclass)
- **Rendering**: Uses `draw(_ dirtyRect:)` with Core Graphics context
- **State Updates**: `updateNSView` sets `needsDisplay = true` on EVERY state change
- **Mouse Events**: `mouseDragged` triggers `needsDisplay = true` per drag event

**CRITICAL ISSUE**: Line 25 - `nsView.needsDisplay = true` called on every SwiftUI state update, causing full canvas redraw even for unrelated state changes.

### 2. AnnotationRenderer.swift (264 lines)
- Iterates ALL annotations on each draw call (line 532-539)
- No dirty rect optimization - redraws entire canvas
- No caching of rendered annotations

### 3. BlurEffectRenderer.swift (159 lines)
- **MAJOR BOTTLENECK**: `drawPixelatedRegion` (lines 23-72)
  - Creates CGImage from NSImage per draw
  - Reads raw pixel data via `CFDataGetBytePtr`
  - Nested loops for pixel sampling (lines 103-132)
  - O(rows * cols) complexity per blur region per frame
- No caching of pixelated results

### 4. AnnotateState.swift (522 lines)
- `@Published var annotations: [AnnotationItem]` triggers view updates
- `updateAnnotationBounds` modifies array in place, triggers full redraw
- No batching of state updates during drag

### 5. AnnotateCanvasView.swift (345 lines)
- SwiftUI wrapper with GeometryReader
- Creates new CanvasDrawingView on layout changes
- No performance optimizations for annotation layer

## Performance Bottlenecks Identified

1. **Full Canvas Redraw**: Every mouse drag triggers complete redraw of all annotations
2. **Blur Recalculation**: Pixelation computed from scratch each frame (no caching)
3. **No Dirty Rect**: Entire canvas redrawn, not just changed regions
4. **State Propagation**: SwiftUI @Published causes cascade of updates
5. **No Layer Separation**: All annotations on single drawing layer

## Recommendations Priority

1. Cache blur effect as bitmap after creation
2. Implement dirty rect tracking for partial redraws
3. Separate static annotations from moving annotation during drag
4. Batch state updates during drag operations
5. Consider CALayer for individual annotations
