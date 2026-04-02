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
  let isEnabled: Binding<Bool>?
  let validationIssue: ShortcutValidationIssue?
  let onShortcutChanged: (ShortcutConfig) -> Bool

  @State private var isRecording = false
  @State private var eventMonitor: Any?
  @State private var didSuspendGlobalShortcuts = false

  init(
    label: String,
    icon: String = "command",
    description: String = "",
    shortcut: Binding<ShortcutConfig>,
    isEnabled: Binding<Bool>? = nil,
    validationIssue: ShortcutValidationIssue? = nil,
    onShortcutChanged: @escaping (ShortcutConfig) -> Bool
  ) {
    self.label = label
    self.icon = icon
    self.description = description
    self._shortcut = shortcut
    self.isEnabled = isEnabled
    self.validationIssue = validationIssue
    self.onShortcutChanged = onShortcutChanged
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
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
          if isRecording {
            Text("Press keys...")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.accentColor)
              .frame(minWidth: 100)
          } else {
            KeyCapGroupView(parts: shortcut.displayParts)
          }
        }
        .buttonStyle(ShortcutKeycapButtonStyle(isRecording: isRecording))
        .disabled(!isInteractionEnabled)
        .help(isInteractionEnabled ? "Click to record a shortcut." : "Turn this shortcut on to edit it.")

        if let toggleBinding {
          HStack(spacing: 6) {
            Text(toggleBinding.wrappedValue ? "On" : "Off")
              .font(.caption)
              .foregroundColor(.secondary)

            Toggle("", isOn: toggleBinding)
              .labelsHidden()
          }
        }
      }

      if let validationIssue {
        ShortcutValidationMessageView(issue: validationIssue, leadingInset: 40)
      }
    }
    .padding(.vertical, 4)
    .opacity(rowOpacity)
    .onChange(of: isInteractionEnabled) { newValue in
      if !newValue {
        stopRecording()
      }
    }
    .onDisappear {
      stopRecording()
    }
  }

  private var toggleBinding: Binding<Bool>? {
    guard let isEnabled else { return nil }
    return Binding(
      get: { isEnabled.wrappedValue },
      set: { isEnabled.wrappedValue = $0 }
    )
  }

  private var rowOpacity: Double {
    guard let isEnabled else { return 1 }
    return isEnabled.wrappedValue ? 1 : 0.62
  }

  private var isInteractionEnabled: Bool {
    isEnabled?.wrappedValue ?? true
  }

  private func startRecording() {
    guard !isRecording, isInteractionEnabled else { return }
    isRecording = true
    KeyboardShortcutManager.shared.beginTemporaryShortcutSuppression()
    didSuspendGlobalShortcuts = true

    // Add local event monitor for key events
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Escape cancels recording
      if event.keyCode == 53 {
        stopRecording()
        return nil
      }

      // Try to create shortcut from event
      if let newShortcut = ShortcutConfig(from: event) {
        _ = onShortcutChanged(newShortcut)
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
    if didSuspendGlobalShortcuts {
      KeyboardShortcutManager.shared.endTemporaryShortcutSuppression()
      didSuspendGlobalShortcuts = false
    }
  }
}

/// Transparent button style for keycap-based shortcut recorder; keycaps provide visual affordance
struct ShortcutKeycapButtonStyle: ButtonStyle {
  let isRecording: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(isRecording ? Color.accentColor.opacity(0.08) : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(
            isRecording ? Color.accentColor.opacity(0.5) : Color.clear,
            lineWidth: 1
          )
      )
      .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
      .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
  }
}

struct ShortcutValidationMessageView: View {
  let issue: ShortcutValidationIssue
  var leadingInset: CGFloat = 0

  var body: some View {
    HStack(spacing: 6) {
      Spacer()
        .frame(width: leadingInset)

      Image(systemName: iconName)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(messageColor)

      Text(issue.message)
        .font(.caption)
        .foregroundColor(messageColor)

      Spacer(minLength: 0)
    }
  }

  private var messageColor: Color {
    switch issue.severity {
    case .warning:
      return .orange
    case .error:
      return .red
    }
  }

  private var iconName: String {
    switch issue.severity {
    case .warning:
      return "exclamationmark.triangle.fill"
    case .error:
      return "xmark.octagon.fill"
    }
  }
}

/// Legacy button style kept for backward compatibility (e.g. if referenced elsewhere)
struct ShortcutButtonStyle: ButtonStyle {
  let isRecording: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(isRecording ? Color.accentColor.opacity(0.08) : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(
            isRecording ? Color.accentColor.opacity(0.5) : Color.clear,
            lineWidth: 1
          )
      )
      .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
      .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
  }
}
