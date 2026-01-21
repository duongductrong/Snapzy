# Diagnostic Report: Secondary Monitor Area Capture Debug Logging

**Date:** 2026-01-18
**Status:** Debug logging added, awaiting test results
**Agent:** Debug Agent

## Problem Statement

Area capture fails on secondary monitors with error:
```
contentRect does not contain sourceRect
```

- Fullscreen capture: WORKS on secondary monitor
- Area capture: FAILS on secondary monitor

## Analysis of Code Flow

### AreaSelectionWindow Coordinate Flow

1. **User Selection** (AreaSelectionOverlayView.swift:361-370)
   - User drags selection rectangle in window-local coordinates
   - Window frame matches screen frame (line 154)

2. **Coordinate Conversion** (AreaSelectionWindow.swift:204-216)
   - Converts from window coords to global screen coords
   - Uses simple offset: `windowFrame.origin + rect.origin`
   - Maintains bottom-left origin (macOS standard)
   - Returns global screen coordinates to ScreenCaptureManager

3. **ScreenCaptureManager.captureArea()** receives global coords

### Suspected Issues

**Issue 1: displayFrame uses wrong dimensions**

Lines 193-198 construct displayFrame:
```swift
let displayFrame = CGRect(
  x: CGFloat(display.frame.origin.x),
  y: CGFloat(display.frame.origin.y),
  width: CGFloat(display.width),      // ← BUG?
  height: CGFloat(display.height)     // ← BUG?
)
```

Should potentially use:
```swift
width: display.frame.width   // Not display.width
height: display.frame.height // Not display.height
```

**Key difference:**
- `display.frame.width/height` = points (logical coordinates)
- `display.width/height` = pixels (backing store)

For Retina displays: `display.width = display.frame.width * 2`

**Issue 2: displayBounds uses displayFrame.width/height**

Line 238-242:
```swift
let displayBounds = CGRect(
  x: 0,
  y: 0,
  width: displayFrame.width,   // ← Inconsistent
  height: displayFrame.height  // ← Inconsistent
)
```

If displayFrame was constructed with pixel dimensions, this creates wrong bounds.

**Issue 3: contentRect vs sourceRect mismatch**

ScreenCaptureKit expects:
- `contentRect` = (0, 0, display.width, display.height) in PIXELS
- `sourceRect` must be within contentRect

Current code:
- Uses displayFrame.height (potentially points) for Y-flip calculation (line 253)
- Uses displayFrame.width/height (potentially points) for bounds (line 241-242)
- SourceRect gets compared against pixel-based contentRect

## Debug Logging Added

### Comprehensive logging at each step:

1. **All available displays**
   - Display ID
   - frame.origin (x, y)
   - frame.size (width, height)
   - display.width/height (pixel dimensions)

2. **Input rect** (global screen coordinates)
   - origin (x, y)
   - size (width, height)

3. **Display selection**
   - Which display intersects with rect
   - displayFrame construction values

4. **Selected display details**
   - Display ID
   - display.frame vs display.width/height comparison

5. **Scale factor calculation**
   - Source (NSScreen or calculated)
   - Actual value

6. **Coordinate conversion**
   - displayFrame dimensions
   - displayOrigin offset
   - relativeRect after offset subtraction
   - displayBounds for clamping
   - clampedRect after intersection

7. **Y-flip calculation**
   - Formula breakdown
   - flippedY result
   - sourceRect final values

8. **Final configuration**
   - config.sourceRect
   - config.width/height (pixels)
   - Expected contentRect bounds
   - Validation check

9. **Error details** (if capture fails)
   - Localized description
   - Full error object

## Testing Instructions

### Setup Required
- macOS with secondary monitor connected
- Secondary monitor in any arrangement (side-by-side, stacked)

### Test Procedure

1. **Build and run** ZapShot with debug logging
2. **Trigger area capture** on secondary monitor
3. **Collect console output** from Xcode debugger
4. **Look for patterns:**

   **Pattern A: Dimension mismatch**
   ```
   display.frame.width: 1920
   display.width: 3840
   displayBounds.width: 3840  ← WRONG (should be 1920)
   sourceRect exceeds contentRect
   ```

   **Pattern B: Wrong display selected**
   ```
   Checking Display 0: intersects=true  ← Selected primary instead
   rect origin: (2000, 500)  ← Actually on secondary
   ```

   **Pattern C: Coordinate math error**
   ```
   relativeRect.origin: (-200, 100)  ← Negative coords
   clampedRect: empty intersection
   ```

### Expected Findings

Most likely: **Pattern A - displayBounds uses pixel dimensions instead of points**

Compare these values in logs:
- `display.frame.width` vs `display.width`
- `displayBounds.width` vs actual value used
- `sourceRect` vs `contentRect (0, 0, display.width, display.height)`

## Next Steps

1. Run test on secondary monitor
2. Capture full console output
3. Identify which pattern appears
4. Confirm root cause hypothesis
5. Report findings for fix implementation

## Unresolved Questions

1. Does `display.frame` dimensions differ from `display.width/height` on secondary monitors?
2. Is the scale factor calculation correct for non-Retina secondary monitors?
3. Should displayBounds use points or pixels for intersection?
4. Is Y-flip using correct reference height?

## Files Modified

- `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/ScreenCaptureManager.swift`
  - Added debug logging to `captureArea()` method
  - No functional changes, diagnostic only

## Files Analyzed

- `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/ScreenCaptureManager.swift`
- `/Users/duongductrong/Developer/ZapShot/ZapShot/Core/AreaSelectionWindow.swift`
