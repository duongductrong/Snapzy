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

      lockButton
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(controlInset)
    }
  }

  private var unlockedControls: some View {
    ZStack {
      chromeButton(systemName: "xmark", help: L10n.PreferencesQuickAccess.unpinAction, action: onClose)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(controlInset)

      zoomMenu
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, controlInset)

      dragHandle
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, controlInset)
    }
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
        .foregroundStyle(LiquidGlassTokens.inkOverlay)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .liquidGlassChrome(
          shape: Capsule(style: .continuous),
          isVisible: true,
          isActive: isZoomHovering || isZoomPickerPresented,
          emphasis: .overlay
        )
        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: false)
    .onHover { hovering in
      withAnimation(reduceMotion ? nil : LiquidGlassTokens.hoverSpring) {
        isZoomHovering = hovering
      }
    }
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
    .liquidGlassChrome(
      shape: RoundedRectangle(cornerRadius: dragHandleCornerRadius, style: .continuous),
      isVisible: true,
      isActive: isDragHovering || isDragActive,
      emphasis: .overlay
    )
    // Rule 2: scale, not opacity — a transform never detaches the glass backdrop.
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
          .fill(LiquidGlassTokens.inkOverlay.opacity(0.34))
          .frame(width: 7, height: 1.3)
      }
    }
    .frame(width: 10)
  }

  private func chromeButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(LiquidGlassTokens.inkOverlay)
        .frame(width: 28, height: 28)
        // Floats over the pinned capture with nothing else to mark it as a control, so the
        // surface stays lit at rest and only brightens under the pointer.
        .liquidGlassControl(
          isActive: false,
          in: Circle(),
          emphasis: .overlay,
          showsRestingSurface: true
        )
        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private var dragForegroundColor: Color {
    let ink = LiquidGlassTokens.inkOverlay
    return isDragHovering || isDragActive ? ink : ink.opacity(0.62)
  }
}

private enum PinWindowZoomPickerMetrics {
  static let width: CGFloat = 122
  static let contentInset: CGFloat = 6
  static let containerCornerRadius = Radius.panel
}

private struct PinWindowZoomOptionButton: View {
  let title: String
  var systemImage: String?
  let isSelected: Bool
  let action: () -> Void

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
      .foregroundStyle(isSelected ? LiquidGlassTokens.inkOnAccent : LiquidGlassTokens.inkBody)
      .padding(.horizontal, 8)
      .frame(height: 25)
      .liquidGlassControl(
        isActive: isSelected,
        in: Capsule(style: .continuous)
      )
    }
    .buttonStyle(.plain)
  }
}
