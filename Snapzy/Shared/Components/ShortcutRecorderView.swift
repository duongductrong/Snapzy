//
//  ShortcutRecorderView.swift
//  Snapzy
//
//  SwiftUI view for recording custom keyboard shortcuts
//

import AppKit
import SwiftUI

/// A view that allows users to record custom keyboard shortcuts
struct ShortcutRecorderView: View {
  let label: String
  let icon: String
  let description: String
  @Binding var shortcut: ShortcutConfig
  let onShortcutChanged: (ShortcutConfig) -> Void

  @State private var isRecording = false
  @State private var eventMonitor: Any?

  init(
    label: String,
    icon: String = "command",
    description: String = "",
    shortcut: Binding<ShortcutConfig>,
    onShortcutChanged: @escaping (ShortcutConfig) -> Void
  ) {
    self.label = label
    self.icon = icon
    self.description = description
    self._shortcut = shortcut
    self.onShortcutChanged = onShortcutChanged
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.secondary)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .fontWeight(.medium)
        if !description.isEmpty {
          Text(description)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      Spacer()

      Button {
        startRecording()
      } label: {
        Text(isRecording ? "Press keys..." : shortcut.displayString)
          .font(.system(.body, design: .monospaced))
          .frame(minWidth: 100)
      }
      .buttonStyle(ShortcutButtonStyle(isRecording: isRecording))
    }
    .padding(.vertical, 4)
    .onDisappear {
      stopRecording()
    }
  }

  private func startRecording() {
    guard !isRecording else { return }
    isRecording = true

    // Add local event monitor for key events
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Escape cancels recording
      if event.keyCode == 53 {
        stopRecording()
        return nil
      }

      // Try to create shortcut from event
      if let newShortcut = ShortcutConfig(from: event) {
        shortcut = newShortcut
        onShortcutChanged(newShortcut)
        stopRecording()
        return nil
      }

      // Invalid shortcut (no modifier), keep recording
      return nil
    }
  }

  private func stopRecording() {
    isRecording = false
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
  }
}

/// Custom button style for shortcut recorder
struct ShortcutButtonStyle: ButtonStyle {
  let isRecording: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isRecording ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
      )
      .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
      .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
  }
}
