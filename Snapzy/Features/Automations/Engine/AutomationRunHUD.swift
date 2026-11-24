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
    let panel = panel ?? makePanel()
    self.panel = panel
    position(panel)
    panel.orderFrontRegardless()
    withAnimation(Self.appearSpring) { model.isShown = true }
  }

  private func hide() {
    guard let panel, model.isShown else { return }
    withAnimation(Self.disappearAnimation) { model.isShown = false }
    // Let the fade/scale finish before the window leaves the screen.
    hideTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 220_000_000)
      guard !Task.isCancelled, self?.model.isShown == false else { return }
      panel.orderOut(nil)
    }
  }

  private func cancelDisplayedRun() {
    guard let runID = displayedRunID else { return }
    AutomationRunner.shared.cancel(runID: runID)
  }

  private func makePanel() -> NSPanel {
    let size = NSSize(
      width: AutomationRunHUDView.width + AutomationRunHUDView.shadowPadding * 2,
      height: AutomationRunHUDView.height + AutomationRunHUDView.shadowPadding * 2
    )
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    // The shadow is drawn in SwiftUI under the dim layer; a window shadow would outline the
    // transparent shadow padding as a rectangle.
    panel.hasShadow = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    let hosting = NSHostingView(rootView: AutomationRunHUDView(model: model) { [weak self] in
      self?.cancelDisplayedRun()
    })
    hosting.frame = NSRect(origin: .zero, size: size)
    panel.contentView = hosting
    return panel
  }

  private func position(_ panel: NSPanel) {
    guard let screen = NSScreen.main else { return }
    let frame = screen.visibleFrame
    let size = panel.frame.size
    let inset = 40 - AutomationRunHUDView.shadowPadding
    panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + inset))
  }

  private static let appearSpring: Animation = .spring(response: 0.34, dampingFraction: 0.78)
  private static let disappearAnimation: Animation = .easeIn(duration: 0.18)

  // MARK: - View

  private struct AutomationRunHUDView: View {
    static let width: CGFloat = 340
    static let height: CGFloat = 60
    static let shadowPadding: CGFloat = 24

    @ObservedObject var model: Model
    let onCancel: () -> Void

    @Environment(\.liquidGlassRenderMode) private var renderMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

    private var usesNativeGlass: Bool {
      LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
    }

    private var shape: Capsule { Capsule(style: .continuous) }

    /// Clear glass over an arbitrary desktop needs a dark veil underneath for legibility.
    private var dimOpacity: Double {
      if reduceTransparency { return 0.78 }
      return usesNativeGlass ? 0.32 : 0.22
    }

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
              .foregroundStyle(LiquidGlassTokens.inkOverlay.opacity(0.66))
              .lineLimit(1)
              .transition(.opacity.combined(with: .move(edge: .bottom)))
              .id(model.step)
          }
        }
        .animation(LiquidGlassTokens.settleSpring, value: model.step)
        Spacer(minLength: 8)
        Button(L10n.Common.cancel, action: onCancel)
          .buttonStyle(.liquidGlass(emphasis: .secondary, capsule: true))
      }
      .liquidGlassGroup(spacing: 8)
      .padding(.leading, 12)
      .padding(.trailing, 10)
      .frame(width: Self.width, height: Self.height)
      // Shadow rides on the dim layer: compositing the glass itself would stop it sampling
      // the backdrop.
      .background(
        shape.fill(Color.black.opacity(dimOpacity))
          .shadow(color: .black.opacity(usesNativeGlass ? 0.28 : 0.45), radius: 16, y: 6)
      )
      .liquidGlassSurface(
        shape: shape,
        substrate: 0.3,
        layer: .backdrop,
        nativeVariant: .clear
      )
      .overlay {
        if !usesNativeGlass {
          shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
        }
      }
      // Overlay chrome stays dark-on-light-ink regardless of the system appearance.
      .environment(\.colorScheme, .dark)
      .scaleEffect(model.isShown || reduceMotion ? 1 : 0.86, anchor: .bottom)
      .offset(y: model.isShown || reduceMotion ? 0 : 10)
      .opacity(model.isShown ? 1 : 0)
      .padding(Self.shadowPadding)
      .accessibilityElement(children: .combine)
    }
  }

  /// Glass orb with a sweeping accent arc around the automation glyph.
  private struct AutomationRunHUDIndicator: View {
    let reduceMotion: Bool
    @State private var isSpinning = false

    var body: some View {
      ZStack {
        Circle()
          .fill(Color.white.opacity(0.08))
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
          .opacity(reduceMotion ? 0.9 : 1)
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
