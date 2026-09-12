//
//  ShortcutRecorderView.swift
//  Snapzy
//
//  SwiftUI view for recording custom keyboard shortcuts
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A view that allows users to record custom keyboard shortcuts
struct ShortcutRecorderView: View {
  let label: String
  let icon: String
  let description: String
  let footnote: String?
  @Binding var shortcut: ShortcutConfig?
  let defaultShortcut: ShortcutConfig?
  let isEnabled: Binding<Bool>?
  let validationIssue: ShortcutValidationIssue?
  let onShortcutChanged: (ShortcutConfig?) -> Bool

  @State private var isRecording = false
  @State private var eventMonitor: Any?
  @State private var didSuspendGlobalShortcuts = false

  init(
    label: String,
    icon: String = "command",
    description: String = "",
    footnote: String? = nil,
    shortcut: Binding<ShortcutConfig?>,
    defaultShortcut: ShortcutConfig? = nil,
    isEnabled: Binding<Bool>? = nil,
    validationIssue: ShortcutValidationIssue? = nil,
    onShortcutChanged: @escaping (ShortcutConfig?) -> Bool
  ) {
    self.label = label
    self.icon = icon
    self.description = description
    self.footnote = footnote
    self._shortcut = shortcut
    self.defaultShortcut = defaultShortcut
    self.isEnabled = isEnabled
    self.validationIssue = validationIssue
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
        if let footnote {
          Text(footnote)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }

      Spacer()

      Button {
        startRecording()
      } label: {
        if isRecording {
          Text(L10n.ShortcutRecorder.pressKeys)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.accentColor)
            .frame(minWidth: 100)
        } else if let shortcut {
          KeyCapGroupView(parts: shortcut.displayParts)
        } else {
          EmptyShortcutCTAView(title: L10n.PreferencesShortcuts.setShortcut)
        }
      }
      .buttonStyle(ShortcutKeycapButtonStyle(isRecording: isRecording))
      .shortcutValidationHighlight(issue: validationIssue)
      .disabled(!isInteractionEnabled)
      .help(isInteractionEnabled ? L10n.ShortcutRecorder.clickToRecord : L10n.ShortcutRecorder.turnOnToEdit)

      ShortcutResetButton(
        isDisabled: !isInteractionEnabled || isRecording || shortcut == defaultShortcut,
        action: resetToDefault
      )

      if let toggleBinding {
        HStack(spacing: 6) {
          Text(toggleBinding.wrappedValue ? L10n.Common.on : L10n.Common.off)
            .font(.caption)
            .foregroundColor(.secondary)

          Toggle("", isOn: toggleBinding)
            .labelsHidden()
        }
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

  private func resetToDefault() {
    if onShortcutChanged(defaultShortcut) {
      shortcut = defaultShortcut
    }
  }

  private func startRecording() {
    guard !isRecording, isInteractionEnabled else { return }
    isRecording = true
    KeyboardShortcutManager.shared.beginTemporaryShortcutSuppression()
    didSuspendGlobalShortcuts = true

    // Add local event monitor for key events
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Escape cancels recording
      if event.keyCode == UInt16(kVK_Escape) {
        stopRecording()
        return nil
      }

      // Backspace/Delete clears only the shortcut value. The row toggle is independent.
      if isClearShortcutEvent(event) {
        _ = onShortcutChanged(nil)
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

struct EmptyShortcutCTAView: View {
  let title: String
  var minWidth: CGFloat = 104

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "return")
        .font(.system(size: 11, weight: .semibold))
      Text(title)
        .font(.system(size: 12, weight: .medium))
    }
    .foregroundColor(.accentColor)
    .frame(minWidth: minWidth)
  }
}

struct ShortcutResetButton: View {
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "arrow.counterclockwise")
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 18, height: 18)
        .foregroundColor(.secondary)
    }
    .buttonStyle(.borderless)
    .disabled(isDisabled)
    .help(L10n.Common.resetToDefault)
    .accessibilityLabel(L10n.Common.resetToDefault)
  }
}

/// Geometry shared by the recorder field, its validation highlight and the legacy button style.
/// All three draw the same rectangle on top of each other, so they must agree on the radius.
enum ShortcutRecorderMetrics {
  /// A `KeyCapView` is 22pt tall and the styles add 4pt of vertical padding either side.
  static let fieldHeight: CGFloat = 30
  static var fieldRadius: CGFloat { Radius.control(forHeight: fieldHeight) }
}

/// Transparent button style for keycap-based shortcut recorder; keycaps provide visual affordance
struct ShortcutKeycapButtonStyle: ButtonStyle {
  let isRecording: Bool
  var horizontalPadding: CGFloat = 6
  var verticalPadding: CGFloat = 4

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .background(
        Radius.rect(ShortcutRecorderMetrics.fieldRadius)
          .fill(isRecording ? Color.accentColor.opacity(0.08) : Color.clear)
      )
      .overlay(
        Radius.rect(ShortcutRecorderMetrics.fieldRadius)
          .strokeBorder(
            isRecording ? Color.accentColor.opacity(0.5) : Color.clear,
            lineWidth: 1
          )
      )
      .contentShape(Radius.rect(ShortcutRecorderMetrics.fieldRadius))
      .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
      .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
  }
}

// MARK: - Validation Highlight + Popover

/// Lightweight coordinator ensuring only one validation popover is visible at a time.
/// Uses a closure callback to dismiss the previous popover — no Combine import needed.
@MainActor
enum ShortcutValidationPopoverCoordinator {
  private static var activeDismiss: (() -> Void)?
  private static var activeID: String?

  static func show(id: String, dismiss: @escaping () -> Void) {
    // Dismiss previous if different
    if activeID != id {
      activeDismiss?()
    }
    activeID = id
    activeDismiss = dismiss
  }

  static func clear(id: String) {
    guard activeID == id else { return }
    activeID = nil
    activeDismiss = nil
  }
}

/// Popover content for validation messages — styled for macOS popover chrome.
private struct ShortcutValidationPopoverContent: View {
  let issue: ShortcutValidationIssue

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: iconName)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(accentColor)

      Text(issue.message)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.primary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(minWidth: 160, maxWidth: 260)
  }

  private var accentColor: Color {
    issue.severity == .error ? .red : .orange
  }

  private var iconName: String {
    issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
  }
}

/// ViewModifier: red/orange pill highlight on keycap + macOS popover tooltip.
struct ShortcutValidationHighlightModifier: ViewModifier {
  let issue: ShortcutValidationIssue?

  @State private var showPopover = false
  @State private var dismissTask: DispatchWorkItem?
  @State private var instanceID = UUID().uuidString

  func body(content: Content) -> some View {
    content
      .background(
        Radius.rect(ShortcutRecorderMetrics.fieldRadius)
          .fill(pillFill)
          .animation(.easeOut(duration: 0.2), value: issue)
      )
      .overlay(
        Radius.rect(ShortcutRecorderMetrics.fieldRadius)
          .strokeBorder(pillBorder, lineWidth: 1)
          .animation(.easeOut(duration: 0.2), value: issue)
      )
      .popover(
        isPresented: $showPopover,
        attachmentAnchor: .rect(.bounds),
        arrowEdge: .bottom
      ) {
        if let issue {
          ShortcutValidationPopoverContent(issue: issue)
        }
      }
      .onChange(of: issue) { newIssue in
        dismissTask?.cancel()
        if newIssue != nil {
          // Dismiss any other active popover first
          ShortcutValidationPopoverCoordinator.show(id: instanceID) { [self] in
            dismissTask?.cancel()
            showPopover = false
          }
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showPopover = true
          }
          let task = DispatchWorkItem { [self] in
            showPopover = false
            ShortcutValidationPopoverCoordinator.clear(id: instanceID)
          }
          dismissTask = task
          DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
        } else {
          showPopover = false
          ShortcutValidationPopoverCoordinator.clear(id: instanceID)
        }
      }
      .onChange(of: showPopover) { isShowing in
        if !isShowing {
          ShortcutValidationPopoverCoordinator.clear(id: instanceID)
        }
      }
  }

  private var pillFill: Color {
    guard let issue else { return .clear }
    return issue.severity == .error
      ? Color.red.opacity(0.12)
      : Color.orange.opacity(0.12)
  }

  private var pillBorder: Color {
    guard let issue else { return .clear }
    return issue.severity == .error
      ? Color.red.opacity(0.35)
      : Color.orange.opacity(0.35)
  }
}

extension View {
  func shortcutValidationHighlight(issue: ShortcutValidationIssue?) -> some View {
    modifier(ShortcutValidationHighlightModifier(issue: issue))
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
        Radius.rect(ShortcutRecorderMetrics.fieldRadius)
          .fill(isRecording ? Color.accentColor.opacity(0.08) : Color.clear)
      )
      .overlay(
        Radius.rect(ShortcutRecorderMetrics.fieldRadius)
          .strokeBorder(
            isRecording ? Color.accentColor.opacity(0.5) : Color.clear,
            lineWidth: 1
          )
      )
      .contentShape(Radius.rect(ShortcutRecorderMetrics.fieldRadius))
      .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
      .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
  }
}
