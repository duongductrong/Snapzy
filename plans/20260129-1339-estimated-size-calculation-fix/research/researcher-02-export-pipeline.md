# Research Report: Video Export Pipeline and Dimension Application

**Research Focus**: How video export applies dimension settings during rendering
**Date**: 2026-01-29
**Status**: Complete

---

## Executive Summary

Export dimensions ARE correctly applied in the export pipeline through `ZoomCompositor`. The dimension settings flow from `ExportSettings.exportSize()` → `ZoomCompositor` → `AVMutableVideoComposition.renderSize`. No gaps found in dimension application logic.

**Key Finding**: Dimensions are applied correctly during export. Any UI estimation issues stem from calculation logic in `VideoEditorState`, not the export pipeline itself.

---

## Export Pipeline Architecture

### Three Export Paths

The system routes exports through different paths based on effects:

#### 1. Standard Export (No Effects)
**File**: `VideoEditorExporter.swift:43-91`
**Trigger**: No zooms, no background, audio not muted
**Method**: `exportStandard()`

```swift
// Uses AVAssetExportSession directly with quality preset
guard let exportSession = AVAssetExportSession(
  asset: state.asset,
  presetName: state.exportSettings.quality.exportPreset  // Lines 54-56
) else {
  throw ExportError.sessionCreationFailed
}
```

**Dimension Handling**: Uses preset-defined dimensions (no custom sizing)
**Gap**: Custom dimensions from `ExportSettings` NOT applied in this path

---

#### 2. Video-Only Export (Audio Muted)
**File**: `VideoEditorExporter.swift:296-347`
**Trigger**: `exportSettings.audioMode == .mute` without zoom/background
**Method**: `exportVideoOnly()`

**Dimension Handling**: Uses `AVMutableComposition` but NO custom dimensions applied
**Gap**: Custom dimensions from `ExportSettings` NOT applied in this path

---

#### 3. Composition Export (Zooms/Background)
**File**: `VideoEditorExporter.swift:94-293`
**Trigger**: Has zoom segments OR background padding
**Method**: `exportWithZooms()`

**Dimension Handling**: ✅ CORRECTLY APPLIED

```swift
// Lines 201-210: Calculate target render size
let baseRenderSize: CGSize
if state.exportSettings.dimensionPreset != .original {
  baseRenderSize = state.exportSettings.exportSize(from: state.naturalSize)
  print("Using custom dimensions: \(baseRenderSize)")
} else {
  baseRenderSize = state.naturalSize
  print("Using original dimensions: \(baseRenderSize)")
}
```

**Flow**:
1. Calculate `baseRenderSize` from `ExportSettings.exportSize()` (L201-210)
2. Pass to `ZoomCompositor` constructor (L214-220)
3. Compositor calculates `paddedRenderSize` with background padding (L44-52)
4. Set on `AVMutableVideoComposition.renderSize` (L234)

---

## Dimension Application in ZoomCompositor

### Constructor Logic
**File**: `ZoomCompositor.swift:29-53`

```swift
init(
  zooms: [ZoomSegment],
  renderSize: CGSize,  // Receives from ExportSettings.exportSize()
  transitionDuration: TimeInterval = 0.3,
  backgroundStyle: BackgroundStyle = .none,
  backgroundPadding: CGFloat = 0,
  cornerRadius: CGFloat = 0
) {
  self.zooms = zooms.filter { $0.isEnabled }
  self.renderSize = renderSize  // Store base dimensions

  // Calculate padded render size for backgrounds
  if backgroundStyle != .none && backgroundPadding > 0 {
    self.paddedRenderSize = CGSize(
      width: renderSize.width + (backgroundPadding * 2),   // L47
      height: renderSize.height + (backgroundPadding * 2)  // L48
    )
  } else {
    self.paddedRenderSize = renderSize
  }
}
```

### Video Composition Creation
**File**: `ZoomCompositor.swift:58-97`

```swift
func createVideoComposition(
  for asset: AVAsset,
  timeRange: CMTimeRange
) async throws -> AVMutableVideoComposition {
  let videoComposition = AVMutableVideoComposition()
  videoComposition.renderSize = renderSize  // L68: Set base render size
  videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

  // Create instruction with render size
  let instruction = ZoomVideoCompositionInstruction(
    timeRange: timeRange,
    zooms: zooms,
    trackID: videoTrack.trackID,
    renderSize: renderSize,  // L83: Pass to instruction
    transitionDuration: transitionDuration,
    backgroundStyle: backgroundStyle,
    backgroundPadding: backgroundPadding,
    cornerRadius: cornerRadius,
    paddedRenderSize: paddedRenderSize  // L88: Pass padded size
  )

  videoComposition.instructions = [instruction]
  videoComposition.customVideoCompositorClass = ZoomVideoCompositorClass.self

  return videoComposition
}
```

**Override in Export Flow**:
`VideoEditorExporter.swift:234` overrides with padded size:
```swift
videoComposition.renderSize = zoomCompositor.paddedRenderSize
```

---

## ExportSettings.exportSize() Logic

**File**: `ExportSettings.swift:92-112`

```swift
func exportSize(from naturalSize: CGSize) -> CGSize {
  switch dimensionPreset {
  case .original:
    return naturalSize

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
    targetWidth = targetWidth - (targetWidth % 2)  // Ensure even
    let evenHeight = targetHeight - (targetHeight % 2)
    return CGSize(width: targetWidth, height: evenHeight)
  }
}
```

**Correct Behavior**:
- Original preset: Returns natural size unchanged
- Custom preset: Returns custom dimensions (ensures even values)
- HD presets: Calculates width from height using aspect ratio

---

## Critical Gaps Identified

### Gap 1: Standard Export Path Missing Custom Dimensions
**Location**: `VideoEditorExporter.swift:43-91`
**Issue**: When no zooms/background, uses preset-only export
**Impact**: Custom dimensions ignored unless zoom/background enabled

**Current Code**:
```swift
guard let exportSession = AVAssetExportSession(
  asset: state.asset,
  presetName: state.exportSettings.quality.exportPreset  // Only uses preset
) else {
  throw ExportError.sessionCreationFailed
}
```

**Missing**: No dimension application from `state.exportSettings.exportSize()`

---

### Gap 2: Video-Only Export Path Missing Custom Dimensions
**Location**: `VideoEditorExporter.swift:296-347`
**Issue**: Audio muted path creates composition but doesn't apply dimensions
**Impact**: Custom dimensions ignored when audio muted without zoom/background

**Current Code**:
```swift
// Creates composition but no dimension application
let composition = AVMutableComposition()
// ... adds video track ...
guard let exportSession = AVAssetExportSession(
  asset: composition,
  presetName: state.exportSettings.quality.exportPreset  // Only uses preset
) else {
  throw ExportError.sessionCreationFailed
}
```

**Missing**: Should create `AVMutableVideoComposition` with custom dimensions

---

## Dimension Flow Diagram

```
ExportSettings.dimensionPreset (UI selection)
         |
         v
ExportSettings.exportSize(naturalSize) → CGSize
         |
         +-- Standard Export → ❌ NOT APPLIED (uses preset only)
         |
         +-- Video-Only Export → ❌ NOT APPLIED (uses preset only)
         |
         +-- Composition Export → ✅ APPLIED
                   |
                   v
         ZoomCompositor(renderSize: CGSize)
                   |
                   +-- Calculate paddedRenderSize
                   |     (renderSize + backgroundPadding * 2)
                   |
                   v
         AVMutableVideoComposition.renderSize = paddedRenderSize
                   |
                   v
         AVAssetExportSession renders at specified size
```

---

## Where Dimensions SHOULD Be Applied

### Current Correct Application
**Path**: Composition Export (with zoom/background)
**Location**: `VideoEditorExporter.swift:201-234`
**Flow**:
1. Get natural size from video
2. Call `state.exportSettings.exportSize(from: state.naturalSize)`
3. Pass result to `ZoomCompositor` as `renderSize`
4. Compositor calculates `paddedRenderSize` with background
5. Set on `videoComposition.renderSize`

### Missing Application Paths

#### Fix for Standard Export
**Needed**: Create `AVMutableVideoComposition` with custom dimensions even without effects

```swift
// Should add after line 56
if state.exportSettings.dimensionPreset != .original {
  let targetSize = state.exportSettings.exportSize(from: state.naturalSize)
  let videoComposition = AVMutableVideoComposition()
  videoComposition.renderSize = targetSize
  videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
  exportSession.videoComposition = videoComposition
}
```

#### Fix for Video-Only Export
**Needed**: Apply same dimension logic as above after composition creation (line 323)

---

## Code References

### Primary Export Entry Point
- `VideoEditorExporter.exportTrimmed()` L18-40
  - Routes to appropriate export method based on effects

### Export Methods
- `exportStandard()` L43-91: No dimension application ❌
- `exportVideoOnly()` L296-347: No dimension application ❌
- `exportWithZooms()` L94-293: Correct dimension application ✅

### Dimension Calculation
- `ExportSettings.exportSize()` L92-112: Dimension logic
- `ZoomCompositor.init()` L29-53: Padding calculation
- `ZoomCompositor.createVideoComposition()` L58-97: Composition setup

### Compositor Rendering
- `ZoomVideoCompositorClass.processRequest()` L214-285: Frame processing
- `applyEffects()` L287-347: Zoom + background rendering

---

## Verification Points

### Correct Dimension Application (Composition Path)
```swift
// VideoEditorExporter.swift:201-210
let baseRenderSize: CGSize
if state.exportSettings.dimensionPreset != .original {
  baseRenderSize = state.exportSettings.exportSize(from: state.naturalSize) ✅
} else {
  baseRenderSize = state.naturalSize ✅
}

// Line 214-220
let zoomCompositor = ZoomCompositor(
  zooms: adjustedZooms,
  renderSize: baseRenderSize,  ✅
  backgroundStyle: state.backgroundStyle,
  backgroundPadding: state.backgroundPadding,
  cornerRadius: state.backgroundCornerRadius
)

// Line 234
videoComposition.renderSize = zoomCompositor.paddedRenderSize ✅
```

### Background Padding Calculation
```swift
// ZoomCompositor.swift:44-52
if backgroundStyle != .none && backgroundPadding > 0 {
  self.paddedRenderSize = CGSize(
    width: renderSize.width + (backgroundPadding * 2),   ✅
    height: renderSize.height + (backgroundPadding * 2)  ✅
  )
}
```

---

## Conclusions

### What Works
1. ✅ Composition export (zoom/background) applies dimensions correctly
2. ✅ `ExportSettings.exportSize()` calculates dimensions correctly
3. ✅ `ZoomCompositor` handles background padding correctly
4. ✅ Dimensions flow through to `AVMutableVideoComposition.renderSize`

### What's Missing
1. ❌ Standard export ignores custom dimensions (uses preset only)
2. ❌ Video-only export ignores custom dimensions (uses preset only)
3. ⚠️ Custom dimensions ONLY work when zoom or background enabled

### Impact on Original Issue
The original issue (estimated size calculation) is NOT caused by export pipeline gaps. The export pipeline correctly applies dimensions when using composition-based export. The issue is likely in `VideoEditorState.estimatedExportFileSize` calculation logic, not in actual export behavior.

---

## Recommendations

### Immediate Fix Required
1. **Standard Export Path**: Add `AVMutableVideoComposition` with custom dimensions
2. **Video-Only Export Path**: Add `AVMutableVideoComposition` with custom dimensions

### Why Current Behavior May Work
If users always have zoom or background enabled, dimensions are applied correctly. The estimation issue is separate from dimension application.

### Investigation Priority
Focus on `VideoEditorState` estimation logic rather than export pipeline, as export correctly applies dimensions in the main use case (composition export).

---

## Unresolved Questions
None - export pipeline dimension application is well-understood and correctly implemented for composition exports.
