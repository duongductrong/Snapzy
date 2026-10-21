//
//  ColorPickerResultWindow.swift
//  Snapzy
//
//  The window shown after Pick Color copies a color: the color and its hex, every
//  `ColorPickerFormat` as a one-click (or ⌘1–⌘7) copy row, recent picks, the format a pick
//  copies, and Pick Again. It is a regular titled window — movable, with the system close and
//  minimize buttons, Esc closes it — backed by the system Liquid Glass material on macOS 26
//  and the standard window background before that.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class ColorPickerResultWindowController: NSObject, NSWindowDelegate {
  private static let pointerGap: CGFloat = 18

  private let copyToPasteboard: (String) -> Void
  private let onPickAgain: () -> Void
  private let preferences: ColorPickerPreferences
  private var window: NSWindow?
  private var model: ColorPickerResultModel?

  init(
    copyToPasteboard: @escaping (String) -> Void,
    onPickAgain: @escaping () -> Void,
    preferences: ColorPickerPreferences = ColorPickerPreferences()
  ) {
    self.copyToPasteboard = copyToPasteboard
    self.onPickAgain = onPickAgain
    self.preferences = preferences
    super.init()
  }

  var isVisible: Bool { window?.isVisible ?? false }

  /// Shows `color`, reusing the window when one is already open. `copiedFormat` is what the pick
  /// already put on the clipboard; `screenPoint` (AppKit global coordinates) is where the color
  /// was picked, used to place a newly opened window.
  func show(color: ColorPickerColor, copiedFormat: ColorPickerFormat, near screenPoint: CGPoint) {
    let recentColors = preferences.recordRecent(color)
    let isNewWindow = window == nil
    let model = self.model ?? ColorPickerResultModel(
      color: color,
      copiedFormat: copiedFormat,
      copyOnPickFormat: preferences.copyFormat
    )
    model.color = color
    model.copiedFormat = copiedFormat
    model.recentColors = recentColors
    self.model = model

    let window = self.window ?? makeWindow(model: model)
    self.window = window
    fitContent(of: window, model: model)
    if isNewWindow {
      window.setFrameOrigin(Self.origin(for: window.frame.size, near: screenPoint))
    }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }

    // A regular app while the window is open, so it can be minimized to the Dock and focused
    // like any other window; `windowWillClose` reverts this.
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func close() {
    window?.performClose(nil)
  }

  /// Below-right of the picked point, flipped to the other side of it when that would leave the
  /// display, then kept inside the visible frame.
  static func origin(for size: CGSize, near point: CGPoint, in visibleFrame: CGRect? = nil) -> CGPoint {
    let frame = visibleFrame
      ?? NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame
      ?? NSScreen.main?.visibleFrame
      ?? CGRect(origin: .zero, size: size)
    var origin = CGPoint(x: point.x + pointerGap, y: point.y - pointerGap - size.height)
    if origin.x + size.width > frame.maxX {
      origin.x = point.x - pointerGap - size.width
    }
    if origin.y < frame.minY {
      origin.y = point.y + pointerGap
    }
    origin.x = min(max(origin.x, frame.minX), frame.maxX - size.width)
    origin.y = min(max(origin.y, frame.minY), frame.maxY - size.height)
    return origin
  }

  // MARK: - Actions

  private func copy(_ format: ColorPickerFormat) {
    guard let model else { return }
    copyToPasteboard(format.string(for: model.color))
    model.copiedFormat = format
  }

  /// Brings a recent color back, copied the way a pick would copy it.
  private func select(_ color: ColorPickerColor) {
    guard let model, let window else { return }
    model.color = color
    model.recentColors = preferences.recordRecent(color)
    copy(model.copyOnPickFormat)
    fitContent(of: window, model: model)
  }

  private func setCopyOnPickFormat(_ format: ColorPickerFormat) {
    preferences.copyFormat = format
    model?.copyOnPickFormat = format
  }

  // MARK: - Window

  private func makeWindow(model: ColorPickerResultModel) -> NSWindow {
    let window = ColorPickerResultNSWindow(
      contentRect: .zero,
      styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = L10n.Actions.pickColor
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
    window.appearance = ThemeManager.shared.nsAppearance
    window.delegate = self

    let hostingView = NSHostingView(rootView: makeView(model: model))
    // The window is sized explicitly in `fitContent`; letting the hosting view drive the window
    // size as well loops the constraint pass inside a glass container.
    hostingView.sizingOptions = []
    hostingView.autoresizingMask = [.width, .height]

    if #available(macOS 26.0, *) {
      // The system Liquid Glass material behind the whole window, titlebar included.
      window.isOpaque = false
      window.backgroundColor = .clear
      let glass = NSGlassEffectView()
      glass.cornerRadius = 26
      glass.contentView = hostingView
      window.contentView = glass
    } else {
      window.backgroundColor = .windowBackgroundColor
      window.contentView = hostingView
    }
    return window
  }

  /// Resizes the window to its content, keeping the top edge in place.
  private func fitContent(of window: NSWindow, model: ColorPickerResultModel) {
    let size = NSHostingView(rootView: makeView(model: model)).fittingSize
    let top = window.frame.maxY
    window.setContentSize(size)
    if window.isVisible {
      window.setFrameTopLeftPoint(CGPoint(x: window.frame.minX, y: top))
    }
  }

  private func makeView(model: ColorPickerResultModel) -> ColorPickerResultView {
    ColorPickerResultView(
      model: model,
      onCopy: { [weak self] format in self?.copy(format) },
      onSelectRecent: { [weak self] color in self?.select(color) },
      onChangeCopyOnPick: { [weak self] format in self?.setCopyOnPickFormat(format) },
      onPickAgain: { [weak self] in self?.onPickAgain() }
    )
  }

  // MARK: - NSWindowDelegate

  func windowWillClose(_ notification: Notification) {
    let closingWindow = window
    window = nil
    model = nil
    NSApp.revertActivationPolicyToAccessoryIfNeeded(excluding: closingWindow)
  }
}

/// Esc closes the window, as it does for the system's small utility windows.
private final class ColorPickerResultNSWindow: NSWindow {
  override func cancelOperation(_ sender: Any?) {
    performClose(sender)
  }
}

#if DEBUG
extension ColorPickerResultWindowController {
  var testWindow: NSWindow? { window }
  var testCopiedFormat: ColorPickerFormat? { model?.copiedFormat }
  var testColor: ColorPickerColor? { model?.color }
  var testRecentColors: [ColorPickerColor] { model?.recentColors ?? [] }

  func testCopy(_ format: ColorPickerFormat) {
    copy(format)
  }

  func testSelectRecent(_ color: ColorPickerColor) {
    select(color)
  }

  func testSetCopyOnPickFormat(_ format: ColorPickerFormat) {
    setCopyOnPickFormat(format)
  }

  func testPickAgain() {
    onPickAgain()
  }
}
#endif

// MARK: - Content

@MainActor
final class ColorPickerResultModel: ObservableObject {
  @Published var color: ColorPickerColor
  @Published var copiedFormat: ColorPickerFormat
  @Published var copyOnPickFormat: ColorPickerFormat
  @Published var recentColors: [ColorPickerColor] = []

  init(color: ColorPickerColor, copiedFormat: ColorPickerFormat, copyOnPickFormat: ColorPickerFormat) {
    self.color = color
    self.copiedFormat = copiedFormat
    self.copyOnPickFormat = copyOnPickFormat
  }
}

struct ColorPickerResultView: View {
  @ObservedObject var model: ColorPickerResultModel
  let onCopy: (ColorPickerFormat) -> Void
  let onSelectRecent: (ColorPickerColor) -> Void
  let onChangeCopyOnPick: (ColorPickerFormat) -> Void
  let onPickAgain: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ColorPickerResultHero(color: model.color, copiedFormat: model.copiedFormat)

      VStack(spacing: 2) {
        ForEach(Array(ColorPickerFormat.allCases.enumerated()), id: \.element) { index, format in
          ColorPickerFormatRow(
            format: format,
            value: format.string(for: model.color),
            shortcut: index + 1,
            isCopied: model.copiedFormat == format,
            onCopy: { onCopy(format) }
          )
        }
      }
      .padding(4)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      if model.recentColors.count > 1 {
        recentColors
      }

      footer
    }
    .padding(16)
    // Clears the titlebar, which the content extends under.
    .padding(.top, 22)
    .frame(width: 348, alignment: .leading)
  }

  private var recentColors: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(L10n.ScreenCapture.colorPickerRecent)
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        ForEach(model.recentColors, id: \.hex) { color in
          Button {
            onSelectRecent(color)
          } label: {
            Circle()
              .fill(Color(cgColor: color.cgColor))
              .overlay(Circle().strokeBorder(.separator))
              .padding(color == model.color ? 3 : 0)
              .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: color == model.color ? 2 : 0))
              .frame(width: 24, height: 24)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .help(color.hex)
          .accessibilityLabel(color.hex)
        }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 12) {
      Picker(L10n.ScreenCapture.colorPickerCopyOnPick, selection: Binding(
        get: { model.copyOnPickFormat },
        set: { onChangeCopyOnPick($0) }
      )) {
        ForEach(ColorPickerFormat.allCases) { format in
          Text(verbatim: format.title).tag(format)
        }
      }
      .pickerStyle(.menu)
      .fixedSize()

      Spacer(minLength: 0)

      pickAgainButton
    }
  }

  @ViewBuilder
  private var pickAgainButton: some View {
    let button = Button(action: onPickAgain) {
      Label(L10n.ScreenCapture.colorPickerPickAgain, systemImage: "eyedropper")
        .padding(.horizontal, 4)
    }
    .controlSize(.large)
    .keyboardShortcut(.defaultAction)

    if #available(macOS 26.0, *) {
      button.buttonStyle(.glassProminent)
    } else {
      button.buttonStyle(.borderedProminent)
    }
  }
}

/// The picked color itself, with its hex written on it.
private struct ColorPickerResultHero: View {
  let color: ColorPickerColor
  let copiedFormat: ColorPickerFormat

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(cgColor: color.cgColor))
        .overlay(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.separator)
        )
        .overlay(alignment: .bottomLeading) {
          Text(verbatim: color.hex)
            .font(.title2.monospaced().weight(.semibold))
            .foregroundStyle(color.isLight ? Color.black.opacity(0.82) : Color.white)
            .textSelection(.enabled)
            .padding(12)
        }
        .frame(height: 84)

      Label(L10n.ScreenCapture.colorPickerCopied(copiedFormat.title), systemImage: "checkmark.circle.fill")
        .font(.callout)
        .foregroundStyle(.secondary)
        .symbolRenderingMode(.multicolor)
    }
  }
}

/// One notation; the whole row copies it.
private struct ColorPickerFormatRow: View {
  let format: ColorPickerFormat
  let value: String
  let shortcut: Int
  let isCopied: Bool
  let onCopy: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onCopy) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(verbatim: format.title)
          .foregroundStyle(.secondary)
          .frame(width: 58, alignment: .leading)
        Text(verbatim: value)
          .monospaced()
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        trailing
      }
      .font(.callout)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
      )
      .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .keyboardShortcut(KeyEquivalent(Character("\(shortcut)")), modifiers: .command)
    .onHover { isHovering = $0 }
    .help("\(L10n.Common.copy) \(format.title) (⌘\(shortcut))")
    .accessibilityLabel("\(L10n.Common.copy) \(format.title) \(value)")
  }

  @ViewBuilder
  private var trailing: some View {
    if isCopied {
      Label(L10n.ScreenCapture.magnifierColorCopiedFeedback, systemImage: "checkmark")
        .font(.caption.weight(.medium))
        .foregroundStyle(.green)
        .labelStyle(.titleAndIcon)
        .fixedSize()
    } else {
      Text(verbatim: "⌘\(shortcut)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
        .opacity(isHovering ? 0 : 1)
        .overlay {
          Image(systemName: "doc.on.doc")
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
        }
        .fixedSize()
    }
  }
}
