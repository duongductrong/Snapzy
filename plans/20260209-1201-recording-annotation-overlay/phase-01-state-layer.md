# Phase 1: Recording Annotation State & Data Layer

- **Date**: 2026-02-09
- **Priority**: High
- **Status**: Pending

## Overview
Create lightweight state management for annotations during recording. Reuses existing `AnnotationItem`, `AnnotationType`, `AnnotationToolType` models — only need a new observable state class scoped to recording context.

## Key Insights
- Existing `AnnotateState` is too heavy (700+ lines, crop/mockup/background/undo/redo) — need slim version
- `AnnotationItem` + `AnnotationRenderer` + `AnnotationFactory` are 100% reusable as-is
- No undo/redo needed during recording (linear drawing flow)
- No blur/text/counter/crop/mockup tools during recording

## Requirements
1. New `RecordingAnnotationState` class (~120 lines max)
2. Subset of tools: selection, rectangle, oval, arrow, line, pencil, highlighter
3. Track: annotations array, selected tool, stroke color, stroke width, drawing state
4. Clear all annotations action
5. Delete selected annotation action
6. **Auto-clear system**: Per-tool configurable annotation lifecycle
   - `AnnotationClearMode` enum: `.persist` (never), `.timeBased(seconds: Double)`, `.countBased(count: Int)`
   - `toolClearModes: [AnnotationToolType: AnnotationClearMode]` dictionary on state
   - Each `AnnotationItem` stores `createdAt: Date` and `createdByTool: AnnotationToolType`
   - Timer-based cleanup runs every 0.5s, removes expired time-based annotations with fade
   - Count-based cleanup runs on every new annotation append, removes oldest when threshold exceeded per tool

## Architecture

### New Enum: `AnnotationClearMode`
```swift
enum AnnotationClearMode: Equatable {
  case persist                    // Never auto-clear
  case timeBased(seconds: Double) // Remove after X seconds (3, 5, 10)
  case countBased(count: Int)     // Remove after N newer annotations drawn
}
```

### New File: `Snapzy/Features/Recording/Annotation/RecordingAnnotationState.swift`
```swift
@MainActor
final class RecordingAnnotationState: ObservableObject {
  @Published var annotations: [RecordingAnnotationEntry] = []
  @Published var selectedTool: AnnotationToolType = .pencil
  @Published var selectedAnnotationId: UUID?
  @Published var strokeColor: Color = .red
  @Published var strokeWidth: CGFloat = 3
  @Published var isAnnotationEnabled: Bool = false
  @Published var toolClearModes: [AnnotationToolType: AnnotationClearMode] = [:]

  private var cleanupTimer: Timer?

  static let availableTools: [AnnotationToolType] = [
    .selection, .rectangle, .oval, .arrow, .line, .pencil, .highlighter
  ]

  // Wrapper adding lifecycle metadata to AnnotationItem
  struct RecordingAnnotationEntry: Identifiable, Equatable {
    let id: UUID
    var item: AnnotationItem
    let createdAt: Date
    let createdByTool: AnnotationToolType
    var opacity: Double = 1.0  // For fade-out animation
  }

  func clearMode(for tool: AnnotationToolType) -> AnnotationClearMode {
    toolClearModes[tool] ?? .persist
  }

  func startCleanupTimer() { /* 0.5s interval, calls removeExpired() */ }
  func stopCleanupTimer() { ... }
  func appendAnnotation(_ item: AnnotationItem, tool: AnnotationToolType) {
    // 1. Add entry with createdAt = Date()
    // 2. Run count-based cleanup for this tool
  }
  private func removeExpired() { /* time-based cleanup + fade opacity */ }
  private func enforceCountLimit(for tool: AnnotationToolType) { ... }
  func clearAll() { annotations.removeAll() }
  func deleteSelected() { ... }
}
```

## Related Code Files
- `Snapzy/Features/Annotate/State/AnnotationItem.swift` (reuse as-is)
- `Snapzy/Features/Annotate/State/AnnotationToolType.swift` (reuse as-is)
- `Snapzy/Features/Annotate/Canvas/AnnotationRenderer.swift` (reuse as-is)
- `Snapzy/Features/Annotate/Canvas/AnnotationFactory.swift` (reuse as-is)

## Implementation Steps
1. Create `Snapzy/Features/Recording/Annotation/` directory
2. Create `RecordingAnnotationState.swift` with minimal state
3. Verify AnnotationItem/Renderer/Factory compile independently

## Success Criteria
- State class compiles and holds annotation data
- Tools subset correctly defined
- No dependency on AnnotateState or editor-specific code
