# Research: VideoEditorState Dimension Configuration Flow

**Date**: 2026-01-29
**Researcher**: Dimension Flow Analysis
**Objective**: Investigate how dimension settings flow from UI to export process

---

## Key Findings

### 1. Dimension Flow Architecture

**UI → State → Export Pipeline:**

```
VideoExportSettingsPanel (UI)
    ↓ [Picker binding]
exportSettings.dimensionPreset
    ↓ [exportSize() calculation]
ExportSettings.exportSize(from: naturalSize)
    ↓ [Used in export]
VideoEditorExporter.exportWithZooms()
```

### 2. ExportSettings.exportSize() Logic

**Location**: `ExportSettings.swift:92-112`

```swift
func exportSize(from naturalSize: CGSize) -> CGSize {
    switch dimensionPreset {
    case .original:
        return naturalSize  // No scaling
    case .custom:
        let evenWidth = customWidth - (customWidth % 2)
        let evenHeight = customHeight - (customHeight % 2)
        return CGSize(width: evenWidth, height: evenHeight)
    default:  // hd1080, hd720, sd480
        guard let targetHeight = dimensionPreset.targetHeight else {
            return naturalSize
        }
        let aspectRatio = naturalSize.width / naturalSize.height
        var targetWidth = Int(CGFloat(targetHeight) * aspectRatio)
        targetWidth = targetWidth - (targetWidth % 2)
        let evenHeight = targetHeight - (targetHeight % 2)
        return CGSize(width: targetWidth, height: evenHeight)
    }
}
```

**Key behaviors**:
- Returns **video dimensions only** (no padding included)
- Ensures even dimensions for H.264 encoding
- Preserves aspect ratio for preset scaling

### 3. File Size Calculation Issue

**Location**: `VideoEditorState.swift:659-702`

**Current implementation**:
```swift
private func calculateEstimatedFileSize() async -> Int64 {
    // ...
    let exportSize = exportSettings.exportSize(from: naturalSize)
    let originalPixels = naturalSize.width * naturalSize.height

    // CORRECT: Includes background padding in canvas calculation
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    if backgroundStyle != .none && backgroundPadding > 0 {
        canvasWidth = exportSize.width + (backgroundPadding * 2)
        canvasHeight = exportSize.height + (backgroundPadding * 2)
    } else {
        canvasWidth = exportSize.width
        canvasHeight = exportSize.height
    }

    let canvasPixels = canvasWidth * canvasHeight
    let dimensionRatio = originalPixels > 0 ? canvasPixels / originalPixels : 1.0
    // ...
}
```

**Status**: ✅ **Already handles padding correctly** in lines 676-684

### 4. Export Process Dimension Usage

**Location**: `VideoEditorExporter.swift:202-234`

```swift
// Calculate target render size BEFORE creating compositor
let baseRenderSize: CGSize
if state.exportSettings.dimensionPreset != .original {
    baseRenderSize = state.exportSettings.exportSize(from: state.naturalSize)
} else {
    baseRenderSize = state.naturalSize
}

// Create zoom compositor with correct render size from the start
let zoomCompositor = ZoomCompositor(
    zooms: adjustedZooms,
    renderSize: baseRenderSize,  // Video size (no padding)
    backgroundStyle: state.backgroundStyle,
    backgroundPadding: state.backgroundPadding,  // Padding passed separately
    cornerRadius: state.backgroundCornerRadius
)

// ...
videoComposition.renderSize = zoomCompositor.paddedRenderSize  // Final size with padding
```

**Responsibilities**:
- `baseRenderSize`: Video content dimensions (from exportSettings)
- `backgroundPadding`: Passed separately to ZoomCompositor
- `paddedRenderSize`: Final canvas size calculated by compositor

---

## Data Path Summary

### Complete Flow

1. **UI Selection** → `VideoExportSettingsPanel`
   - User picks dimension preset (Original/1080p/720p/480p/Custom)

2. **State Update** → `VideoEditorState.updateExportSettings()`
   - Triggers `recalculateEstimatedFileSize()`
   - Updates `exportSettings` property

3. **Size Estimation** → `calculateEstimatedFileSize()`
   - Calls `exportSettings.exportSize(from: naturalSize)` → gets **video dimensions**
   - Adds `backgroundPadding * 2` → gets **canvas dimensions**
   - Uses canvas pixels for file size ratio calculation

4. **Export Execution** → `VideoEditorExporter.exportWithZooms()`
   - Calls `exportSettings.exportSize(from: naturalSize)` → gets **baseRenderSize**
   - Passes `baseRenderSize` + `backgroundPadding` to `ZoomCompositor`
   - Compositor calculates `paddedRenderSize` and sets `videoComposition.renderSize`

### Change Triggers

**Current triggers** (`VideoEditorState.swift:738-772`):

✅ Trim changes → `$trimStart`, `$trimEnd`
✅ Audio changes → `$isMuted`
✅ Zoom changes → `$zoomSegments`
✅ Background changes → `$backgroundStyle`, `$backgroundPadding`, `$backgroundShadowIntensity`, `$backgroundCornerRadius`
✅ Export settings → `$exportSettings`

**File size recalculation triggered by**:
- Background changes (lines 758-764)
- Export settings changes (lines 767-772)

---

## Issues Identified

### ❌ None - Implementation is Correct

The current implementation **correctly separates concerns**:

1. `ExportSettings.exportSize()` returns **video content dimensions** only
2. File size calculation **adds padding** when computing canvas pixels
3. Export process **passes padding separately** to compositor
4. Compositor **combines both** to produce final render size

**This design is intentional and correct.**

---

## Recommendations

### 1. Documentation Enhancement

Add inline comments to clarify dimension semantics:

```swift
/// Compute actual export dimensions for VIDEO CONTENT ONLY
/// Note: Background padding is applied separately during rendering
func exportSize(from naturalSize: CGSize) -> CGSize {
    // ...
}
```

### 2. Validation Check (Optional)

Add assertion in `calculateEstimatedFileSize()`:

```swift
// Validate canvas size is larger than export size when padding exists
if backgroundStyle != .none && backgroundPadding > 0 {
    assert(canvasWidth > exportSize.width, "Canvas should include padding")
    assert(canvasHeight > exportSize.height, "Canvas should include padding")
}
```

### 3. No Code Changes Required

The dimension flow is **working as designed**. No fixes needed for dimension calculation logic.

---

## Code References

### Key Files

1. **ExportSettings.swift**
   - `ExportDimensionPreset` enum (lines 59-78)
   - `ExportSettings.exportSize()` method (lines 92-112)

2. **VideoEditorState.swift**
   - `exportSettings` property (line 110)
   - `naturalSize` property (line 45)
   - `updateExportSettings()` method (lines 646-649)
   - `calculateEstimatedFileSize()` method (lines 659-702)
   - Change tracking setup (lines 738-772)

3. **VideoEditorExporter.swift**
   - Dimension calculation before export (lines 202-210)
   - ZoomCompositor initialization (lines 214-220)
   - RenderSize assignment (line 234)

---

## Unresolved Questions

None - dimension flow is functioning correctly per architectural design.

---

**Conclusion**: The dimension configuration flow correctly separates video content dimensions from canvas dimensions. The `exportSize()` method intentionally returns video-only dimensions, while padding is applied separately in both file size estimation and export rendering. No architectural changes needed.
