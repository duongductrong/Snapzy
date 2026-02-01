# Crop Export Bug Scout Report

## Executive Summary

Found critical aspect ratio discrepancy between preview and export.

**Root Cause**: Export uses crop dimensions directly, preview uses crop dimensions for layout calculation.

**Impact**: Exported image has wrong aspect ratio compared to what user sees in preview.

## Key Files

### Crop Feature Files

**State Management:**
- `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Annotate/State/AnnotateState.swift`
  - Lines 236-251: Crop state properties (`cropRect`, `cropAspectRatio`, `isCropActive`)
  - Lines 430-490: Crop methods (`initializeCrop()`, `applyCrop()`, `applyCropAspectRatio()`)
  - `cropRect` stored in image coordinates (bottom-left origin)

**Crop Ratio Definition:**
- `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Annotate/State/CropAspectRatio.swift`
  - Lines 22-31: Ratio calculation (e.g., `16:9` = 16.0/9.0 = 1.778)
  - Ratios: free, 1:1, 4:3, 3:2, 16:9, 21:9

**UI Components:**
- `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Annotate/Views/CropOverlayView.swift`
  - Lines 114-122: Coordinate transform (bottom-left → top-left)
  - Visual overlay, does NOT affect actual crop calculation

- `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Annotate/Views/CropToolbarView.swift`
  - Lines 44-52: Aspect ratio picker
  - Line 49: Calls `state.applyCropAspectRatio(ratio)`

### Export Feature Files

**Main Exporter:**
- `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Annotate/Export/AnnotateExporter.swift`
  - Lines 92-214: `renderFinalImage()` - main export logic
  - Lines 100-106: Determines `effectiveBounds` from `cropRect`
  - Lines 108-116: Calculates `totalSize` with padding + alignment space
  - Lines 130-168: Alignment-based positioning
  - Lines 170-184: Source/dest rect calculation for drawing

**Preview Canvas:**
- `/Users/duongductrong/Developer/ZapShot/Snapzy/Features/Annotate/Views/AnnotateCanvasView.swift`
  - Lines 106-120: Effective dimensions based on crop state
  - Lines 122-129: Logical canvas size calculation with padding
  - Lines 144-161: Offset calculation when crop applied
  - Lines 164-171: Clip rect calculation for applied crop

## Crop Flow Analysis

### 1. Crop Creation Flow

```
User selects crop tool
  → AnnotateState.initializeCrop() (line 433)
  → cropRect = full image bounds
  → isCropActive = true

User selects aspect ratio (e.g., 16:9)
  → CropToolbarView calls applyCropAspectRatio() (line 49)
  → AnnotateState.applyCropAspectRatio() (line 468)
  → Adjusts cropRect to match ratio
  → Uses originalCropRect as base (line 472)

User clicks Apply
  → AnnotateState.applyCrop() (line 441)
  → isCropActive = false
  → cropRect RETAINED for export
```

### 2. Preview Display Flow

**AnnotateCanvasView.swift lines 106-120:**
```swift
let isCropApplied = state.cropRect != nil && !state.isCropActive
if isCropApplied, let cropRect = state.cropRect {
  effectiveWidth = cropRect.width   // Use crop dimensions
  effectiveHeight = cropRect.height
} else {
  effectiveWidth = state.imageWidth  // Use full image
  effectiveHeight = state.imageHeight
}

logicalCanvasWidth = effectiveWidth + currentPadding * 2 + alignmentSpace
```

**Key Point**: Preview uses crop dimensions to calculate canvas size, then scales everything proportionally.

### 3. Export Rendering Flow

**AnnotateExporter.swift lines 100-116:**
```swift
let effectiveBounds: CGRect
if let cropRect = state.cropRect {
  effectiveBounds = cropRect  // Uses crop rect directly
} else {
  effectiveBounds = CGRect(origin: .zero, size: sourceImage.size)
}

let totalSize = NSSize(
  width: effectiveBounds.width + padding * 2 + alignmentSpace,
  height: effectiveBounds.height + padding * 2 + alignmentSpace
)
```

**Key Point**: Export also uses crop dimensions but then adds padding/alignment.

## Potential Discrepancy Points

### Issue #1: Alignment Space Addition

**Preview** (AnnotateCanvasView.swift line 104):
```swift
let alignmentSpace: CGFloat = state.imageAlignment != .center ? 40 : 0
```

**Export** (AnnotateExporter.swift line 111):
```swift
let alignmentSpace: CGFloat = state.imageAlignment != .center ? 40 : 0
```

Both use same logic ✓

### Issue #2: Scaling Difference

**Preview** (AnnotateCanvasView.swift lines 126-129):
```swift
let scaleX = availableWidth / logicalCanvasWidth
let scaleY = availableHeight / logicalCanvasHeight
let scale = min(scaleX, scaleY, 1.0)  // Unified scale, maintains aspect
```

**Export** (AnnotateExporter.swift lines 113-116):
```swift
let totalSize = NSSize(
  width: effectiveBounds.width + padding * 2 + alignmentSpace,
  height: effectiveBounds.height + padding * 2 + alignmentSpace
)
// NO SCALING - uses pixel dimensions directly
```

**CRITICAL**: Export creates image at ACTUAL pixel dimensions, preview SCALES to fit viewport.

### Issue #3: Crop Rect Aspect Preservation

**AnnotateState.applyCropAspectRatio()** (lines 467-490):
- Adjusts cropRect to match selected ratio
- Logic seems sound for width/height adjustment

**Need to verify**: Does crop interaction preserve aspect ratio during resize?

### Issue #4: Coordinate System Transforms

**Preview** transforms crop coordinates (CropOverlayView.swift line 114):
```swift
y: (imageSize.height - rect.origin.y - rect.height) * scale
```

**Export** transforms crop coordinates (AnnotateExporter.swift line 181):
```swift
y: sourceImage.size.height - effectiveBounds.origin.y - effectiveBounds.height
```

Both flip Y-axis from bottom-left to top-left ✓

## Critical Questions Requiring Investigation

1. **How is cropRect modified during interactive resize?**
   - Need to check mouse drag handlers for crop handles
   - Does resize maintain aspect ratio when ratio is selected?

2. **Does background padding affect aspect ratio calculation?**
   - Both preview and export add padding AFTER using crop dimensions
   - Should be proportional

3. **Is there a rounding/truncation issue?**
   - Preview uses CGFloat throughout
   - Export uses NSSize (also CGFloat-based)
   - Unlikely but possible

4. **Mockup mode interaction?**
   - Lines 95-98: Mockup uses different rendering path
   - Lines 389-435: `renderFlatImageWithAnnotations()` for mockup
   - User likely not in mockup mode but worth checking

## Next Steps for Investigation

1. Find crop handle drag interaction code
2. Add logging to compare cropRect values at:
   - After aspect ratio selection
   - After crop apply
   - During export render
3. Test with exact dimensions (e.g., 1920x1080 for 16:9)
4. Check if issue occurs with all aspect ratios or specific ones

## Unresolved Questions

- Where is crop resize drag handler implemented? (Not found in scanned files)
- Does shift-lock for aspect ratio work correctly during resize?
- Is cropRect ever modified between apply and export?
- Are there floating point precision issues with aspect ratio calculations?
