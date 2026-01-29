# Phase 02: Add Percentage-Based Dimension Presets

**Status**: Pending
**Estimated Effort**: Low
**Files**: `ClaudeShot/Features/VideoEditor/Models/ExportSettings.swift`

---

## Objective

Add percentage-based reduction presets (75%, 50%, 25%) to ExportDimensionPreset enum, similar to CleanShot's approach.

## Current State

```swift
enum ExportDimensionPreset: String, CaseIterable, Identifiable {
  case original = "Original"
  case hd1080 = "1080p"
  case hd720 = "720p"
  case sd480 = "480p"
  case custom = "Custom"
}
```

## Implementation

### Task 1: Update `ExportDimensionPreset` Enum

**Replace lines 59-78** with:

```swift
enum ExportDimensionPreset: String, CaseIterable, Identifiable {
  case original = "Original"
  case percent75 = "75%"
  case percent50 = "50%"
  case percent25 = "25%"
  case hd1080 = "1080p"
  case hd720 = "720p"
  case sd480 = "480p"
  case custom = "Custom"

  var id: String { rawValue }

  /// Returns target height for fixed presets (width calculated from aspect ratio)
  var targetHeight: Int? {
    switch self {
    case .original, .percent75, .percent50, .percent25, .custom:
      return nil
    case .hd1080:
      return 1080
    case .hd720:
      return 720
    case .sd480:
      return 480
    }
  }

  /// Returns scale factor for percentage-based presets
  var scaleFactor: CGFloat? {
    switch self {
    case .percent75:
      return 0.75
    case .percent50:
      return 0.50
    case .percent25:
      return 0.25
    default:
      return nil
    }
  }

  /// Display label showing dimensions when available
  func displayLabel(for naturalSize: CGSize) -> String {
    switch self {
    case .original:
      return "Original (\(Int(naturalSize.width))x\(Int(naturalSize.height)))"
    case .percent75, .percent50, .percent25:
      guard let scale = scaleFactor else { return rawValue }
      let width = Int(naturalSize.width * scale)
      let height = Int(naturalSize.height * scale)
      // Ensure even dimensions in display
      let evenWidth = width - (width % 2)
      let evenHeight = height - (height % 2)
      return "\(rawValue) (\(evenWidth)x\(evenHeight))"
    case .hd1080, .hd720, .sd480:
      guard let targetH = targetHeight else { return rawValue }
      let aspectRatio = naturalSize.width / naturalSize.height
      var targetW = Int(CGFloat(targetH) * aspectRatio)
      targetW = targetW - (targetW % 2)
      let evenH = targetH - (targetH % 2)
      return "\(rawValue) (\(targetW)x\(evenH))"
    case .custom:
      return "Custom"
    }
  }
}
```

### Task 2: Update `exportSize()` Method

**Replace lines 92-112** with:

```swift
/// Compute actual export dimensions for VIDEO CONTENT ONLY
/// Note: Background padding is applied separately during rendering
func exportSize(from naturalSize: CGSize) -> CGSize {
  switch dimensionPreset {
  case .original:
    return naturalSize

  case .percent75, .percent50, .percent25:
    guard let scale = dimensionPreset.scaleFactor else {
      return naturalSize
    }
    var targetWidth = Int(naturalSize.width * scale)
    var targetHeight = Int(naturalSize.height * scale)
    // Ensure even dimensions for video encoding
    targetWidth = targetWidth - (targetWidth % 2)
    targetHeight = targetHeight - (targetHeight % 2)
    return CGSize(width: targetWidth, height: targetHeight)

  case .custom:
    // Ensure even dimensions for video encoding
    let evenWidth = customWidth - (customWidth % 2)
    let evenHeight = customHeight - (customHeight % 2)
    return CGSize(width: evenWidth, height: evenHeight)

  case .hd1080, .hd720, .sd480:
    guard let targetHeight = dimensionPreset.targetHeight else {
      return naturalSize
    }
    let aspectRatio = naturalSize.width / naturalSize.height
    var targetWidth = Int(CGFloat(targetHeight) * aspectRatio)
    // Ensure even dimensions for video encoding
    targetWidth = targetWidth - (targetWidth % 2)
    let evenHeight = targetHeight - (targetHeight % 2)
    return CGSize(width: targetWidth, height: evenHeight)
  }
}
```

## Verification

1. Select 50% preset on 1920x1080 video - should return 960x540
2. Select 75% preset on 1920x1080 video - should return 1440x810
3. Select 25% preset on 1920x1080 video - should return 480x270
4. Verify all returned dimensions are even numbers

## Test Matrix

| Source Size | Preset | Expected Output |
|-------------|--------|-----------------|
| 1920x1080 | 75% | 1440x810 |
| 1920x1080 | 50% | 960x540 |
| 1920x1080 | 25% | 480x270 |
| 2560x1440 | 50% | 1280x720 |
| 1280x720 | 50% | 640x360 |

---

## Code References

- `ExportDimensionPreset` enum: Lines 59-78
- `exportSize()` method: Lines 92-112
