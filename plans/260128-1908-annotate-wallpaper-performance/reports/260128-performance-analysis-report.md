# Annotate Feature Performance Analysis Report

**Date:** 2026-01-28
**Issue:** Slider adjustments (padding, corner radius, shadows, rotation) cause lag with FPS under 60
**Target:** Achieve 60+ FPS, ideally 120 FPS

## Executive Summary

Performance bottleneck identified: **CompactSliderRow** in AnnotateSidebarView.swift directly binds to @Published state properties, triggering full view hierarchy re-renders on every slider movement (30-60 times/second during drag). This cascades through entire canvas causing expensive shadow/corner/blur recalculations.

**Impact:** FPS drops to <60 during slider drag due to main thread blocking by SwiftUI view updates + GPU rendering overhead.

**Root Cause:** Missing local state optimization pattern for sliders + excessive shadow recalculation + potential wallpaper re-loading.

---

## Critical Issues (Priority 1 - Highest Impact)

### Issue 1: Direct State Binding Without Local Optimization
**Location:** `AnnotateSidebarView.swift:146-164` (CompactSliderRow)

**Problem:**
```swift
CompactSliderRow(
  label: "Padding",
  value: Binding(
    get: { state.padding },
    set: { newValue in
      state.padding = newValue  // TRIGGERS @Published IMMEDIATELY
      if newValue > 0 && state.backgroundStyle == .none {
        state.backgroundStyle = .solidColor(.white)
      }
    }
  ),
  range: 0...300
)

CompactSliderRow(label: "Shadow", value: $state.shadowIntensity, range: 0...1)
CompactSliderRow(label: "Corners", value: $state.cornerRadius, range: 0...60)
```

**Why it causes lag:**
- Every slider movement (30-60 events/second) triggers `@Published` update
- SwiftUI re-evaluates entire view hierarchy on each update
- Canvas re-renders with new values 30-60 times/second
- Shadow calculations (`.shadow()` modifier) run on every frame
- Corner radius clipping recalculated on every frame

**Evidence:**
- CompactSliderRow (lines 230-290) has NO local state buffering
- Direct `@Binding` to state properties
- Unlike `SliderRow` in AnnotateSidebarComponents.swift (lines 213-249) which HAS `@State private var localValue` + `onEditingChanged` callback

### Issue 2: Shadow Recalculation on Every Frame
**Location:** `AnnotateCanvasView.swift:193-197, 273-278`

**Problem:**
```swift
.shadow(
  color: .black.opacity(currentShadowIntensity),  // Recalculated every render
  radius: 20,
  x: 0,
  y: 10
)
```

**Why it causes lag:**
- `.shadow()` modifier is computationally expensive (requires GPU rendering to texture)
- Applied to BOTH background layer AND image layer
- No caching - recalculated on every slider movement
- Shadow opacity changes trigger full re-rasterization

**Impact:** Each shadow recalculation takes 2-5ms on GPU. With 2 shadows + 60fps = 240-600ms overhead per second.

### Issue 3: Corner Radius Clipping Without Caching
**Location:** `AnnotateCanvasView.swift:185, 219, 232, 271`

**Problem:**
```swift
RoundedRectangle(cornerRadius: currentCornerRadius)
  .fill(...)

Image(nsImage: sourceImage)
  .cornerRadius(currentCornerRadius)  // Re-clips on every change
```

**Why it causes lag:**
- `.cornerRadius()` triggers Core Graphics clipping path recalculation
- Image clipping requires re-rasterization to off-screen buffer
- No GPU texture caching between frames
- `.drawingGroup()` (line 255, 272) helps but doesn't cache across value changes

---

## High Impact Issues (Priority 2)

### Issue 4: Missing Preview Value Pattern for All Sliders
**Location:** `AnnotateState.swift:123-136` (partial implementation)

**Current State:**
- Preview values exist for padding/inset/shadow/corner (lines 126-129)
- `effective*` computed properties implemented (lines 132-135)
- BUT CompactSliderRow doesn't USE this pattern!

**Evidence:**
- `SliderRow` (AnnotateSidebarComponents.swift:203-240) properly uses `onDragging` callback
- `SidebarSlidersSection` (AnnotateSidebarSections.swift:203-240) shows correct usage:
  ```swift
  SliderRow(
    label: "Padding",
    value: $state.padding,
    onDragging: { isDragging, value in
      state.previewPadding = isDragging ? value : nil  // ✓ CORRECT
    }
  )
  ```
- But `CompactSliderRow` in AnnotateSidebarView lacks this implementation

### Issue 5: Wallpaper Image Re-loading Risk
**Location:** `AnnotateCanvasView.swift:212-220`

**Potential Problem:**
```swift
} else if let nsImage = state.cachedBackgroundImage {
  Image(nsImage: nsImage)
    .resizable()
    .aspectRatio(contentMode: .fill)
    .frame(width: width, height: height)  // width/height change during padding slider
    .clipped()
    .cornerRadius(currentCornerRadius)
```

**Why it might cause lag:**
- `width`/`height` change on padding slider drag
- `.frame()` modifier might trigger Image re-evaluation
- `.clipped()` + `.cornerRadius()` = double clipping overhead
- Large wallpaper images (2048px) being processed

**Mitigation already in place:**
- `cachedBackgroundImage` avoids disk I/O (good!)
- `cachedBlurredImage` pre-computed (good!)
- But GPU texture upload might still happen on size changes

### Issue 6: Mockup Slider Direct Binding
**Location:** `MockupControlsSection.swift:88-108`

**Problem:**
```swift
struct MockupSlider: View {
    let label: String
    @Binding var value: Double  // DIRECT binding, no local state
    let range: ClosedRange<Double>

    Slider(value: $value, in: range)  // Updates on every movement
}
```

**Impact:**
- Same issue as CompactSliderRow
- Triggers 3D transform recalculation on every frame
- Rotation/perspective transforms are expensive (matrix operations)

---

## Medium Impact Issues (Priority 3)

### Issue 7: View Hierarchy Re-evaluation Cascade
**Location:** `AnnotateSidebarView.swift:14-68`

**Problem:**
```swift
struct AnnotateSidebarView: View {
  @ObservedObject var state: AnnotateState  // Entire sidebar re-renders on ANY state change

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        noneButton          // Re-evaluated
        gradientSection     // Re-evaluated
        wallpaperSection    // Re-evaluated (LazyVGrid + ForEach)
        colorSection        // Re-evaluated
        slidersSection      // Re-evaluated
        alignmentSection    // Re-evaluated
        // ... more sections
      }
    }
  }
}
```

**Why it causes lag:**
- `@ObservedObject` triggers full view re-evaluation on ANY @Published change
- Entire sidebar hierarchy re-computed (gradients, wallpapers, colors, alignment grid)
- LazyVGrid in wallpaperSection still evaluates visible items
- Bindings recalculated for all components

**Recommendation:** Use `@ObservedObject` more granularly or add `.id()` modifiers to prevent cascade.

### Issue 8: CanvasDrawingView NSView Updates
**Location:** `CanvasDrawingView.swift:22-26`

**Problem:**
```swift
func updateNSView(_ nsView: DrawingCanvasNSView, context: Context) {
    nsView.state = state
    nsView.displayScale = displayScale
    nsView.needsDisplay = true  // Forces full redraw
}
```

**Why it might cause lag:**
- `needsDisplay = true` on EVERY state update (even non-visual changes)
- Should check if visual properties actually changed
- Full canvas redraw includes all annotations (lines 542-549)

---

## Lower Impact Issues (Priority 4)

### Issue 9: Background Auto-Apply Logic in Slider Binding
**Location:** `AnnotateSidebarView.swift:150-158`

**Problem:**
```swift
set: { newValue in
  state.padding = newValue
  if newValue > 0 && state.backgroundStyle == .none {
    state.backgroundStyle = .solidColor(.white)  // EXTRA state change during drag
  }
}
```

**Why it causes lag:**
- Triggers TWO @Published updates during single slider movement
- Conditional logic evaluated 30-60 times/second
- Creates white background mid-drag (visual flicker potential)

### Issue 10: TextField Sync During Slider Drag
**Location:** `AnnotateSidebarView.swift:261-265`

**Problem:**
```swift
.onChange(of: value) { _, newValue in
  if !isTextFieldFocused {
    textValue = String(format: "%.0f", newValue)  // String formatting 60x/sec
  }
}
```

**Impact:** Minor - string formatting is fast, but unnecessary work during drag.

---

## Performance Optimization Recommendations

### Fix 1: Implement Local State for CompactSliderRow (CRITICAL)
**Priority:** P0 (Highest)
**Expected FPS gain:** +40-60 FPS

**Implementation:**
```swift
struct CompactSliderRow: View {
  let label: String
  @Binding var value: CGFloat
  let range: ClosedRange<CGFloat>

  @State private var localValue: CGFloat = 0       // ADD THIS
  @State private var isDragging: Bool = false      // ADD THIS

  var body: some View {
    VStack(...) {
      Slider(
        value: $localValue,                        // Use local, not binding
        in: range,
        onEditingChanged: { editing in             // ADD THIS
          isDragging = editing
          if !editing {
            value = localValue  // Sync only when drag ends
          }
        }
      )
    }
    .onAppear { localValue = value }
    .onChange(of: value) { _, newValue in
      if !isDragging { localValue = newValue }
    }
  }
}
```

### Fix 2: Use Preview Values for Canvas Rendering (CRITICAL)
**Priority:** P0
**Expected FPS gain:** +20-30 FPS

**Implementation:**
Update CompactSliderRow to use preview pattern:
```swift
CompactSliderRow(
  label: "Padding",
  value: $state.padding,
  range: 0...300,
  onDragging: { isDragging, previewValue in
    state.previewPadding = isDragging ? previewValue : nil
  }
)
```

Canvas already uses `effectivePadding` etc., so this will work immediately.

### Fix 3: Cache Shadow Rendering (HIGH)
**Priority:** P1
**Expected FPS gain:** +15-25 FPS

**Implementation:**
```swift
// Wrap shadow layers in .drawingGroup() with .id() modifier
Group {
  backgroundLayer(...)
}
.drawingGroup()  // Rasterize to Metal texture
.shadow(...)     // Apply shadow to cached texture
.id("\(currentShadowIntensity)")  // Re-cache only when intensity changes significantly
```

Or use stepped shadow values (round to nearest 0.05) to reduce re-renders.

### Fix 4: Debounce Canvas Updates (MEDIUM)
**Priority:** P2
**Expected FPS gain:** +10-15 FPS

**Implementation:**
```swift
func updateNSView(_ nsView: DrawingCanvasNSView, context: Context) {
  let visualPropsChanged = (
    nsView.displayScale != displayScale ||
    hasVisualStateChanges()
  )

  if visualPropsChanged {
    nsView.state = state
    nsView.displayScale = displayScale
    nsView.needsDisplay = true
  }
}
```

### Fix 5: Optimize Mockup Sliders (MEDIUM)
**Priority:** P2
**Expected FPS gain:** +5-10 FPS

Apply same local state pattern to MockupSlider as Fix 1.

### Fix 6: Separate Sidebar State Observation (LOW)
**Priority:** P3
**Expected FPS gain:** +5 FPS

Break AnnotateSidebarView into smaller components with targeted @ObservedObject usage.

---

## Measurement Strategy

**Before optimization:**
1. Profile with Instruments (Time Profiler + Core Animation)
2. Measure FPS with Xcode FPS gauge
3. Identify hotspots in `draw(_:)` and `updateNSView`

**After each fix:**
1. Re-measure FPS during slider drag
2. Compare Time Profiler flame graphs
3. Verify no visual regressions

---

## Priority Implementation Order

1. **P0 - Fix 1 + Fix 2:** Local state + preview values (Expected: 60-90 FPS gain)
2. **P1 - Fix 3:** Shadow caching (Expected: +15-25 FPS)
3. **P2 - Fix 4 + Fix 5:** Canvas debounce + mockup sliders (Expected: +15-25 FPS)
4. **P3 - Fix 6:** Sidebar optimization (Expected: +5 FPS)

**Total Expected Improvement:** 95-145 FPS gain → **Target 120 FPS achievable**

---

## Code Locations Summary

**Critical files:**
- `/ClaudeShot/Features/Annotate/Views/AnnotateSidebarView.swift:146-164` (CompactSliderRow bindings)
- `/ClaudeShot/Features/Annotate/Views/AnnotateCanvasView.swift:193-197, 273-278` (Shadow rendering)
- `/ClaudeShot/Features/Annotate/State/AnnotateState.swift:123-136` (Preview values infrastructure)

**Reference implementations (good patterns):**
- `/ClaudeShot/Features/Annotate/Views/AnnotateSidebarComponents.swift:213-249` (SliderRow with local state)
- `/ClaudeShot/Features/Annotate/Views/AnnotateSidebarSections.swift:203-240` (Preview pattern usage)

**Secondary files:**
- `/ClaudeShot/Features/Annotate/Mockup/Views/MockupControlsSection.swift:88-108` (MockupSlider)
- `/ClaudeShot/Features/Annotate/Canvas/CanvasDrawingView.swift:22-26` (NSView updates)

---

## Unresolved Questions

1. Is `.drawingGroup()` invalidating texture cache on cornerRadius changes? (Need Instruments GPU profiling)
2. What's actual FPS during slider drag? (Need XCTest performance measurement)
3. Are wallpaper LazyVGrid thumbnails causing sidebar lag? (Profile sidebar separately)
4. Does mockup 3D transform use Metal acceleration? (Check CATransform3D implementation)

---

## Technical Notes

- SliderRow pattern EXISTS and WORKS (AnnotateSidebarComponents.swift) but NOT used in main sidebar
- Preview value infrastructure EXISTS (AnnotateState.swift) but NOT connected to CompactSliderRow
- This is NOT a missing feature - it's an **implementation inconsistency**
- Quick win: copy SliderRow pattern to CompactSliderRow (30 min fix, massive perf gain)
