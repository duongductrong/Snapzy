//
//  CursorBubbleController.swift
//  Snapzy
//
//  Figma-style "cursor chat" bubble that sticks to the pointer for a moment.
//

import AppKit
import Combine
import SwiftUI

/// Shows a short message in a pill that rides along with the pointer, like
/// Figma's cursor chat. Non-interactive, never takes focus, and is excluded
/// from captures like other Snapzy toasts.
@MainActor
final class CursorBubbleController {
  static let shared = CursorBubbleController()

  /// Panel offset from the pointer tip. The bubble sits 10pt inside the panel
  /// (shadow room), so the visible gap is this plus 10.
  private static let pointerOffset = CGSize(width: 4, height: 6)
  private static let screenMargin: CGFloat = 0

  private var panel: NSPanel?
  private let model = CursorBubbleModel()
  private var followTimer: Timer?
  private var dismissTask: Task<Void, Never>?
  private var lastMouseLocation: CGPoint?

  private init() {}

  /// Shows (or refreshes) the bubble. Calling again while visible restarts the
  /// timer and gives the bubble a small nudge instead of stacking a new one.
  func show(_ message: String, duration: TimeInterval = 1.8) {
    let isVisible = panel?.isVisible == true && model.isPresented
    model.message = message

    let panel = resolvePanel()
    resizePanelToFit(panel)
    lastMouseLocation = nil
    followPointer()

    if isVisible {
      model.nudge()
    } else {
      CaptureChromeWindowRegistry.configureAppWindow(panel)
      panel.alphaValue = 1
      panel.orderFrontRegardless()
      model.present(reduceMotion: Self.reduceMotion)
    }

    startFollowing()
    scheduleDismiss(after: duration)
  }

  // MARK: - Panel

  private func resolvePanel() -> NSPanel {
    if let panel { return panel }
    let panel = AppToastManager.makeToastPanel(contentRect: .zero)
    // Glass draws its own shadow; sit above capture overlays (`.screenSaver`).
    panel.hasShadow = false
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    panel.contentView = NSHostingView(rootView: CursorBubbleView(model: model))
    self.panel = panel
    return panel
  }

  private func resizePanelToFit(_ panel: NSPanel) {
    guard let hostingView = panel.contentView else { return }
    let size = hostingView.fittingSize
    panel.setContentSize(size)
  }

  // MARK: - Following

  private func startFollowing() {
    guard followTimer == nil else { return }
    // 120 Hz keeps the bubble glued to the pointer on ProMotion displays; the
    // timer only lives for the ~2s the bubble is on screen.
    let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.followPointer() }
    }
    RunLoop.main.add(timer, forMode: .common)
    followTimer = timer
  }

  private func stopFollowing() {
    followTimer?.invalidate()
    followTimer = nil
  }

  private func followPointer() {
    guard let panel else { return }
    let mouse = NSEvent.mouseLocation
    guard mouse != lastMouseLocation else { return }
    lastMouseLocation = mouse

    let size = panel.frame.size
    let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    let bounds = screen?.visibleFrame ?? CGRect(origin: .zero, size: CGSize(width: 10_000, height: 10_000))
    let margin = Self.screenMargin
    let offset = Self.pointerOffset

    // Default: below-right of the pointer (AppKit y grows upward).
    var x = mouse.x + offset.width
    var y = mouse.y - offset.height - size.height
    var flipsX = false
    var flipsY = false
    if x + size.width > bounds.maxX - margin {
      x = mouse.x - offset.width - size.width
      flipsX = true
    }
    if y < bounds.minY + margin {
      y = mouse.y + offset.height
      flipsY = true
    }
    x = min(max(x, bounds.minX + margin), bounds.maxX - size.width - margin)
    y = min(max(y, bounds.minY + margin), bounds.maxY - size.height - margin)

    model.setPointedCorner(flipsX: flipsX, flipsY: flipsY)
    panel.setFrameOrigin(CGPoint(x: x.rounded(), y: y.rounded()))
  }

  // MARK: - Dismissal

  private func scheduleDismiss(after duration: TimeInterval) {
    dismissTask?.cancel()
    dismissTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(max(0.6, duration) * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.dismiss()
    }
  }

  private func dismiss() {
    guard let panel else { return }
    model.dismiss(reduceMotion: Self.reduceMotion)
    dismissTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 220_000_000)
      guard !Task.isCancelled else { return }
      panel.orderOut(nil)
      self?.stopFollowing()
    }
  }

  private static var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
}

// MARK: - Model

@MainActor
private final class CursorBubbleModel: ObservableObject {
  @Published var message = ""
  @Published private(set) var isPresented = false
  @Published private(set) var nudgeScale: CGFloat = 1
  /// Which corner points at the cursor; flips near screen edges.
  @Published private(set) var anchor: UnitPoint = .topLeading

  func present(reduceMotion: Bool) {
    isPresented = false
    let animation: Animation = reduceMotion
      ? .easeOut(duration: 0.12)
      : .spring(response: 0.32, dampingFraction: 0.62)
    // Next runloop turn so SwiftUI sees the false → true transition.
    DispatchQueue.main.async {
      withAnimation(animation) { self.isPresented = true }
    }
  }

  func nudge() {
    withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { nudgeScale = 1.08 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
      withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { self.nudgeScale = 1 }
    }
  }

  func dismiss(reduceMotion: Bool) {
    withAnimation(.easeIn(duration: reduceMotion ? 0.12 : 0.18)) { isPresented = false }
  }

  func setPointedCorner(flipsX: Bool, flipsY: Bool) {
    let next: UnitPoint
    switch (flipsX, flipsY) {
    case (false, false): next = .topLeading
    case (true, false): next = .topTrailing
    case (false, true): next = .bottomLeading
    case (true, true): next = .bottomTrailing
    }
    if next != anchor { anchor = next }
  }
}

// MARK: - View

private struct CursorBubbleView: View {
  @ObservedObject var model: CursorBubbleModel

  var body: some View {
    let shape = CursorBubbleShape(pointedCorner: model.anchor)

    HStack(spacing: 7) {
      CursorBubbleDots()
      Text(model.message)
        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .fixedSize()
    }
    .padding(.leading, 11)
    .padding(.trailing, 13)
    .padding(.vertical, 7)
    .modifier(CursorBubbleGlass(shape: shape))
    // Room for the glass shadow inside the borderless panel.
    .padding(10)
    .scaleEffect(model.isPresented ? model.nudgeScale : 0.6, anchor: model.anchor)
    .opacity(model.isPresented ? 1 : 0)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(model.message)
  }
}

/// Clear Liquid Glass on macOS 26+ (when the user keeps Liquid Glass on); the
/// design system's legacy glass composite otherwise.
private struct CursorBubbleGlass: ViewModifier {
  let shape: CursorBubbleShape

  @Environment(\.liquidGlassRenderMode) private var renderMode
  @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *),
       LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled) {
      content.glassEffect(.clear, in: shape)
    } else {
      content
        .liquidGlassSurface(shape: shape)
        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
    }
  }
}

/// Rounded pill whose corner nearest the cursor is almost square, like a speech bubble.
private struct CursorBubbleShape: InsettableShape {
  var pointedCorner: UnitPoint
  var radius: CGFloat = 13
  var pointedRadius: CGFloat = 3
  var inset: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    let rect = rect.insetBy(dx: inset, dy: inset)
    let maxRadius = min(rect.width, rect.height) / 2
    func r(_ corner: UnitPoint) -> CGFloat {
      min(corner == pointedCorner ? pointedRadius : radius, maxRadius)
    }
    let tl = r(.topLeading), tr = r(.topTrailing), bl = r(.bottomLeading), br = r(.bottomTrailing)

    var path = Path()
    path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr), radius: tr)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY), radius: br)
    path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bl), radius: bl)
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + tl, y: rect.minY), radius: tl)
    path.closeSubpath()
    return path
  }

  func inset(by amount: CGFloat) -> CursorBubbleShape {
    var shape = self
    shape.inset += amount
    return shape
  }
}

/// Three softly bouncing accent-colored dots — a "working on it" typing indicator.
private struct CursorBubbleDots: View {
  @State private var animating = false

  var body: some View {
    HStack(spacing: 2.5) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(Color.accentColor)
          .frame(width: 4, height: 4)
          .opacity(animating ? 1 : 0.4)
          .offset(y: animating ? -1.5 : 1.5)
          .animation(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
              ? nil
              : .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(index) * 0.15),
            value: animating
          )
      }
    }
    .frame(height: 12)
    .onAppear { animating = true }
  }
}
