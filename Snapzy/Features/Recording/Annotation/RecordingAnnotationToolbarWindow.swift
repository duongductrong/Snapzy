//
//  RecordingAnnotationToolbarWindow.swift
//  Snapzy
//
//  Floating NSWindow for annotation tools during recording
//  Draggable with auto-snap to corners, auto horizontal/vertical layout
//  Uses native NSWindow drag (isMovableByWindowBackground) for smooth performance
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingAnnotationToolbarWindow: NSWindow {

  private let annotationState: RecordingAnnotationState
  private var hostingView: NSHostingView<AnyView>?
  private var effectView: NSVisualEffectView?
  private var direction: AnnotationToolbarDirection = .horizontal
  private var enabledCancellable: AnyCancellable?
  private var isDragging = false

  init(annotationState: RecordingAnnotationState) {
    self.annotationState = annotationState

    super.init(
      contentRect: .zero,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    configureWindow()
    rebuildContent()
    positionDefault()
    observeToggle()
  }

  // MARK: - Configuration

  private func configureWindow() {
    isOpaque = false
    backgroundColor = .clear
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    hasShadow = false
    isReleasedWhenClosed = false
    appearance = ThemeManager.shared.nsAppearance
    // Enable native window dragging — smooth, hardware-accelerated
    isMovableByWindowBackground = true
  }

  private func observeToggle() {
    enabledCancellable = annotationState.$isAnnotationEnabled
      .receive(on: RunLoop.main)
      .sink { [weak self] enabled in
        if enabled {
          self?.orderFrontRegardless()
        } else {
          self?.orderOut(nil)
        }
      }
  }

  // MARK: - Content

  private func rebuildContent() {
    let view = RecordingAnnotationToolbarView(
      state: annotationState,
      direction: direction
    )

    let themed = view.preferredColorScheme(ThemeManager.shared.systemAppearance)
    let hosting = NSHostingView(rootView: AnyView(themed))
    hosting.translatesAutoresizingMaskIntoConstraints = false

    let effect = NSVisualEffectView()
    effect.material = .hudWindow
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.wantsLayer = true
    effect.layer?.cornerRadius = ToolbarConstants.toolbarCornerRadius
    effect.layer?.masksToBounds = true

    hosting.layer?.backgroundColor = .clear
    effect.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.topAnchor.constraint(equalTo: effect.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
      hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
    ])

    let fittingSize = hosting.fittingSize
    effect.frame = CGRect(origin: .zero, size: fittingSize)

    contentView = effect
    hostingView = hosting
    effectView = effect
    setContentSize(fittingSize)
  }

  // MARK: - Positioning

  private func positionDefault() {
    guard let screen = NSScreen.main else { return }
    let sf = screen.visibleFrame
    let size = self.frame.size
    let x = sf.midX - size.width / 2
    let y = sf.minY + 60
    setFrameOrigin(CGPoint(x: x, y: y))
  }

  // MARK: - Native Drag Detection (for snap-on-release)

  override func mouseDown(with event: NSEvent) {
    isDragging = true
    super.mouseDown(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    if isDragging {
      isDragging = false
      snapToNearestZone()
    }
    super.mouseUp(with: event)
  }

  // MARK: - Snap + Direction

  private func snapToNearestZone() {
    guard let screen = NSScreen.main else { return }
    let sf = screen.visibleFrame
    let center = CGPoint(x: frame.midX, y: frame.midY)

    let relX = (center.x - sf.minX) / sf.width
    let relY = (center.y - sf.minY) / sf.height

    let newDirection: AnnotationToolbarDirection
    if relX < 0.15 && relY > 0.3 && relY < 0.7 {
      newDirection = .vertical
    } else if relX > 0.85 && relY > 0.3 && relY < 0.7 {
      newDirection = .vertical
    } else {
      newDirection = .horizontal
    }

    if newDirection != direction {
      direction = newDirection
      rebuildContent()
    }

    let margin: CGFloat = 20
    let size = frame.size
    var snapX: CGFloat
    var snapY: CGFloat

    if relX < 0.5 {
      snapX = sf.minX + margin
    } else {
      snapX = sf.maxX - size.width - margin
    }

    if relY < 0.35 {
      snapY = sf.minY + margin
    } else if relY > 0.65 {
      snapY = sf.maxY - size.height - margin
    } else {
      snapY = center.y - size.height / 2
    }

    snapX = max(sf.minX + margin, min(snapX, sf.maxX - size.width - margin))
    snapY = max(sf.minY + margin, min(snapY, sf.maxY - size.height - margin))

    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.25
      ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      self.animator().setFrameOrigin(CGPoint(x: snapX, y: snapY))
    }
  }

  override var canBecomeKey: Bool { true }
}
