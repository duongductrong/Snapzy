# Phase 5: VideoEditorExporter Implementation

## Context

- [Phase 5 Main](./phase-05-export-and-save.md)

## VideoEditorExporter

Location: `ZapShot/Features/VideoEditor/Export/VideoEditorExporter.swift`

```swift
import AVFoundation
import Foundation

@MainActor
final class VideoEditorExporter {

    static func exportTrimmed(
        asset: AVAsset,
        timeRange: CMTimeRange,
        outputURL: URL
    ) async throws {
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.sessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputURL.pathExtension == "mov" ? .mov : .mp4
        exportSession.timeRange = timeRange

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw exportSession.error ?? ExportError.unknown
        }
    }

    static func replaceOriginal(
        asset: AVAsset,
        timeRange: CMTimeRange,
        originalURL: URL
    ) async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(originalURL.pathExtension)

        try await exportTrimmed(asset: asset, timeRange: timeRange, outputURL: tempURL)

        try FileManager.default.removeItem(at: originalURL)
        try FileManager.default.moveItem(at: tempURL, to: originalURL)
    }

    static func saveAsCopy(
        asset: AVAsset,
        timeRange: CMTimeRange,
        originalURL: URL
    ) async throws -> URL {
        let copyURL = generateCopyURL(from: originalURL)
        try await exportTrimmed(asset: asset, timeRange: timeRange, outputURL: copyURL)
        return copyURL
    }

    static func generateCopyURL(from original: URL) -> URL {
        let directory = original.deletingLastPathComponent()
        let baseName = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        return directory.appendingPathComponent("\(baseName)_trimmed.\(ext)")
    }

    enum ExportError: Error, LocalizedError {
        case sessionCreationFailed
        case unknown

        var errorDescription: String? {
            switch self {
            case .sessionCreationFailed:
                return "Failed to create export session"
            case .unknown:
                return "Unknown export error"
            }
        }
    }
}
```

## State Additions

Add to VideoEditorState:
```swift
@Published var isExporting: Bool = false
@Published var exportProgress: Double = 0

var trimTimeRange: CMTimeRange {
    CMTimeRange(start: trimStart, end: trimEnd)
}

func markAsSaved() {
    hasUnsavedChanges = false
}
```
