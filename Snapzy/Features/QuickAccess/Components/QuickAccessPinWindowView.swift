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
  let onLockChanged: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isZoomPickerPresented = false
  @State private var isZoomHovering = false
  @State private var isLockHovering = false
  @State private var isDragHovering = false
  @State private var isDragActive = false

  private let cornerRadius = NSWindow.defaultCornerRadius
  private let dragHandleCornerRadius: CGFloat = 8
  private let controlInset: CGFloat = 12

  /// Hidden chrome shrinks a little instead of only losing its surface, so it settles into place
  /// rather than blinking in. A transform keeps the glass backdrop attached (Rule 2), opacity
  /// would not.
  private static let hiddenChromeScale: CGFloat = 0.86

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
    QuickAccessPinImageViewport(state: state)
      .frame(width: state.displaySize.width, height: state.displaySize.height)
      .clipped()
      .opacity(state.isLocked && state.isMouseInside ? 0.18 : 1)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: state.isMouseInside)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: state.isLocked)
  }

  private var chromeLayer: some View {
    ZStack {
      unlockedControls
        .allowsHitTesting(unlockedChromeIsRevealed)

      interactiveRegion(
        lockButton(isRevealed: lockChromeIsRevealed),
        isExcluded: lockChromeIsRevealed
      )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(controlInset)
    }
  }

  /// Chrome answers to the pointer being over the pinned image instead of sitting on top of it
  /// permanently — the point of a pin is to look at the capture. Interactions that outlive the
  /// hover itself keep their own control lit, so an open popover is never stranded by the pointer
  /// drifting off the frame.
  private var wantsChrome: Bool {
    state.isMouseInside || isZoomPickerPresented || isDragActive || isDragHovering
  }

  private var unlockedChromeIsRevealed: Bool {
    !state.isLocked && wantsChrome
  }

  /// A locked pin is click-through everywhere but the lock rect, so there the button is revealed by
  /// its own hover; the pointer merely crossing the image would light something it cannot click.
  private var lockChromeIsRevealed: Bool {
    state.isLocked ? isLockHovering : wantsChrome
  }

  private var chromeMotion: Animation? {
    reduceMotion ? nil : LiquidGlassTokens.hoverSpring
  }

  private var unlockedControls: some View {
    ZStack {
      interactiveRegion(
        chromeButton(
          systemName: "xmark",
          help: L10n.PreferencesQuickAccess.unpinAction,
          isRevealed: unlockedChromeIsRevealed,
          action: onClose
        ),
        isExcluded: unlockedChromeIsRevealed
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(controlInset)

      interactiveRegion(
        zoomMenu(isRevealed: unlockedChromeIsRevealed),
        isExcluded: unlockedChromeIsRevealed
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .padding(.top, controlInset)

      interactiveRegion(
        dragHandle(isRevealed: unlockedChromeIsRevealed),
        isExcluded: unlockedChromeIsRevealed
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      .padding(.bottom, controlInset)
    }
  }

  /// Wraps interactive chrome so background-window dragging never starts on
  /// a control, keeping both drags and clicks exclusive to the control. Hidden chrome drops out of
  /// the exclusion too — an invisible button must not eat the drag and leave a dead patch.
  private func interactiveRegion(_ content: some View, isExcluded: Bool) -> some View {
    content.background(PinWindowDragExclusionRepresentable(isActive: isExcluded))
  }

  private func lockButton(isRevealed: Bool) -> some View {
    chromeButton(
      systemName: state.isLocked ? "lock.fill" : "lock.open",
      help: state.isLocked ? L10n.QuickAccess.unlockPinnedWindow : L10n.QuickAccess.lockPinnedWindow,
      isRevealed: isRevealed
    ) {
      state.isLocked.toggle()
      onLockChanged()
    }
    .onHover { hovering in
      isLockHovering = hovering
    }
    .animation(chromeMotion, value: isLockHovering)
  }

  private func zoomMenu(isRevealed: Bool) -> some View {
    Button {
      isZoomPickerPresented.toggle()
    } label: {
      Text("\(state.zoomPercent)%")
        .font(.system(size: 12, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(LiquidGlassTokens.inkOverlay.opacity(isRevealed ? 1 : 0))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .liquidGlassChrome(
          shape: Capsule(style: .continuous),
          isVisible: isRevealed,
          isActive: isZoomHovering || isZoomPickerPresented,
          emphasis: .overlay
        )
        .shadow(color: Color.black.opacity(isRevealed ? 0.2 : 0), radius: 5, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    .fixedSize(horizontal: true, vertical: false)
    .scaleEffect(isRevealed ? 1 : Self.hiddenChromeScale)
    .onHover { hovering in
      withAnimation(chromeMotion) {
        isZoomHovering = hovering
      }
    }
    .popover(isPresented: $isZoomPickerPresented, arrowEdge: .top) {
      zoomPicker
    }
    .animation(chromeMotion, value: isRevealed)
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
          state.setZoomPercent(percent)
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
        state.resetZoom()
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

  private func dragHandle(isRevealed: Bool) -> some View {
    QuickAccessPinDragHandleView(
      fileURL: state.url,
      image: state.image,
      thumbnail: state.thumbnail,
      onDragStateChanged: { isDragActive = $0 }
    )
    .frame(width: 72, height: 32)
    .overlay(
      HStack(spacing: 8) {
        dragGrip(isRevealed: isRevealed)

        Image(systemName: "doc.fill")
          .font(.system(size: 15, weight: .semibold))
          .frame(width: 14)

        dragGrip(isRevealed: isRevealed)
      }
      .foregroundStyle(dragForegroundColor(isRevealed: isRevealed))
      .allowsHitTesting(false)
    )
    .liquidGlassChrome(
      shape: RoundedRectangle(cornerRadius: dragHandleCornerRadius, style: .continuous),
      isVisible: isRevealed,
      isActive: isDragHovering || isDragActive,
      emphasis: .overlay
    )
    // Rule 2: scale, not opacity — a transform never detaches the glass backdrop.
    .scaleEffect(isDragHovering || isDragActive ? 1.015 : 1)
    .scaleEffect(isRevealed ? 1 : Self.hiddenChromeScale)
    .shadow(
      color: Color.black.opacity(isRevealed ? (isDragHovering || isDragActive ? 0.18 : 0.12) : 0),
      radius: 7,
      x: 0,
      y: 2
    )
    .onHover { isDragHovering = $0 }
    .animation(chromeMotion, value: isRevealed)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDragHovering)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDragActive)
    .help(L10n.AnnotateUI.dragToAppHelp)
  }

  private func dragGrip(isRevealed: Bool) -> some View {
    VStack(spacing: 3) {
      ForEach(0..<3, id: \.self) { _ in
        Capsule(style: .continuous)
          .fill(LiquidGlassTokens.inkOverlay.opacity(isRevealed ? 0.34 : 0))
          .frame(width: 7, height: 1.3)
      }
    }
    .frame(width: 10)
  }

  private func chromeButton(
    systemName: String,
    help: String,
    isRevealed: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(LiquidGlassTokens.inkOverlay.opacity(isRevealed ? 1 : 0))
        .frame(width: 28, height: 28)
        // This button floats over the capture with nothing else to mark it as clickable, so while
        // it is shown its surface stays lit and only brightens under the pointer. Hidden chrome
        // gives up the resting surface instead of being wrapped in `.opacity()`, which would
        // detach the glass backdrop (Rule 2).
        .liquidGlassControl(
          isActive: false,
          in: Circle(),
          emphasis: .overlay,
          showsRestingSurface: isRevealed
        )
        .shadow(color: Color.black.opacity(isRevealed ? 0.12 : 0), radius: 6, x: 0, y: 2)
    }
    .buttonStyle(.plain)
    .scaleEffect(isRevealed ? 1 : Self.hiddenChromeScale)
    .animation(chromeMotion, value: isRevealed)
    .help(help)
  }

  private func dragForegroundColor(isRevealed: Bool) -> Color {
    let ink = LiquidGlassTokens.inkOverlay
    guard isRevealed else { return ink.opacity(0) }
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

/// NSView marker that opts a region of the pin window out of background
/// window dragging. `QuickAccessPinWindow` hit-tests for this class before
/// starting a native-or-manual background drag, so chrome controls keep
/// their clicks and future interactive controls only need to be wrapped in
/// `PinWindowDragExclusionRepresentable`.
///
/// Hidden chrome hides its marker: the window hit-tests marker bounds directly instead of going
/// through SwiftUI, so an inactive control would otherwise keep refusing drags from a spot the
/// user cannot see.
final class PinWindowDragExclusionView: NSView {
  override var mouseDownCanMoveWindow: Bool { false }
}

struct PinWindowDragExclusionRepresentable: NSViewRepresentable {
  let isActive: Bool

  func makeNSView(context _: Context) -> PinWindowDragExclusionView {
    let view = PinWindowDragExclusionView(frame: .zero)
    view.isHidden = !isActive
    return view
  }

  func updateNSView(_ nsView: PinWindowDragExclusionView, context _: Context) {
    nsView.isHidden = !isActive
  }
}
