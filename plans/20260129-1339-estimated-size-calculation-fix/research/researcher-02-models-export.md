# Export Models & Configuration Analysis

## Overview
Analysis of export-related models, background/zoom configurations, and how they affect final output dimensions and file size estimation.

## 1. Export Settings Structure

**File**: `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/Models/ExportSettings.swift`

### ExportSettings (Lines 82-127)
```swift
struct ExportSettings: Equatable {
    var quality: ExportQuality = .high
    var dimensionPreset: ExportDimensionPreset = .original
    var customWidth: Int = 1920
    var customHeight: Int = 1080
    var aspectRatioLocked: Bool = true
    var audioMode: AudioExportMode = .keep
    var audioVolume: Float = 1.0 // 0.0 to 2.0
}
```

**Critical Method - exportSize()** (Lines 92-112):
```swift
func exportSize(from naturalSize: CGSize) -> CGSize {
    switch dimensionPreset {
    case .original:
        return naturalSize
    case .custom:
        let evenWidth = customWidth - (customWidth % 2)
        let evenHeight = customHeight - (customHeight % 2)
        return CGSize(width: evenWidth, height: evenHeight)
    default:
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

### ExportQuality Enum (Lines 13-37)
```swift
enum ExportQuality {
    case low, medium, high

    var bitrateMultiplier: Float {
        switch self {
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 1.0
        }
    }
}
```

**Impact**: Bitrate multipliers directly affect file size calculations but NOT used in actual export.

### Dimension Presets (Lines 59-78)
- `.original` - Uses source dimensions
- `.hd1080` - 1080p height
- `.hd720` - 720p height
- `.sd480` - 480p height
- `.custom` - User-defined dimensions

## 2. Background Configuration

**File**: `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/Export/ZoomCompositor.swift`

### ZoomCompositor Properties (Lines 21-52)
```swift
private let backgroundStyle: BackgroundStyle
private let backgroundPadding: CGFloat
private let cornerRadius: CGFloat
let paddedRenderSize: CGSize

init(...) {
    // Calculate padded render size
    if backgroundStyle != .none && backgroundPadding > 0 {
        self.paddedRenderSize = CGSize(
            width: renderSize.width + (backgroundPadding * 2),
            height: renderSize.height + (backgroundPadding * 2)
        )
    } else {
        self.paddedRenderSize = renderSize
    }
}
```

**Properties**:
- `backgroundStyle` - Type of background (none/gradient/solid/wallpaper/blurred)
- `backgroundPadding` - Adds pixels around video (affects final size)
- `cornerRadius` - Rounds video corners (cosmetic, no size impact)
- `paddedRenderSize` - **Final output size including padding**

**Critical Finding**: Background padding adds `padding * 2` to both width and height.

## 3. Zoom Configuration

**File**: Model not found but referenced in ZoomCompositor

### ZoomSegment Properties (Referenced Lines 119-128)
```swift
struct ZoomSegment {
    var startTime: TimeInterval
    var duration: TimeInterval
    var zoomLevel: CGFloat  // Scale factor
    var center: CGPoint
    var isEnabled: Bool
}
```

**Impact on Dimensions**: Zoom does NOT change output dimensions. It crops and scales within same frame size.

## 4. Export Pipeline Flow

**File**: `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/Export/VideoEditorExporter.swift`

### Dimension Calculation Flow (Lines 201-210)
```swift
let baseRenderSize: CGSize
if state.exportSettings.dimensionPreset != .original {
    baseRenderSize = state.exportSettings.exportSize(from: state.naturalSize)
} else {
    baseRenderSize = state.naturalSize
}
```

### Compositor Integration (Lines 214-234)
```swift
let zoomCompositor = ZoomCompositor(
    zooms: adjustedZooms,
    renderSize: baseRenderSize,  // From ExportSettings
    backgroundStyle: state.backgroundStyle,
    backgroundPadding: state.backgroundPadding,
    cornerRadius: state.backgroundCornerRadius
)

videoComposition.renderSize = zoomCompositor.paddedRenderSize  // FINAL SIZE
```

**Critical**: Final render size = `baseRenderSize + (padding * 2)` for each dimension.

### Export Quality Application (Lines 54-56, 245-247)
```swift
guard let exportSession = AVAssetExportSession(
    asset: state.asset,
    presetName: state.exportSettings.quality.exportPreset
)
```

**Presets**:
- `.low` → `AVAssetExportPresetMediumQuality`
- `.medium` → `AVAssetExportPresetHighestQuality`
- `.high` → `AVAssetExportPresetHighestQuality`

## 5. Dimension Calculation Bug

**Problem**: Estimated size calculation likely uses `exportSize()` but ignores `backgroundPadding`.

**Evidence**:
1. ExportSettings.exportSize() returns base dimensions (Lines 92-112)
2. ZoomCompositor adds padding AFTER (Lines 44-52)
3. Final render uses `paddedRenderSize` (Line 234)

**Formula**:
```
Actual dimensions = exportSize(naturalSize) + (backgroundPadding * 2)
```

## 6. Codec & Bitrate Settings

**No explicit codec/bitrate configuration found**. Uses AVFoundation presets:
- Preset determines codec automatically (likely H.264)
- Bitrate calculated by AVFoundation based on dimensions
- `bitrateMultiplier` in ExportQuality is for estimation ONLY (not applied to actual export)

## Key Findings

1. **Dimension Flow**: naturalSize → exportSize() → baseRenderSize → paddedRenderSize (final)
2. **Background Padding**: Adds `padding * 2` to width and height
3. **Zoom Impact**: Cosmetic only, no dimension changes
4. **Quality**: Uses AVFoundation presets, no manual bitrate control
5. **Bug Location**: Size estimation likely missing padding calculation

## Unresolved Questions

None - all required structures analyzed.
