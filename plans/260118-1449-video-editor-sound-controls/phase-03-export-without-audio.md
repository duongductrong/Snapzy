# Phase 3: Export Without Audio

## Context

- [Plan](./plan.md)
- [Phase 1](./phase-01-audio-state.md)
- [Phase 2](./phase-02-audio-ui.md)

## Overview

Modify VideoEditorExporter to optionally exclude audio track when isMuted is true.

## Requirements

1. When state.isMuted is true, export video without audio
2. Use AVMutableComposition to selectively include tracks
3. Maintain video quality during re-export

## Implementation Steps

### Step 1: Add Export Without Audio Method

```swift
/// Export video with optional audio removal
static func exportTrimmedWithOptions(
  state: VideoEditorState,
  to outputURL: URL,
  includeAudio: Bool,
  progress: @escaping (Float) -> Void
) async throws {
  let timeRange = CMTimeRange(start: state.trimStart, end: state.trimEnd)

  if includeAudio {
    // Use simple AVAssetExportSession
    try await exportTrimmed(state: state, to: outputURL, progress: progress)
  } else {
    // Use AVMutableComposition to exclude audio
    try await exportVideoOnly(state: state, to: outputURL, timeRange: timeRange, progress: progress)
  }
}

private static func exportVideoOnly(
  state: VideoEditorState,
  to outputURL: URL,
  timeRange: CMTimeRange,
  progress: @escaping (Float) -> Void
) async throws {
  let composition = AVMutableComposition()

  // Add only video track
  guard let videoTrack = try await state.asset.loadTracks(withMediaType: .video).first else {
    throw ExportError.exportFailed
  }

  let compositionVideoTrack = composition.addMutableTrack(
    withMediaType: .video,
    preferredTrackID: kCMPersistentTrackID_Invalid
  )

  try compositionVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: .zero)

  // Export composition
  guard let exportSession = AVAssetExportSession(
    asset: composition,
    presetName: AVAssetExportPresetHighestQuality
  ) else {
    throw ExportError.sessionCreationFailed
  }

  try? FileManager.default.removeItem(at: outputURL)
  exportSession.outputURL = outputURL
  exportSession.outputFileType = outputFileType(for: state.fileExtension)

  let progressTask = Task {
    while !Task.isCancelled && exportSession.status == .exporting {
      progress(exportSession.progress)
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  await exportSession.export()
  progressTask.cancel()

  guard exportSession.status == .completed else {
    throw exportSession.error ?? ExportError.exportFailed
  }
}
```

### Step 2: Update Existing Export Methods

Modify `replaceOriginal` and `saveAsCopy` to pass `includeAudio: !state.isMuted`

## Todo List

- [ ] Add exportVideoOnly method using AVMutableComposition
- [ ] Add exportTrimmedWithOptions wrapper
- [ ] Update replaceOriginal to use options
- [ ] Update saveAsCopy to use options
- [ ] Test export with/without audio

## Success Criteria

- Muted state exports video without audio track
- Unmuted state exports with audio
- Video quality preserved in both cases
