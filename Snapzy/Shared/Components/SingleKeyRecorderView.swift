//
//  SingleKeyRecorderView.swift
//  Snapzy
//
//  SwiftUI view for recording single-key shortcuts (no modifiers)
//

import AppKit
import SwiftUI

/// A single context badge for annotation tool availability
struct AnnotationToolBadge: Hashable {
  let label: String
  let color: Color

  func hash(into hasher: inout Hasher) { hasher.combine(label) }
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.label == rhs.label }
}

/// Context where an annotation tool is available
enum AnnotationToolContext {
  case screenshotOnly
  case recordingOnly
  case both

  var badges: [AnnotationToolBadge] {
    switch self {
    case .screenshotOnly:
      return [AnnotationToolBadge(label: "Screenshot", color: .blue)]
    case .recordingOnly:
      return [AnnotationToolBadge(label: "Recording", color: .orange)]
    case .both:
      return [
        AnnotationToolBadge(label: "Screenshot", color: .blue),
        AnnotationToolBadge(label: "Recording", color: .orange),
      ]
    }
  }
}

/// View for recording single-key shortcuts
struct SingleKeyRecorderView: View {
  let tool: AnnotationToolType
  @Binding var shortcut: Character?
  @Binding var isEnabled: Bool
  let onChanged: (Character?) -> Void
  let conflictingTool: AnnotationToolType?
  var context: AnnotationToolContext = .both

  @State private var isRecording = false
  @State private var eventMonitor: Any?
  @State private var didSuspendGlobalShortcuts = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: tool.icon)
        .font(.title3)
        .foregroundColor(.secondary)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 4) {
        Text(tool.displayName)
        HStack(spacing: 4) {
          ForEach(context.badges, id: \.label) { badge in
            Text(badge.label)
              .font(.system(size: 9, weight: .medium))
              .foregroundColor(badge.color)
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(
                Capsule().fill(badge.color.opacity(0.15))
              )
          }
        }
      }
      .frame(minWidth: 100, alignment: .leading)

      Spacer()

      // Conflict warning
      if isEnabled, let conflict = conflictingTool {
        Label("Used by \(conflict.displayName)", systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundColor(.orange)
      }

      Button {
        startRecording()
      } label: {
        if isRecording {
          Text("...")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.accentColor)
            .frame(minWidth: 40)
        } else if let key = shortcut {
          KeyCapView(symbol: String(key).uppercased())
        } else {
          Text("–")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.secondary)
            .frame(minWidth: 40)
        }
      }
      .buttonStyle(ShortcutButtonStyle(isRecording: isRecording))

      HStack(spacing: 6) {
        Text(isEnabled ? "On" : "Off")
          .font(.caption)
          .foregroundColor(.secondary)

        Toggle("", isOn: $isEnabled)
          .labelsHidden()
      }
    }
    .padding(.vertical, 2)
    .opacity(isEnabled ? 1 : 0.62)
    .onDisappear { stopRecording() }
  }

  private func startRecording() {
    guard !isRecording else { return }
    isRecording = true
    KeyboardShortcutManager.shared.beginTemporaryShortcutSuppression()
    didSuspendGlobalShortcuts = true

    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Escape cancels
      if event.keyCode == 53 {
        stopRecording()
        return nil
      }

      // Delete/Backspace turns the shortcut off without discarding the key
      if event.keyCode == 51 || event.keyCode == 117 {
        isEnabled = false
        stopRecording()
        return nil
      }

      // Get character (lowercase for consistency)
      if let char = event.charactersIgnoringModifiers?.lowercased().first,
         char.isLetter {
        shortcut = char
        onChanged(char)
        stopRecording()
        return nil
      }

      return nil
    }
  }

  private func stopRecording() {
    isRecording = false
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
    if didSuspendGlobalShortcuts {
      KeyboardShortcutManager.shared.endTemporaryShortcutSuppression()
      didSuspendGlobalShortcuts = false
    }
  }
}
