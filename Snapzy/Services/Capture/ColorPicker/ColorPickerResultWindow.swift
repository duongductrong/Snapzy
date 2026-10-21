//
//  ColorPickerResultWindow.swift
//  Snapzy
//
//  The window shown after Pick Color copies a color: a swatch, the value in every
//  `ColorPickerFormat` with one-click copy, and Pick Again. It is a regular titled window —
//  movable, with the system close and minimize buttons — backed by the system Liquid Glass
//  material on macOS 26 and the standard window background before that.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class ColorPickerResultWindowController: NSObject, NSWindowDelegate {
  private static let pointerGap: CGFloat = 18

  private let copyToPasteboard: (String) -> Void
  private let onPickAgain: () -> Void
  private var window: NSWindow?
  private var hostingView: NSHostingView<ColorPickerResultView>?
  private var model: ColorPickerResultModel?

  init(copyToPasteboard: @escaping (String) -> Void, onPickAgain: @escaping () -> Void) {
    self.copyToPasteboard = copyToPasteboard
    self.onPickAgain = onPickAgain
    super.init()
  }

  var isVisible: Bool { window?.isVisible ?? false }

  /// Shows `color`, reusing the window when one is already open. `copiedFormat` is what the pick
  /// already put on the clipboard; `screenPoint` (AppKit global coordinates) is where the color
  /// was picked, used to place a newly opened window.
  func show(color: ColorPickerColor, copiedFormat: ColorPickerFormat, near screenPoint: CGPoint) {
    let isNewWindow = window == nil
    let model = self.model ?? ColorPickerResultModel(color: color, copiedFormat: copiedFormat)
    model.color = color
    model.copiedFormat = copiedFormat
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

  // MARK: - Window

  private func makeWindow(model: ColorPickerResultModel) -> NSWindow {
    let window = NSWindow(
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
    self.hostingView = hostingView

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
      onPickAgain: { [weak self] in self?.onPickAgain() }
    )
  }

  private func copy(_ format: ColorPickerFormat) {
    guard let model else { return }
    copyToPasteboard(format.string(for: model.color))
    model.copiedFormat = format
  }

  // MARK: - NSWindowDelegate

  func windowWillClose(_ notification: Notification) {
    let closingWindow = window
    window = nil
    hostingView = nil
    model = nil
    NSApp.revertActivationPolicyToAccessoryIfNeeded(excluding: closingWindow)
  }
}

#if DEBUG
extension ColorPickerResultWindowController {
  var testWindow: NSWindow? { window }
  var testCopiedFormat: ColorPickerFormat? { model?.copiedFormat }

  func testCopy(_ format: ColorPickerFormat) {
    copy(format)
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

  init(color: ColorPickerColor, copiedFormat: ColorPickerFormat) {
    self.color = color
    self.copiedFormat = copiedFormat
  }
}

struct ColorPickerResultView: View {
  @ObservedObject var model: ColorPickerResultModel
  let onCopy: (ColorPickerFormat) -> Void
  let onPickAgain: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header

      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
        ForEach(ColorPickerFormat.allCases) { format in
          GridRow {
            Text(verbatim: format.title)
              .foregroundStyle(.secondary)
            Text(verbatim: format.string(for: model.color))
              .monospaced()
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button {
              onCopy(format)
            } label: {
              Image(systemName: model.copiedFormat == format ? "checkmark" : "doc.on.doc")
                .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(L10n.Common.copy)
            .accessibilityLabel("\(L10n.Common.copy) \(format.title)")
          }
        }
      }

      pickAgainButton
    }
    .padding(20)
    // Clears the titlebar, which the content extends under.
    .padding(.top, 18)
    .frame(width: 360, alignment: .leading)
  }

  private var header: some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(cgColor: model.color.cgColor))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.separator)
        )
        .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: model.color.hex)
          .font(.title3.monospaced().weight(.semibold))
          .textSelection(.enabled)
        Label(L10n.ScreenCapture.colorPickerCopied(model.copiedFormat.title), systemImage: "checkmark.circle.fill")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var pickAgainButton: some View {
    let button = Button(action: onPickAgain) {
      Label(L10n.ScreenCapture.colorPickerPickAgain, systemImage: "eyedropper")
        .frame(maxWidth: .infinity)
    }
    .controlSize(.large)

    if #available(macOS 26.0, *) {
      button.buttonStyle(.glass)
    } else {
      button.buttonStyle(.bordered)
    }
  }
}
