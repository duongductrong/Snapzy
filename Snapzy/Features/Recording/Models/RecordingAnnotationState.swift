//
//  RecordingAnnotationState.swift
//  Snapzy
//
//  Lightweight state for annotations during screen recording
//  Supports per-tool auto-clear (time-based and count-based)
//

import Combine
import SwiftUI

// MARK: - Auto-Clear Mode

enum AnnotationClearMode: Equatable, Hashable {
  case persist
  case timeBased(seconds: Double)
  case countBased(count: Int)

  var displayName: String {
    switch self {
    case .persist: return "Persist"
    case .timeBased(let s): return "\(Int(s))s"
    case .countBased(let c): return "Last \(c)"
    }
  }
}

// MARK: - Annotation Entry (wraps AnnotationItem with lifecycle metadata)

struct RecordingAnnotationEntry: Identifiable, Equatable {
  let id: UUID
  var item: AnnotationItem
  let createdAt: Date
  let createdByTool: AnnotationToolType
  var opacity: Double = 1.0

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id && lhs.opacity == rhs.opacity
  }
}

// MARK: - Recording Annotation State

@MainActor
final class RecordingAnnotationState: ObservableObject {
  @Published var annotations: [RecordingAnnotationEntry] = []
  @Published var selectedTool: AnnotationToolType = .selection
  @Published var selectedAnnotationId: UUID?
  @Published var strokeColor: Color = .red
  @Published var strokeWidth: CGFloat = 3
  @Published var isAnnotationEnabled: Bool = false
  @Published var toolClearModes: [AnnotationToolType: AnnotationClearMode] = [:]
  @Published var isShortcutModeActive: Bool = false

  private var cleanupTimer: Timer?

  static let availableTools: [AnnotationToolType] = [
    .selection, .rectangle, .oval, .arrow, .line, .pencil, .highlighter,
  ]

  static let clearModePresets: [AnnotationClearMode] = [
    .persist,
    .timeBased(seconds: 3),
    .timeBased(seconds: 5),
    .timeBased(seconds: 10),
    .countBased(count: 3),
    .countBased(count: 5),
    .countBased(count: 10),
  ]

  func clearMode(for tool: AnnotationToolType) -> AnnotationClearMode {
    toolClearModes[tool] ?? .persist
  }

  // MARK: - Annotation Management

  func appendAnnotation(_ item: AnnotationItem, tool: AnnotationToolType) {
    let entry = RecordingAnnotationEntry(
      id: item.id,
      item: item,
      createdAt: Date(),
      createdByTool: tool
    )
    annotations.append(entry)
    enforceCountLimit(for: tool)
  }

  func clearAll() {
    annotations.removeAll()
    selectedAnnotationId = nil
  }

  func deleteSelected() {
    guard let selectedId = selectedAnnotationId else { return }
    annotations.removeAll { $0.id == selectedId }
    selectedAnnotationId = nil
  }

  // MARK: - Cleanup Timer

  func startCleanupTimer() {
    cleanupTimer?.invalidate()
    cleanupTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.removeExpired()
      }
    }
  }

  func stopCleanupTimer() {
    cleanupTimer?.invalidate()
    cleanupTimer = nil
  }

  // MARK: - Private Cleanup

  private func removeExpired() {
    let now = Date()
    var changed = false

    annotations = annotations.compactMap { entry in
      let mode = clearMode(for: entry.createdByTool)
      guard case .timeBased(let seconds) = mode else { return entry }

      let elapsed = now.timeIntervalSince(entry.createdAt)
      let fadeStart = seconds - 0.5  // Start fading 0.5s before removal

      if elapsed >= seconds {
        changed = true
        return nil  // Remove
      } else if elapsed >= fadeStart {
        var fading = entry
        fading.opacity = max(0, 1.0 - (elapsed - fadeStart) / 0.5)
        changed = true
        return fading
      }
      return entry
    }

    if changed {
      objectWillChange.send()
    }
  }

  private func enforceCountLimit(for tool: AnnotationToolType) {
    guard case .countBased(let maxCount) = clearMode(for: tool) else { return }

    let toolEntries = annotations.filter { $0.createdByTool == tool }
    guard toolEntries.count > maxCount else { return }

    let excess = toolEntries.count - maxCount
    let idsToRemove = Set(toolEntries.prefix(excess).map(\.id))
    annotations.removeAll { idsToRemove.contains($0.id) }
  }
}
