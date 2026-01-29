# Phase 03: Update UI to Show Reduction Percentage

**Status**: Pending
**Estimated Effort**: Low
**Files**: `ClaudeShot/Features/VideoEditor/Views/VideoExportSettingsPanel.swift`

---

## Objective

Update the dimensions picker to display percentage and calculated dimensions for each preset option, making it easier for users to understand the output size.

## Current State

```swift
Picker("", selection: dimensionPresetBinding) {
  ForEach(ExportDimensionPreset.allCases) { preset in
    Text(preset.rawValue).tag(preset)  // Shows only "50%", "720p", etc.
  }
}
```

## Implementation

### Task 1: Update Dimensions Picker (lines 91-98)

**Replace lines 91-98** with:

```swift
// Preset picker with dimension labels
Picker("", selection: dimensionPresetBinding) {
  ForEach(ExportDimensionPreset.allCases) { preset in
    Text(preset.displayLabel(for: state.naturalSize))
      .tag(preset)
  }
}
.pickerStyle(.menu)
.frame(minWidth: 140)  // Increased to fit longer labels
.controlSize(.small)
```

### Task 2: Update Dimension Display Text (lines 226-229)

The `dimensionDisplayText` helper can remain as-is for showing computed dimensions below the picker, but update for consistency:

**Replace lines 226-229** with:

```swift
private var dimensionDisplayText: String {
  let size = state.exportSettings.exportSize(from: state.naturalSize)
  let naturalSize = state.naturalSize

  // Calculate reduction percentage if applicable
  if state.exportSettings.dimensionPreset == .original {
    return "\(Int(size.width)) x \(Int(size.height))"
  }

  let reduction = (1.0 - (size.width * size.height) / (naturalSize.width * naturalSize.height)) * 100
  if reduction > 0 {
    return "\(Int(size.width)) x \(Int(size.height)) (-\(Int(reduction))%)"
  }
  return "\(Int(size.width)) x \(Int(size.height))"
}
```

### Task 3: Simplify Display for Non-Custom Presets

Since the picker now shows dimensions, we can simplify the below-picker display.

**Update lines 101-109** to:

```swift
// Custom dimension fields or reduction info
if state.exportSettings.dimensionPreset == .custom {
  customDimensionFields
} else if state.exportSettings.dimensionPreset != .original {
  // Show file size impact hint
  let size = state.exportSettings.exportSize(from: state.naturalSize)
  let originalPixels = state.naturalSize.width * state.naturalSize.height
  let newPixels = size.width * size.height
  let reduction = Int((1.0 - newPixels / originalPixels) * 100)

  if reduction > 0 {
    Text("~\(reduction)% smaller file size")
      .font(.system(size: 9))
      .foregroundColor(.green.opacity(0.8))
  }
}
```

## UI Preview

### Before
```
Dimensions
[Original        v]
1920 x 1080
```

### After
```
Dimensions
[50% (960x540)   v]
~75% smaller file size
```

## Verification

1. Open export settings panel
2. Click dimension picker - verify all options show dimensions
3. Select 50% preset - verify picker shows "50% (960x540)" for 1080p source
4. Select 720p preset - verify picker shows "720p (1280x720)" for 16:9 source
5. Verify "smaller file size" hint appears for reduction presets

## Picker Options Display

| Preset | Display for 1920x1080 Source |
|--------|------------------------------|
| Original | Original (1920x1080) |
| 75% | 75% (1440x810) |
| 50% | 50% (960x540) |
| 25% | 25% (480x270) |
| 1080p | 1080p (1920x1080) |
| 720p | 720p (1280x720) |
| 480p | 480p (854x480) |
| Custom | Custom |

---

## Code References

- `dimensionsSection`: Lines 84-111
- `dimensionDisplayText`: Lines 226-229
- `dimensionPresetBinding`: Lines 233-246
