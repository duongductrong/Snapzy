# Scout Report: QuickAccess & Recording Codebase Analysis

**Date:** 2026-01-17
**Scope:** QuickAccess feature and Recording integration points

## Relevant Files

### QuickAccess Feature
| File | Purpose | Lines |
|------|---------|-------|
| `QuickAccessItem.swift` | Data model for captured items | 28 |
| `QuickAccessCardView.swift` | Single card UI with hover/actions | 109 |
| `QuickAccessStackView.swift` | Container for stacked cards | 33 |
| `QuickAccessManager.swift` | State management, add/remove/copy/save | 261 |
| `ThumbnailGenerator.swift` | Thumbnail generation from images | 57 |
| `QuickAccessPanel.swift` | Panel window management | - |
| `QuickAccessPanelController.swift` | Panel controller | - |
| `QuickAccessActionButton.swift` | Action button component | - |
| `QuickAccessTextButton.swift` | Text button component | - |

### Recording Feature
| File | Purpose | Lines |
|------|---------|-------|
| `RecordingCoordinator.swift` | Recording flow coordination | 285 |
| `ScreenRecordingManager.swift` | Core recording engine | 469 |

### Annotation Feature (Reference Pattern)
| File | Purpose | Lines |
|------|---------|-------|
| `AnnotateManager.swift` | Window management singleton | 92 |
| `AnnotateWindow.swift` | Dark mode window config | 35 |
| `AnnotateWindowController.swift` | Window controller lifecycle | 163 |

## Key Patterns Identified

### 1. QuickAccessItem Model
```swift
struct QuickAccessItem: Identifiable, Equatable {
  let id: UUID
  let url: URL
  let thumbnail: NSImage
  let capturedAt: Date
}
```
- Simple value type
- No type discrimination (screenshot only)
- No duration property

### 2. QuickAccessManager Integration
```swift
func addScreenshot(url: URL) async {
  guard let thumbnail = await ThumbnailGenerator.generate(from: url) else { return }
  let item = QuickAccessItem(url: url, thumbnail: thumbnail)
  items.insert(item, at: 0)
}
```
- Async thumbnail generation
- Inserts at front (newest first)
- Auto-dismiss timer support

### 3. QuickAccessCardView Actions
- **Copy**: `manager.copyToClipboard(id:)` - copies NSImage to pasteboard
- **Save**: `manager.openInFinder(id:)` - reveals in Finder
- **Double-click**: Opens `AnnotateManager.shared.openAnnotation(for: item)`

### 4. AnnotateManager Pattern (for VideoEditorManager)
```swift
@MainActor
final class AnnotateManager {
  static let shared = AnnotateManager()
  private var windowControllers: [UUID: AnnotateWindowController] = [:]

  func openAnnotation(for item: QuickAccessItem) {
    // Check existing, create controller, track window
  }
}
```

### 5. RecordingCoordinator Stop Flow
```swift
private func stopRecording() {
  Task {
    let url = await recorder.stopRecording()
    if let url = url {
      NSSound(named: "Glass")?.play()
      NSWorkspace.shared.activateFileViewerSelecting([url])  // Currently opens Finder
    }
    cleanup()
  }
}
```
**Integration Point:** Replace Finder reveal with QuickAccessManager.addVideo()

## Integration Requirements

1. **Extend QuickAccessItem** - Add `itemType` enum and optional `duration`
2. **Extend ThumbnailGenerator** - Add video support using AVAssetImageGenerator
3. **Extend QuickAccessManager** - Add `addVideo(url:)` method
4. **Modify QuickAccessCardView** - Add duration badge, conditional double-click
5. **Create VideoEditorManager** - Following AnnotateManager pattern
6. **Modify RecordingCoordinator** - Call QuickAccessManager after recording
