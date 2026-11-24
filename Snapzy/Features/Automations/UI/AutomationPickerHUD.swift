//
//  AutomationPickerHUD.swift
//  Snapzy
//
//  The run-time picker (milestone 5) shared by the Ask step, Finder's "Run
//  Snapzy Automation…" service and files dropped on the menu bar icon. A
//  non-activating panel near the cursor: it takes the keyboard without
//  bringing Snapzy (an accessory app) forward. ↑/↓ + Return, 1–9 to pick,
//  Esc or a click elsewhere cancels. More than nine rows add a search field.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Model

/// Selection state and key handling, kept free of AppKit so it can be tested.
@MainActor
final class AutomationPickerModel: ObservableObject {
  /// Rows beyond this get a search field; number keys cover the first nine.
  static let searchThreshold = 9

  enum Key: Equatable {
    case up
    case down
    case returnKey
    case escape
    case digit(Int)
  }

  enum Outcome: Equatable {
    case picked(AutomationPickerChoice)
    case cancelled
  }

  enum KeyResult: Equatable {
    /// Not for the picker (e.g. typing into the search field).
    case ignored
    /// Moved the highlight, or a key with nothing to pick.
    case consumed
    case finished(Outcome)
  }

  let title: String
  let choices: [AutomationPickerChoice]
  @Published var query = "" {
    didSet { highlighted = filtered.isEmpty ? nil : 0 }
  }

  @Published var highlighted: Int?

  init(title: String, choices: [AutomationPickerChoice]) {
    self.title = title
    self.choices = choices
    highlighted = choices.isEmpty ? nil : 0
  }

  var showsSearch: Bool { choices.count > Self.searchThreshold }

  var filtered: [AutomationPickerChoice] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return choices }
    return choices.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
  }

  func handle(_ key: Key) -> KeyResult {
    let rows = filtered
    switch key {
    case .up:
      if !rows.isEmpty { highlighted = max(0, (highlighted ?? 0) - 1) }
      return .consumed
    case .down:
      if !rows.isEmpty { highlighted = min(rows.count - 1, (highlighted ?? -1) + 1) }
      return .consumed
    case .returnKey:
      guard let index = highlighted, rows.indices.contains(index) else { return .consumed }
      return .finished(.picked(rows[index]))
    case .escape:
      return .finished(.cancelled)
    case .digit(let number):
      // While searching, digits are part of the query.
      guard query.isEmpty else { return .ignored }
      let index = number - 1
      guard index < Self.searchThreshold, rows.indices.contains(index) else { return .consumed }
      return .finished(.picked(rows[index]))
    }
  }
}

// MARK: - Panel controller

@MainActor
final class AutomationPickerHUD {
  static let shared = AutomationPickerHUD()

  private static let width: CGFloat = 300

  private var panel: PickerPanel?
  private var continuation: CheckedContinuation<AutomationPickerChoice?, Never>?
  private var keyMonitor: Any?
  private var clickMonitor: Any?
  private var model: AutomationPickerModel?

  /// Shows the picker and returns the chosen row, or `nil` when cancelled.
  /// A second call while one is open cancels the first.
  func present(title: String, thumbnail: URL?, choices: [AutomationPickerChoice]) async -> AutomationPickerChoice? {
    finish(nil)
    guard !choices.isEmpty else { return nil }
    // Cancelling the run (HUD Cancel, CLI caller gone) closes the picker.
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        show(title: title, thumbnail: thumbnail, choices: choices)
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(nil) }
    }
  }

  private func show(title: String, thumbnail: URL?, choices: [AutomationPickerChoice]) {
    let model = AutomationPickerModel(title: title, choices: choices)
    self.model = model
    let image = thumbnail.flatMap { NSImage(contentsOf: $0) }
    let view = AutomationPickerView(model: model, thumbnail: image) { [weak self] outcome in
      self?.resolve(outcome)
    }
    let hosting = NSHostingView(rootView: view)
    let size = hosting.fittingSize

    let panel = PickerPanel(
      contentRect: NSRect(x: 0, y: 0, width: Self.width, height: size.height),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    // Above full-screen apps and the capture overlay's leftovers.
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.becomesKeyOnlyIfNeeded = false
    panel.contentView = hosting
    panel.onResignKey = { [weak self] in self?.finish(nil) }
    panel.setFrame(Self.frame(size: NSSize(width: Self.width, height: size.height)), display: true)
    self.panel = panel
    panel.makeKeyAndOrderFront(nil)
    installMonitors()
    NSAccessibility.post(element: panel, notification: .focusedWindowChanged)
  }

  /// Near the cursor, kept on the cursor's screen.
  private static func frame(size: NSSize) -> NSRect {
    let cursor = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    var origin = NSPoint(x: cursor.x + 12, y: cursor.y - size.height - 12)
    origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
    origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
    return NSRect(origin: origin, size: size)
  }

  private func installMonitors() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let model = self.model, self.panel?.isKeyWindow == true else { return event }
      guard let key = Self.key(for: event) else { return event }
      switch model.handle(key) {
      case .finished(let outcome):
        self.resolve(outcome)
        return nil
      case .consumed:
        return nil
      case .ignored:
        return event
      }
    }
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      // A click in another app (global monitors only see those) cancels.
      Task { @MainActor in self?.finish(nil) }
    }
  }

  private static func key(for event: NSEvent) -> AutomationPickerModel.Key? {
    switch event.keyCode {
    case 126: return .up
    case 125: return .down
    case 36, 76: return .returnKey
    case 53: return .escape
    default:
      guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
            let characters = event.charactersIgnoringModifiers,
            characters.count == 1,
            let digit = Int(characters),
            (1...9).contains(digit)
      else { return nil }
      return .digit(digit)
    }
  }

  private func resolve(_ outcome: AutomationPickerModel.Outcome) {
    switch outcome {
    case .picked(let choice): finish(choice)
    case .cancelled: finish(nil)
    }
  }

  private func finish(_ choice: AutomationPickerChoice?) {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    keyMonitor = nil
    clickMonitor = nil
    if let panel {
      panel.onResignKey = nil
      panel.orderOut(nil)
    }
    panel = nil
    model = nil
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(returning: choice)
  }

  /// Borderless panels can't become key by default; this one must (keyboard).
  private final class PickerPanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
      super.resignKey()
      onResignKey?()
    }
  }
}

// MARK: - View

private struct AutomationPickerView: View {
  @ObservedObject var model: AutomationPickerModel
  let thumbnail: NSImage?
  let onOutcome: (AutomationPickerModel.Outcome) -> Void
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        if let thumbnail {
          Image(nsImage: thumbnail)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
        }
        Text(model.title)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)

      if model.showsSearch {
        TextField(L10n.Automations.pickerSearch, text: $model.query)
          .textFieldStyle(.roundedBorder)
          .focused($searchFocused)
          .onAppear { searchFocused = true }
      }

      VStack(spacing: 2) {
        let rows = model.filtered
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, choice in
          row(choice, index: index)
        }
        if rows.isEmpty {
          Text(L10n.Automations.pickerNoMatches)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
      }

      Text(L10n.Automations.pickerHint)
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 6)
    }
    .padding(10)
    .frame(width: 300)
    .background(.regularMaterial, in: Radius.rect(Radius.card))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(model.title)
  }

  private func row(_ choice: AutomationPickerChoice, index: Int) -> some View {
    let isHighlighted = model.highlighted == index
    return Button {
      onOutcome(.picked(choice))
    } label: {
      HStack(spacing: 8) {
        Image(systemName: choice.symbol)
          .frame(width: 18)
          .foregroundStyle(isHighlighted ? Color.white : .secondary)
        Text(choice.title)
          .lineLimit(1)
          .foregroundStyle(isHighlighted ? Color.white : .primary)
        Spacer(minLength: 4)
        if index < AutomationPickerModel.searchThreshold, model.query.isEmpty {
          Text("\(index + 1)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(isHighlighted ? Color.white.opacity(0.85) : .secondary)
            .frame(width: 18, height: 16)
            .background(
              RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(isHighlighted ? Color.white.opacity(0.5) : Color.secondary.opacity(0.4))
            )
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isHighlighted ? Color.accentColor : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      if hovering { model.highlighted = index }
    }
    .accessibilityLabel(choice.title)
    .accessibilityHint(index < AutomationPickerModel.searchThreshold ? L10n.Automations.pickerNumberHint(index + 1) : "")
  }
}
