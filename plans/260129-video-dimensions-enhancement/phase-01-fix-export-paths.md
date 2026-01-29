# Phase 01: Fix Dimension Application in Export Paths

**Status**: Pending
**Estimated Effort**: Medium
**Files**: `ClaudeShot/Features/VideoEditor/Export/VideoEditorExporter.swift`

---

## Objective

Ensure custom export dimensions are applied in standard export and video-only export paths, not just composition export.

## Current State

### Export Path Routing (lines 18-40)
```swift
// 1. Composition export - HAS dimension support
if hasZooms || hasBackground {
  try await exportWithZooms(...) // Dimensions applied correctly
}

// 2. Video-only export - MISSING dimension support
if state.exportSettings.audioMode == .mute {
  try await exportVideoOnly(...) // Uses preset only
}

// 3. Standard export - MISSING dimension support
try await exportStandard(...) // Uses preset only
```

### Gap Analysis

| Export Path | Location | Dimension Support |
|-------------|----------|-------------------|
| `exportWithZooms()` | L94-293 | Yes - uses exportSize() |
| `exportStandard()` | L43-91 | No - uses preset only |
| `exportVideoOnly()` | L296-347 | No - uses preset only |

## Implementation

### Task 1: Fix `exportStandard()` (lines 43-91)

Add AVMutableVideoComposition when dimensions differ from original.

**Insert after line 66** (after `exportSession.timeRange = timeRange`):

```swift
// Apply custom dimensions if not using original size
if state.exportSettings.dimensionPreset != .original {
  let targetSize = state.exportSettings.exportSize(from: state.naturalSize)

  // Get video track for composition
  if let videoTrack = try await state.asset.loadTracks(withMediaType: .video).first {
    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = targetSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

    // Create layer instruction for scaling
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = timeRange

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

    // Calculate scale transform
    let naturalSize = state.naturalSize
    let scaleX = targetSize.width / naturalSize.width
    let scaleY = targetSize.height / naturalSize.height
    let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
    layerInstruction.setTransform(transform, at: .zero)

    instruction.layerInstructions = [layerInstruction]
    videoComposition.instructions = [instruction]

    exportSession.videoComposition = videoComposition
    print("📹 [Export] Applied custom dimensions: \(targetSize)")
  }
}
```

### Task 2: Fix `exportVideoOnly()` (lines 296-347)

Add AVMutableVideoComposition after composition creation.

**Insert after line 320** (after `compositionVideoTrack.preferredTransform = transform`):

```swift
// Create video composition for custom dimensions
var videoComposition: AVMutableVideoComposition?
if state.exportSettings.dimensionPreset != .original {
  let targetSize = state.exportSettings.exportSize(from: state.naturalSize)

  let composition = AVMutableVideoComposition()
  composition.renderSize = targetSize
  composition.frameDuration = CMTime(value: 1, timescale: 30)

  // Create layer instruction for scaling
  let instruction = AVMutableVideoCompositionInstruction()
  instruction.timeRange = CMTimeRange(start: .zero, duration: compositionVideoTrack.timeRange.duration)

  let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)

  // Calculate scale transform
  let naturalSize = state.naturalSize
  let scaleX = targetSize.width / naturalSize.width
  let scaleY = targetSize.height / naturalSize.height
  let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
  layerInstruction.setTransform(transform.concatenating(scaleTransform), at: .zero)

  instruction.layerInstructions = [layerInstruction]
  composition.instructions = [instruction]

  videoComposition = composition
  print("📹 [Export] Video-only: Applied custom dimensions: \(targetSize)")
}
```

**Modify line 331-332** to apply video composition:

```swift
exportSession.outputFileType = outputFileType(for: state.fileExtension)
if let videoComposition = videoComposition {
  exportSession.videoComposition = videoComposition
}
```

## Verification

1. Export video with 720p preset, no zoom/background - verify output is 720p
2. Export video with 720p preset, audio muted - verify output is 720p
3. Export video with custom 800x600, no effects - verify output is 800x600

## Test Cases

| Scenario | Dimension Preset | Expected Output |
|----------|------------------|-----------------|
| Standard export, 1080p source | 720p | 1280x720 |
| Standard export, 1080p source | 50% | 960x540 |
| Video-only export, 1080p source | 480p | 854x480 |
| Any export | Original | Source dimensions |

---

## Code References

- `VideoEditorExporter.swift`: Lines 43-91 (standard), Lines 296-347 (video-only)
- `ExportSettings.exportSize()`: Lines 92-112 in ExportSettings.swift
