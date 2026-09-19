//
//  QuickAccessPinWindowView.swift
//  Snapzy
//
//  Floating image-first surface for pinned screenshots.
//

import AppKit
import SwiftUI

struct QuickAccessPinWindowView: View {
  @ObservedObject var state: QuickAccessPinWindowState

  let onClose: () -> Void
  let onZoomSizeChange: (CGSize) -> Void
  let onLockChanged: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isZoomPickerPresented = false
  @State private var isZoomHovering = false
  @State private var isDragHovering = false
  @State private var isDragActive = false

  private let cornerRadius = NSWindow.defaultCornerRadius
  private let dragHandleCornerRadius: CGFloat = 8
  private let controlInset: CGFloat = 12

  var body: some View {
    ZStack {
      screenshotImage
      chromeLayer
    }
    .frame(width: state.displaySize.width, height: state.displaySize.height)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(Color.white.opacity(0.22), lineWidth: 1)
    )
    .background(Color.clear)
  }

  private var screenshotImage: some View {
    Image(nsImage: state.image)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: state.displaySize.width, height: state.displaySize.height)
      .background(Color.black.opacity(0.03))
      .clipped()
      .opacity(state.isLocked && state.isMouseInside ? 0.18 : 1)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: state.isMouseInside)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: state.isLocked)
  }

  private var chromeLayer: some View {
    ZStack {
      unlockedControls
        .opacity(state.isLocked ? 0 : 1)
        .allowsHitTesting(!state.isLocked)

      interactiveRegion(lockButton)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(controlInset)
    }
  }

  private var unlockedControls: some View {
    ZStack {
      interactiveRegion(
        chromeButton(systemName: "xmark", help: L10n.PreferencesQuickAccess.unpinAction, action: onClose)
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(controlInset)

      interactiveRegion(zoomMenu)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, controlInset)

      interactiveRegion(dragHandle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, controlInset)
    }
  }

  /// Wraps interactive chrome so background-window dragging never starts on
  /// a control, keeping both drags and clicks exclusive to the control.
  private func interactiveRegion<V: View>(_ content: V) -> some View {
    content.background(PinWindowDragExclusionRepresentable())
  }

  private var lockButton: some View {
    chromeButton(
      systemName: state.isLocked ? "lock.fill" : "lock.open",
      help: state.isLocked ? L10n.QuickAccess.unlockPinnedWindow : L10n.QuickAccess.lockPinnedWindow
    ) {
      state.isLocked.toggle()
      onLockChanged()
    }
  }

  private var zoomMenu: some View {
    Button {
      isZoomPickerPresented.toggle()
    } label: {
      Text("\(state.zoomPercent)%")
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
          Capsule(style: .continuous)
            .fill(Color.black.opacity(isZoomHovering || isZoomPickerPresented ? 0.64 : 0.54))
        )
        .overlay(
          Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: false)
    .onHover { isZoomHovering = $0 }
    .popover(isPresented: $isZoomPickerPresented, arrowEdge: .top) {
      zoomPicker
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isZoomHovering)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isZoomPickerPresented)
    .help(L10n.QuickAccess.zoomPinnedWindow)
  }

  private var zoomPicker: some View {
    VStack(spacing: 4) {
      ForEach(state.zoomMenuPercents, id: \.self) { percent in
        PinWindowZoomOptionButton(
          title: "\(percent)%",
          isSelected: percent == state.zoomPercent
        ) {
          onZoomSizeChange(state.setZoomPercent(percent))
          isZoomPickerPresented = false
        }
      }

      Rectangle()
        .fill(Color.primary.opacity(0.08))
        .frame(height: 1)
        .padding(.vertical, 3)

      PinWindowZoomOptionButton(
        title: L10n.QuickAccess.fitPinnedWindow,
        systemImage: "arrow.down.right.and.arrow.up.left",
        isSelected: state.zoomPercent == 100
      ) {
        onZoomSizeChange(state.resetZoom())
        isZoomPickerPresented = false
      }
    }
    .padding(PinWindowZoomPickerMetrics.contentInset)
    .frame(width: PinWindowZoomPickerMetrics.width)
    .background(
      RoundedRectangle(cornerRadius: PinWindowZoomPickerMetrics.containerCornerRadius, style: .continuous)
        .fill(.regularMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: PinWindowZoomPickerMetrics.containerCornerRadius, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: PinWindowZoomPickerMetrics.containerCornerRadius, style: .continuous))
    .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
  }

  private var dragHandle: some View {
    QuickAccessPinDragHandleView(
      fileURL: state.url,
      image: state.image,
      thumbnail: state.thumbnail,
      onDragStateChanged: { isDragActive = $0 }
    )
    .frame(width: 72, height: 32)
    .overlay(
      HStack(spacing: 8) {
        dragGrip

        Image(systemName: "doc.fill")
          .font(.system(size: 15, weight: .semibold))
          .frame(width: 14)

        dragGrip
      }
      .foregroundStyle(dragForegroundColor)
      .allowsHitTesting(false)
    )
    .background(dragHandleFill(isActive: isDragHovering || isDragActive))
    .overlay(dragHandleStroke(isActive: isDragHovering || isDragActive))
    .scaleEffect(isDragHovering || isDragActive ? 1.015 : 1)
    .shadow(color: Color.black.opacity(isDragHovering || isDragActive ? 0.18 : 0.12), radius: 7, x: 0, y: 2)
    .onHover { isDragHovering = $0 }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDragHovering)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDragActive)
    .help(L10n.AnnotateUI.dragToAppHelp)
  }

  private var dragGrip: some View {
    VStack(spacing: 3) {
      ForEach(0..<3, id: \.self) { _ in
        Capsule(style: .continuous)
          .fill(Color.primary.opacity(0.34))
          .frame(width: 7, height: 1.3)
      }
    }
    .frame(width: 10)
  }

  private func chromeButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.primary)
        .frame(width: 28, height: 28)
        .background(
          Circle()
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.84))
        )
        .overlay(
          Circle()
            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private var dragForegroundColor: Color {
    isDragHovering || isDragActive ? .primary : Color.primary.opacity(0.62)
  }

  private func dragHandleFill(isActive: Bool) -> some View {
    RoundedRectangle(cornerRadius: dragHandleCornerRadius, style: .continuous)
      .fill(Color(nsColor: .windowBackgroundColor).opacity(isActive ? 0.94 : 0.86))
  }

  private func dragHandleStroke(isActive: Bool) -> some View {
    RoundedRectangle(cornerRadius: dragHandleCornerRadius, style: .continuous)
      .strokeBorder(Color.primary.opacity(isActive ? 0.16 : 0.08), lineWidth: 1)
  }
}

private enum PinWindowZoomPickerMetrics {
  static let width: CGFloat = 122
  static let contentInset: CGFloat = 6
  static let containerCornerRadius: CGFloat = Size.radiusLg
  static var optionCornerRadius: CGFloat {
    max(containerCornerRadius - contentInset, Size.radiusMd)
  }
}

private struct PinWindowZoomOptionButton: View {
  let title: String
  var systemImage: String?
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false
  private let cornerRadius = PinWindowZoomPickerMetrics.optionCornerRadius

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        if let systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 12)
        }

        Text(title)
          .font(.system(size: 11, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.75)

        Spacer(minLength: 4)

        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
        }
      }
      .foregroundStyle(isSelected || isHovering ? .primary : .secondary)
      .padding(.horizontal, 8)
      .frame(height: 25)
      .background(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(rowFill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(rowStroke, lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .animation(.easeInOut(duration: 0.12), value: isHovering)
  }

  private var rowFill: Color {
    if isSelected {
      return Color.primary.opacity(0.1)
    }
    return isHovering ? Color.primary.opacity(0.075) : Color.clear
  }

  private var rowStroke: Color {
    isSelected || isHovering ? Color.primary.opacity(0.08) : Color.clear
  }
}

/// NSView marker that opts a region of the pin window out of background
/// window dragging. `QuickAccessPinWindow` hit-tests for this class before
/// starting a native-or-manual background drag, so chrome controls keep
/// their clicks and future interactive controls only need to be wrapped in
/// `PinWindowDragExclusionRepresentable`.
final class PinWindowDragExclusionView: NSView {
  override var mouseDownCanMoveWindow: Bool { false }
}

struct PinWindowDragExclusionRepresentable: NSViewRepresentable {
  func makeNSView(context: Context) -> PinWindowDragExclusionView {
    PinWindowDragExclusionView(frame: .zero)
  }

  func updateNSView(_ nsView: PinWindowDragExclusionView, context: Context) {}
}
