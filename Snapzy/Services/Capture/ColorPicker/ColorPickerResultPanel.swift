//
//  ColorPickerResultPanel.swift
//  Snapzy
//
//  The card shown after Pick Color copies a color: a swatch, the value in every
//  `ColorPickerFormat` with one-click copy, and Pick Again. It floats next to the picked
//  point without taking keyboard focus, and closes on Esc, a click elsewhere, or a new pick.
//

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class ColorPickerResultPresenter {
  private static let pointerGap: CGFloat = 18

  private let copyToPasteboard: (String) -> Void
  private let onPickAgain: () -> Void
  private var panel: ColorPickerResultWindow?
  private var model: ColorPickerResultModel?
  private var monitors: [Any] = []

  init(copyToPasteboard: @escaping (String) -> Void, onPickAgain: @escaping () -> Void) {
    self.copyToPasteboard = copyToPasteboard
    self.onPickAgain = onPickAgain
  }

  var isVisible: Bool { panel != nil }

  /// `copiedFormat` is what the pick already put on the clipboard. `screenPoint` is where the
  /// color was picked, in AppKit global coordinates.
  func show(color: ColorPickerColor, copiedFormat: ColorPickerFormat, near screenPoint: CGPoint) {
    dismiss()

    let model = ColorPickerResultModel(color: color, copiedFormat: copiedFormat)
    self.model = model
    let view = ColorPickerResultView(
      model: model,
      onCopy: { [weak self] format in self?.copy(format) },
      onPickAgain: { [weak self] in self?.pickAgain() },
      onClose: { [weak self] in self?.dismiss() }
    )
    let hostingView = NSHostingView(rootView: view)
    let size = hostingView.fittingSize
    let panel = ColorPickerResultWindow(contentRect: CGRect(origin: .zero, size: size))
    panel.contentView = hostingView
    panel.setFrameOrigin(Self.origin(for: size, near: screenPoint))
    panel.orderFrontRegardless()
    self.panel = panel
    installMonitors()
  }

  func dismiss() {
    removeMonitors()
    panel?.orderOut(nil)
    panel?.close()
    panel = nil
    model = nil
  }

  private func copy(_ format: ColorPickerFormat) {
    guard let model else { return }
    copyToPasteboard(format.string(for: model.color))
    model.copiedFormat = format
  }

  private func pickAgain() {
    dismiss()
    onPickAgain()
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

  private func installMonitors() {
    // The card never takes key focus (typing keeps going to the app in front), so Esc and
    // outside clicks are observed globally, plus locally for Snapzy's own windows.
    let handleKey: (NSEvent) -> Bool = { [weak self] event in
      guard event.keyCode == UInt16(kVK_Escape) else { return false }
      self?.dismiss()
      return true
    }
    let handleClick: (NSEvent) -> Void = { [weak self] event in
      guard let self, let panel = self.panel, event.window !== panel else { return }
      self.dismiss()
    }
    if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
      MainActor.assumeIsolated { _ = handleKey(event) }
    }) {
      monitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
      handleKey(event) ? nil : event
    }) {
      monitors.append(monitor)
    }
    if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in
      MainActor.assumeIsolated { handleClick(event) }
    }) {
      monitors.append(monitor)
    }
    if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in
      handleClick(event)
      return event
    }) {
      monitors.append(monitor)
    }
  }

  private func removeMonitors() {
    monitors.forEach(NSEvent.removeMonitor)
    monitors.removeAll()
  }
}

#if DEBUG
extension ColorPickerResultPresenter {
  var testPanel: NSPanel? { panel }
  var testCopiedFormat: ColorPickerFormat? { model?.copiedFormat }

  func testCopy(_ format: ColorPickerFormat) {
    copy(format)
  }

  func testPickAgain() {
    pickAgain()
  }
}
#endif

// MARK: - Window

final class ColorPickerResultWindow: NSPanel {
  init(contentRect: CGRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = .statusBar
    isFloatingPanel = true
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    animationBehavior = .utilityWindow
    // Snapzy's own chrome never lands in a capture or a recording.
    sharingType = .none
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    appearance = ThemeManager.shared.nsAppearance
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

// MARK: - Content

@MainActor
final class ColorPickerResultModel: ObservableObject {
  let color: ColorPickerColor
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
  let onClose: () -> Void

  private var swatch: Color { Color(cgColor: model.color.cgColor) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      VStack(spacing: 2) {
        ForEach(ColorPickerFormat.allCases) { format in
          ColorPickerFormatRow(
            title: format.title,
            value: format.string(for: model.color),
            isCopied: model.copiedFormat == format,
            onCopy: { onCopy(format) }
          )
        }
      }

      Button(action: onPickAgain) {
        Label(L10n.ScreenCapture.colorPickerPickAgain, systemImage: "eyedropper")
          .font(.system(size: 12, weight: .medium))
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(LiquidGlassButtonStyle(emphasis: .secondary, capsule: true))
    }
    .padding(14)
    .frame(width: 340)
    .liquidGlassSurface(shape: Radius.rect(Radius.panel))
    .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 6)
    .padding(16)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Radius.rect(Radius.tile)
        .fill(swatch)
        .frame(width: 46, height: 46)
        .overlay(Radius.rect(Radius.tile).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))

      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: model.color.hex)
          .font(.system(size: 17, weight: .semibold, design: .monospaced))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)
        Label(L10n.ScreenCapture.colorPickerCopied(model.copiedFormat.title), systemImage: "checkmark.circle.fill")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(LiquidGlassTokens.inkBody)
          .labelStyle(.titleAndIcon)
      }

      Spacer(minLength: 0)

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(LiquidGlassTokens.inkMuted)
          .frame(width: 22, height: 22)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help(L10n.Common.close)
      .accessibilityLabel(L10n.Common.close)
    }
  }
}

private struct ColorPickerFormatRow: View {
  let title: String
  let value: String
  let isCopied: Bool
  let onCopy: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onCopy) {
      HStack(spacing: 10) {
        Text(verbatim: title)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(LiquidGlassTokens.inkMuted)
          .frame(width: 52, alignment: .leading)
        Text(verbatim: value)
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)
          // Long notations (SwiftUI) wrap rather than hide part of what gets copied.
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(isCopied ? Color(nsColor: .systemGreen) : LiquidGlassTokens.inkMuted)
          .frame(width: 16)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(minHeight: 26)
      .background(
        Radius.controlRect(forHeight: 26)
          .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
      )
      .contentShape(Radius.controlRect(forHeight: 26))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(L10n.Common.copy)
    .accessibilityLabel("\(L10n.Common.copy) \(title) \(value)")
  }
}
