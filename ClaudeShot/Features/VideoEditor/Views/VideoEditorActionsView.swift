//
//  VideoEditorActionsView.swift
//  ClaudeShot
//
//  Footer action buttons for video editor
//

import SwiftUI

/// Footer actions for video editor with save, save as, and cancel buttons
struct VideoEditorActionsView: View {
  @ObservedObject var state: VideoEditorState
  let onSave: () -> Void
  let onSaveAs: () -> Void
  let onCancel: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      // Hint text
      if state.hasUnsavedChanges {
        HStack(spacing: 6) {
          Image(systemName: "info.circle")
            .font(.system(size: 12))
          Text("Trim adjusted. Save to apply changes.")
            .font(.system(size: 12))
        }
        .foregroundColor(.secondary)
      } else {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle")
            .font(.system(size: 12))
          Text("No changes")
            .font(.system(size: 12))
        }
        .foregroundColor(.secondary.opacity(0.6))
      }

      Spacer()

      // Cancel button
      Button(action: onCancel) {
        Text("Cancel")
          .font(.system(size: 13))
          .frame(minWidth: 70)
      }
      .buttonStyle(.bordered)
      .keyboardShortcut(.escape, modifiers: [])

      // Save As Copy button
      Button(action: onSaveAs) {
        Text("Save as Copy")
          .font(.system(size: 13))
          .frame(minWidth: 90)
      }
      .buttonStyle(.bordered)
      .keyboardShortcut("s", modifiers: [.command, .shift])
      .disabled(!state.hasUnsavedChanges)

      // Save button (primary)
      Button(action: onSave) {
        Text("Save")
          .font(.system(size: 13, weight: .medium))
          .frame(minWidth: 70)
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut("s", modifiers: [.command])
      .disabled(!state.hasUnsavedChanges)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
  }
}
