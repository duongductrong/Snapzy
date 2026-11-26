//
//  AutomationRunHUD.swift
//  Snapzy
//
//  Small bottom-center Liquid Glass capsule (clear variant) shown when a run
//  takes longer than 1.5 s: the automation, its current step and a Cancel
//  button. Non-activating, so it never takes focus from the app the user is
//  working in.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AutomationRunHUDController {
  static let shared = AutomationRunHUDController()

  private static let showDelay: UInt64 = 1_500_000_000

  private final class Model: ObservableObject {
    @Published var name = ""
    @Published var step = ""
    @Published var isShown = false
  }

  private struct ActiveRun {
    let name: String
    var step: String
    var showTask: Task<Void, Never>?
  }

  private var runs: [UUID: ActiveRun] = [:]
  private var displayedRunID: UUID?
  private var panel: NSPanel?
  /// The drop shadow lives in its own event-transparent window behind the glass, as Ruru's
  /// composer does: the glass window stays exactly the size of the glass, so no transparent
  /// shadow margin ever eats a click meant for the app underneath.
  private var shadowPanel: NSPanel?
  private var hideTask: Task<Void, Never>?
  private let model = Model()

  func handle(_ update: AutomationRunUpdate) {
    switch update {
    case .started(let runID, let name):
      let task = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: Self.showDelay)
        guard !Task.isCancelled else { return }
        self?.show(runID)
      }
      runs[runID] = ActiveRun(name: name, step: "", showTask: task)
    case .step(let runID, let title):
      runs[runID]?.step = title
      if displayedRunID == runID { model.step = title }
    case .finished(let runID):
      runs.removeValue(forKey: runID)?.showTask?.cancel()
      if displayedRunID == runID {
        displayedRunID = nil
        if let next = runs.keys.first, runs[next]?.showTask == nil {
          show(next)
        } else {
          hide()
        }
      }
    }
  }

  #if DEBUG
    /// `-SnapzyDemoAutomationHUD` launch argument: plays a fake long-running run so the HUD can
    /// be reviewed without building an automation that takes > 1.5 s.
    func runDemoIfRequested() {
      guard ProcessInfo.processInfo.arguments.contains("-SnapzyDemoAutomationHUD") else { return }
      let runID = UUID()
      Task { @MainActor [weak self] in
        self?.handle(.started(runID: runID, name: "Translate Snip"))
        for title in ["Capture area", "Recognize text", "Translate text", "Copy to clipboard"] {
          self?.handle(.step(runID: runID, title: title))
          try? await Task.sleep(nanoseconds: 4_000_000_000)
        }
        self?.handle(.finished(runID: runID))
      }
    }
  #endif

  private func show(_ runID: UUID) {
    guard var run = runs[runID] else { return }
    run.showTask = nil
    runs[runID] = run
    displayedRunID = runID
    hideTask?.cancel()
    hideTask = nil
    model.name = run.name
    model.step = run.step
    model.isShown = true

    let panel = panel ?? makePanel()
    let shadowPanel = shadowPanel ?? makeShadowPanel()
    self.panel = panel
    self.shadowPanel = shadowPanel

    guard let target = targetFrame() else { return }
    if !panel.isVisible {
      // Enter from slightly below. The *windows* move and fade, never the glass inside them:
      // an animated SwiftUI opacity around a glass surface renders it in isolation, cutting
      // the substrate out of its backdrop, and the glass resolves milky. Moving the window
      // also keeps the shadow window in lockstep with the glass.
      let start = target.offsetBy(dx: 0, dy: Self.reduceMotion ? 0 : -Self.travel)
      panel.setFrame(start, display: false)
      shadowPanel.setFrame(Self.shadowFrame(for: start), display: false)
      panel.alphaValue = 0
      shadowPanel.alphaValue = 0
    }
    // Shadow first, so it sits behind the glass.
    shadowPanel.orderFrontRegardless()
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.32
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
      panel.animator().setFrame(target, display: true)
      shadowPanel.animator().setFrame(Self.shadowFrame(for: target), display: true)
      panel.animator().alphaValue = 1
      shadowPanel.animator().alphaValue = 1
    }
  }

  private func hide() {
    guard let panel, let shadowPanel, model.isShown else { return }
    model.isShown = false
    let end = panel.frame.offsetBy(dx: 0, dy: Self.reduceMotion ? 0 : -Self.travel / 2)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().setFrame(end, display: true)
      shadowPanel.animator().setFrame(Self.shadowFrame(for: end), display: true)
      panel.animator().alphaValue = 0
      shadowPanel.animator().alphaValue = 0
    }
    hideTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 220_000_000)
      guard !Task.isCancelled, self?.model.isShown == false else { return }
      panel.orderOut(nil)
      shadowPanel.orderOut(nil)
    }
  }

  private func cancelDisplayedRun() {
    guard let runID = displayedRunID else { return }
    AutomationRunner.shared.cancel(runID: runID)
  }

  private func makePanel() -> NSPanel {
    let size = NSSize(width: AutomationRunHUDView.width, height: AutomationRunHUDView.height)
    let panel = Self.makeBorderlessPanel(size: size)
    let hosting = NSHostingView(rootView: AutomationRunHUDView(model: model) { [weak self] in
      self?.cancelDisplayedRun()
    })
    hosting.frame = NSRect(origin: .zero, size: size)
    hosting.autoresizingMask = [.width, .height]
    hosting.wantsLayer = true
    hosting.layer?.backgroundColor = NSColor.clear.cgColor
    panel.contentView = hosting
    return panel
  }

  private func makeShadowPanel() -> NSPanel {
    let inset = HUDShadowView.inset
    let size = NSSize(
      width: AutomationRunHUDView.width + inset * 2,
      height: AutomationRunHUDView.height + inset * 2
    )
    let panel = Self.makeBorderlessPanel(size: size)
    panel.ignoresMouseEvents = true
    let host = HUDShadowView(frame: NSRect(origin: .zero, size: size))
    host.autoresizingMask = [.width, .height]
    panel.contentView = host
    return panel
  }

  private static func makeBorderlessPanel(size: NSSize) -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    // Depth comes from the glass and `HUDShadowView`; a window shadow would box the capsule.
    panel.hasShadow = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    // Order in/out is animated by hand, on both windows together.
    panel.animationBehavior = .none
    return panel
  }

  /// Bottom-center of the main screen, 40pt above the Dock / screen edge.
  private func targetFrame() -> NSRect? {
    guard let screen = NSScreen.main else { return nil }
    let visible = screen.visibleFrame
    let size = NSSize(width: AutomationRunHUDView.width, height: AutomationRunHUDView.height)
    return NSRect(
      x: (visible.midX - size.width / 2).rounded(),
      y: visible.minY + 40,
      width: size.width,
      height: size.height
    )
  }

  private static func shadowFrame(for glass: NSRect) -> NSRect {
    glass.insetBy(dx: -HUDShadowView.inset, dy: -HUDShadowView.inset)
  }

  private static let travel: CGFloat = 10

  private static var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  // MARK: - View

  private struct AutomationRunHUDView: View {
    static let width: CGFloat = 340
    static let height: CGFloat = 60

    @ObservedObject var model: Model
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
      HStack(spacing: 12) {
        AutomationRunHUDIndicator(reduceMotion: reduceMotion)
        VStack(alignment: .leading, spacing: 2) {
          Text(model.name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(LiquidGlassTokens.inkOverlay)
            .lineLimit(1)
          if !model.step.isEmpty {
            Text(model.step)
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(LiquidGlassTokens.inkOverlay.opacity(0.62))
              .lineLimit(1)
              // Text is not glass, so fading it is free.
              .transition(.opacity.combined(with: .move(edge: .bottom)))
              .id(model.step)
          }
        }
        .animation(LiquidGlassTokens.settleSpring, value: model.step)
        Spacer(minLength: 8)
        Button(L10n.Common.cancel, action: onCancel)
          .buttonStyle(HUDChipButtonStyle())
      }
      .padding(.leading, 13)
      .padding(.trailing, 15)
      .frame(width: Self.width, height: Self.height)
      .background { HUDGlassBackground() }
      // Overlay chrome is dark glass with light ink regardless of the system appearance.
      .environment(\.colorScheme, .dark)
      .accessibilityElement(children: .combine)
    }
  }

  /// Ruru's composer glass, Clear style at its default darkness (0.75) with the panel dim
  /// (0.14):
  ///   1. a black substrate the glass samples, so it resolves as *dark* glass over a white
  ///      window instead of going milky,
  ///   2. one pass of `Glass.clear`, darkened from inside by its tint,
  ///   3. a black wash over the result for legibility,
  ///   4. a rim of our own — at 60pt tall the system's lensed rim barely reads (Ruru draws the
  ///      same rim on its selection bar).
  /// The glass fills the view's bounds and clips itself to its own shape; content sits on top.
  private struct HUDGlassBackground: View {
    // NativeGlass.recipe(.clear, darkness: 0.75, substrate: 0.28, dim: 0.14)
    static let substrate: Double = 0.14
    static let innerTint: Double = 0.07
    static let wash: Double = 0.43

    @Environment(\.liquidGlassRenderMode) private var renderMode
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

    private var usesNativeGlass: Bool {
      LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
    }

    private var shape: Capsule { Capsule(style: .continuous) }

    var body: some View {
      ZStack {
        if reduceTransparency {
          shape.fill(Color(white: 0.13).opacity(0.96))
          rim(top: 0.16, bottom: 0.04, width: 0.5)
        } else if #available(macOS 26.0, *), usesNativeGlass {
          shape.fill(Color.black.opacity(Self.substrate))
          shape
            .fill(Color.clear)
            .glassEffect(Glass.clear.tint(Color.black.opacity(Self.innerTint)), in: shape)
            // The system glass casts a faint shadow past its edge, which this glass-sized
            // window would cut square; `HUDShadowView` draws the real one.
            .clipShape(shape)
          shape.fill(Color.black.opacity(Self.wash))
          rim(top: 0.24, bottom: 0.10, width: 1)
        } else {
          // macOS 13–15: live behind-window vibrancy stands in for the glass.
          LiquidGlassSurface(shape: shape, substrate: 0.28, dim: 0.14, layer: .backdrop)
        }
      }
      .allowsHitTesting(false)
    }

    private func rim(top: Double, bottom: Double, width: CGFloat) -> some View {
      shape.strokeBorder(
        LinearGradient(
          colors: [.white.opacity(top), .white.opacity(bottom)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        lineWidth: width
      )
    }
  }

  /// Path-based CALayer drop shadow (Ruru's two-layer model): a wide, faint ambient halo that
  /// floats the capsule and a tight contact shadow that lands it. Core Animation blurs the
  /// path on the GPU; nothing is drawn inside the capsule, so the glass backdrop stays clean.
  private final class HUDShadowView: NSView {
    private struct Spec {
      let radius: CGFloat
      let offsetY: CGFloat
      let opacity: Float
    }

    private static let specs = [
      Spec(radius: 22, offsetY: 9, opacity: 0.16),
      Spec(radius: 5, offsetY: 2, opacity: 0.11),
    ]

    /// Visible falloff runs to ~3× the blur radius; a clipped blur ends in a straight line.
    static let inset: CGFloat = specs.reduce(0) { max($0, ($1.radius * 3 + $1.offsetY).rounded(.up)) }

    private let shadowLayers: [CALayer]

    override init(frame frameRect: NSRect) {
      shadowLayers = Self.specs.map { spec in
        let layer = CALayer()
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = spec.opacity
        layer.shadowRadius = spec.radius
        layer.shadowOffset = CGSize(width: 0, height: -spec.offsetY)
        layer.masksToBounds = false
        return layer
      }
      super.init(frame: frameRect)
      wantsLayer = true
      layer?.masksToBounds = false
      shadowLayers.forEach { layer?.addSublayer($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
      super.layout()
      let rect = bounds.insetBy(dx: Self.inset, dy: Self.inset)
      let radius = rect.height / 2
      let path = CGPath(
        roundedRect: CGRect(origin: .zero, size: rect.size),
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
      )
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      for layer in shadowLayers {
        layer.frame = rect
        layer.shadowPath = path
      }
      CATransaction.commit()
    }
  }

  /// A Ruru composer chip: real `Glass.clear` tinted dark, so the edge is the system's own
  /// lensed rim rather than a painted gradient. The label is drawn in front of the glass, never
  /// inside it, so it stays sharp. Below macOS 26 a darker body, light pooling at the top and a
  /// lit hairline stand in.
  private struct HUDChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      HUDChipButton(configuration: configuration)
    }
  }

  private struct HUDChipButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    @Environment(\.liquidGlassRenderMode) private var renderMode
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

    private enum ChipState { case resting, hovered, pressed }

    private var state: ChipState {
      configuration.isPressed ? .pressed : isHovered ? .hovered : .resting
    }

    private var usesNativeGlass: Bool {
      !reduceTransparency
        && LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
    }

    var body: some View {
      let shape = Capsule(style: .continuous)
      configuration.label
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(LiquidGlassTokens.inkOverlay.opacity(isHovered ? 1 : 0.92))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background { chip(shape) }
        .contentShape(shape)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .onHover { isHovered = $0 }
        .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: configuration.isPressed)
    }

    @ViewBuilder
    private func chip(_ shape: Capsule) -> some View {
      if #available(macOS 26.0, *), usesNativeGlass {
        shape
          .fill(Color.clear)
          .glassEffect(Glass.clear.tint(Color.black.opacity(nativeTint)).interactive(), in: shape)
      } else {
        ZStack {
          shape.fill(Color.black.opacity(bodyFill))
          shape.fill(
            LinearGradient(
              colors: [.white.opacity(sheen), .white.opacity(0)],
              startPoint: .top,
              endPoint: .center
            )
          )
          shape.strokeBorder(
            LinearGradient(
              colors: [.white.opacity(rim.top), .white.opacity(rim.bottom)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 0.5
          )
        }
      }
    }

    // GlassChip tokens.
    private var nativeTint: Double {
      switch state {
      case .resting: 0.34
      case .hovered: 0.42
      case .pressed: 0.50
      }
    }

    private var bodyFill: Double {
      switch state {
      case .resting: 0.36
      case .hovered: 0.44
      case .pressed: 0.52
      }
    }

    private var sheen: Double {
      switch state {
      case .resting: 0.07
      case .hovered: 0.11
      case .pressed: 0.05
      }
    }

    private var rim: (top: Double, bottom: Double) {
      switch state {
      case .resting: (0.22, 0.06)
      case .hovered: (0.32, 0.10)
      case .pressed: (0.18, 0.05)
      }
    }
  }

  /// Glass-free orb with a sweeping accent arc around the automation glyph.
  private struct AutomationRunHUDIndicator: View {
    let reduceMotion: Bool
    @State private var isSpinning = false

    var body: some View {
      ZStack {
        Circle()
          .fill(Color.white.opacity(0.10))
        Circle()
          .strokeBorder(Color.white.opacity(0.14), lineWidth: 2)
        Circle()
          .trim(from: 0, to: 0.28)
          .stroke(
            AngularGradient(
              colors: [Color.accentColor.opacity(0), Color.accentColor, .white],
              center: .center,
              startAngle: .degrees(0),
              endAngle: .degrees(100)
            ),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
          )
          .padding(1)
          .rotationEffect(.degrees(isSpinning ? 360 : 0))
          .opacity(reduceMotion ? 0 : 1)
        Image(systemName: "bolt.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(LiquidGlassTokens.inkOverlay)
      }
      .frame(width: 34, height: 34)
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
          isSpinning = true
        }
      }
      .accessibilityHidden(true)
    }
  }
}
