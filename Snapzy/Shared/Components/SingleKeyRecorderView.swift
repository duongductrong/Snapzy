//
//  SingleKeyRecorderView.swift
//  Snapzy
//
//  SwiftUI view for recording single-key shortcuts (no modifiers)
//

import AppKit
import Carbon.HIToolbox
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
      return [AnnotationToolBadge(label: L10n.CaptureKind.screenshot, color: .blue)]
    case .recordingOnly:
      return [AnnotationToolBadge(label: L10n.CaptureKind.recording, color: .orange)]
    case .both:
      return [
        AnnotationToolBadge(label: L10n.CaptureKind.screenshot, color: .blue),
        AnnotationToolBadge(label: L10n.CaptureKind.recording, color: .orange),
      ]
    }
  }
}

/// View for recording single-key shortcuts
struct SingleKeyRecorderView: View {
  let tool: AnnotationToolType
  @Binding var shortcut: Character?
  @Binding var isEnabled: Bool
  let validationIssue: ShortcutValidationIssue?
  let onChanged: (Character?) -> Bool
  let conflictingTool: AnnotationToolType?
  var context: AnnotationToolContext = .both
  var defaultShortcut: Character? = nil

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
      if isEnabled, validationIssue == nil, let conflict = conflictingTool {
        Label(L10n.ShortcutRecorder.usedBy(conflict.displayName), systemImage: "exclamationmark.triangle")
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
          EmptyShortcutCTAView(title: L10n.PreferencesShortcuts.setKey, minWidth: 72)
        }
      }
      .buttonStyle(ShortcutButtonStyle(isRecording: isRecording))
      .shortcutValidationHighlight(issue: validationIssue)
      .disabled(!isEnabled)
      .help(isEnabled ? L10n.ShortcutRecorder.clickToRecord : L10n.ShortcutRecorder.turnOnToEdit)

      ShortcutOptionsMenuButton(
        isEnabled: $isEnabled,
        isDefault: shortcut == defaultShortcut,
        isBusy: isRecording,
        onReset: resetToDefault
      )
    }
    .padding(.vertical, 2)
    .opacity(isEnabled ? 1 : 0.62)
    .onChange(of: isEnabled) { newValue in
      if !newValue {
        stopRecording()
      }
    }
    .onDisappear { stopRecording() }
  }

  private func resetToDefault() {
    if onChanged(defaultShortcut) {
      shortcut = defaultShortcut
    }
  }

  private func startRecording() {
    guard !isRecording, isEnabled else { return }
    isRecording = true
    KeyboardShortcutManager.shared.beginTemporaryShortcutSuppression()
    didSuspendGlobalShortcuts = true

    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Escape cancels
      if event.keyCode == UInt16(kVK_Escape) {
        stopRecording()
        return nil
      }

      // Backspace/Delete clears only the shortcut value. The row toggle is independent.
      if isClearShortcutEvent(event) {
        _ = onChanged(nil)
        stopRecording()
        return nil
      }

      // Get character (lowercase for consistency)
      if let char = event.charactersIgnoringModifiers?.lowercased().first,
         char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol {
        _ = onChanged(char)
        stopRecording()
        return nil
      }

      return nil
    }
  }

  private func isClearShortcutEvent(_ event: NSEvent) -> Bool {
    switch Int(event.keyCode) {
    case kVK_Delete, kVK_ForwardDelete:
      return event.modifierFlags
        .intersection([.command, .control, .option, .shift])
        .isEmpty
    default:
      return false
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
