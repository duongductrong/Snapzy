# VideoEditorState Estimation Logic Analysis

## Location & Implementation

**Primary File**: `/Users/duongductrong/Developer/ZapShot/ClaudeShot/Features/VideoEditor/State/VideoEditorState.swift`

### State Property (Line 111)
```swift
@Published private(set) var estimatedFileSize: Int64 = 0
```

### Public API (Lines 644-647)
```swift
func updateExportSettings(_ settings: ExportSettings) {
  exportSettings = settings
  recalculateEstimatedFileSize()
}
```

### Recalculation Trigger (Lines 650-654)
```swift
func recalculateEstimatedFileSize() {
  Task { @MainActor in
    estimatedFileSize = await calculateEstimatedFileSize()
  }
}
```

### Core Calculation Logic (Lines 657-689)
```swift
private func calculateEstimatedFileSize() async -> Int64 {
  // Get source file size
  guard let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
        let sourceSize = attrs[.size] as? Int64 else { return 0 }

  let sourceDuration = CMTimeGetSeconds(duration)
  guard sourceDuration > 0 else { return 0 }

  // Calculate trim ratio
  let trimmedDurationSec = CMTimeGetSeconds(trimmedDuration)
  let trimRatio = trimmedDurationSec / sourceDuration

  // Calculate dimension ratio
  let exportSize = exportSettings.exportSize(from: naturalSize)
  let originalPixels = naturalSize.width * naturalSize.height
  let exportPixels = exportSize.width * exportSize.height
  let dimensionRatio = originalPixels > 0 ? exportPixels / originalPixels : 1.0

  // Apply quality multiplier
  let qualityMultiplier = Double(exportSettings.quality.bitrateMultiplier)

  // Audio adjustment (rough estimate: audio is ~10% of file)
  let audioMultiplier: Double = {
    switch exportSettings.audioMode {
    case .mute: return 0.9 // Remove audio portion
    case .keep, .custom: return 1.0
    }
  }()

  // Calculate estimated size
  let estimated = Double(sourceSize) * trimRatio * dimensionRatio * qualityMultiplier * audioMultiplier
  return Int64(max(estimated, 1024)) // Minimum 1KB
}
```

## When/How Estimation is Calculated

### Initial Calculation
- Triggered via Combine publisher in `setupChangeTracking()` (Lines 752-758)
```swift
$exportSettings
  .dropFirst()
  .sink { [weak self] _ in
    self?.recalculateEstimatedFileSize()
  }
  .store(in: &cancellables)
```

### Manual Triggers
- Every call to `updateExportSettings()` from UI (VideoExportSettingsPanel.swift)
- Called from 8 different UI bindings: quality, dimensions, audio mode, custom width/height, aspect ratio lock, volume

## Current Inputs Used

1. **Source file size** - `FileManager.default.attributesOfItem`
2. **Trim ratio** - `trimmedDuration / sourceDuration`
3. **Dimension ratio** - `exportPixels / originalPixels` from `exportSettings.exportSize(from: naturalSize)`
4. **Quality multiplier** - `exportSettings.quality.bitrateMultiplier`
5. **Audio multiplier** - Based on `exportSettings.audioMode` (mute = 0.9, keep/custom = 1.0)

## Missing Inputs (Critical Gap)

### Background Effects (NOT included)
- **backgroundStyle** (Lines 79-83) - solid, gradient, wallpaper, blurred
- **backgroundPadding** (Line 84) - adds canvas size
- **backgroundShadowIntensity** (Line 96)
- **backgroundCornerRadius** (Line 97)

**Impact**: Background adds canvas size (padding), blur processing increases file size, additional rendering layers ignored

### Zoom Effects (NOT included)
- **zoomSegments** (Line 71) - array of zoom transformations
- **ZoomSegment properties**: startTime, duration, zoomLevel, zoomCenter

**Impact**: Zoom processing can increase file size due to scaling/interpolation overhead

## Current Formula
```
estimatedSize = sourceSize × trimRatio × dimensionRatio × qualityMultiplier × audioMultiplier
```

## Required Formula (with missing inputs)
```
estimatedSize = sourceSize × trimRatio × canvasRatio × qualityMultiplier × audioMultiplier × zoomMultiplier × backgroundMultiplier
```

Where:
- **canvasRatio** = (exportWidth + padding×2) × (exportHeight + padding×2) / originalPixels
- **zoomMultiplier** = 1.0 + (zoomSegmentsTotalDuration / trimmedDuration) × 0.15 (estimate ~15% overhead)
- **backgroundMultiplier** = based on style complexity (solid=1.0, gradient=1.05, wallpaper=1.1, blurred=1.15)

## Recommendations

1. Extract background config into estimation logic
2. Calculate canvas size from padding (affects dimension ratio)
3. Add zoom processing overhead multiplier
4. Consider background style complexity factor
5. Update recalculation triggers to include background/zoom changes
