//
//  HistoryFloatingPanelController.swift
//  Snapzy
//
//  Controller for managing the floating history panel lifecycle
//

import AppKit
import Foundation
import SwiftUI

/// Manages the floating history panel with animated transitions
@MainActor
final class HistoryFloatingPanelController {

  var onPanelDidResignKey: (() -> Void)?

  private enum VisibilityState {
    case hidden
    case showing
    case visible
    case hiding
  }

  private struct Presentation {
    let content: AnyView
    let size: CGSize
    let position: HistoryPanelPosition
  }

  private var panel: HistoryFloatingPanel?
  private var position: HistoryPanelPosition = .topCenter
  private let padding: CGFloat = 20
  private var state: VisibilityState = .hidden
  private var pendingPresentation: Presentation?
  private var pendingHide = false
  private var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  /// Show SwiftUI content in floating panel with a soft fade + slide animation.
  func show<Content: View>(_ content: Content, size: CGSize, position: HistoryPanelPosition) {
    requestShow(
      Presentation(content: AnyView(content), size: size, position: position)
    )
  }

  /// Update panel content with new SwiftUI view
  func updateContent<Content: View>(_ content: Content) {
    guard let panel = panel else { return }
    installContent(AnyView(content), on: panel, size: panel.frame.size)
  }

  /// Resize panel and reposition
  func updateSize(_ size: CGSize) {
    guard let panel = panel, state != .hiding else { return }
    let screen = ScreenUtility.activeScreen()
    let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
    let targetFrame = NSRect(origin: origin, size: size)
    panel.setFrame(targetFrame, display: true, animate: false)
  }

  /// Update panel position
  func updatePosition(_ newPosition: HistoryPanelPosition) {
    position = newPosition
    repositionPanel()
  }

  /// Hide panel with fade animation
  func hide() {
    pendingPresentation = nil

    switch state {
    case .hidden, .hiding:
      return
    case .showing:
      pendingHide = true
    case .visible:
      performHide()
    }
  }

  /// Check if panel is onscreen or transitioning.
  var isVisible: Bool {
    state != .hidden
  }

  /// Check if panel is intended to stay open.
  var isPresenting: Bool {
    state == .showing || state == .visible
  }

  func focusPanel() {
    guard let panel else { return }
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  private func requestShow(_ presentation: Presentation) {
    pendingHide = false

    switch state {
    case .hidden:
      performShow(presentation)
    case .showing:
      pendingPresentation = presentation
    case .visible:
      applyPresentation(presentation, animated: !reduceMotion)
    case .hiding:
      pendingPresentation = presentation
    }
  }

  private func performShow(_ presentation: Presentation) {
    position = presentation.position
    let targetFrame = frame(for: presentation.size, position: presentation.position)
    let panel = HistoryFloatingPanel(contentRect: targetFrame)
    panel.onDidResignKey = { [weak self] in
      self?.handlePanelDidResignKey()
    }
    installContent(presentation.content, on: panel, size: presentation.size)

    self.panel = panel
    state = .showing

    if reduceMotion {
      panel.alphaValue = 0
      panel.setFrame(targetFrame, display: false)
      panel.makeKeyAndOrderFront(nil)
      NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.18
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.animator().alphaValue = 1
      }, completionHandler: { [weak self] in
        MainActor.assumeIsolated {
          self?.finishShow()
        }
      })
      return
    }

    panel.alphaValue = 0
    panel.setFrame(transitionFrame(for: targetFrame, isShowing: true), display: false)
    panel.makeKeyAndOrderFront(nil)

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.22
      context.timingFunction = CAMediaTimingFunction(
        controlPoints: 0.22, 1.0, 0.36, 1.0
      )
      panel.animator().setFrame(targetFrame, display: true)
      panel.animator().alphaValue = 1
    }, completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        self?.finishShow()
      }
    })
  }

  private func finishShow() {
    state = .visible

    if pendingHide {
      pendingHide = false
      performHide()
      return
    }

    if let pendingPresentation {
      self.pendingPresentation = nil
      requestShow(pendingPresentation)
    }
  }

  private func performHide() {
    guard let panel else {
      state = .hidden
      return
    }

    state = .hiding
    let targetFrame = reduceMotion ? panel.frame : transitionFrame(for: panel.frame, isShowing: false)

    NSAnimationContext.runAnimationGroup({ context in
      context.duration = reduceMotion ? 0.14 : 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      if !reduceMotion {
        panel.animator().setFrame(targetFrame, display: true)
      }
      panel.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      panel.close()
      MainActor.assumeIsolated {
        self?.panel = nil
        self?.state = .hidden
        self?.resumePendingPresentationIfNeeded()
      }
    })
  }

  private func resumePendingPresentationIfNeeded() {
    guard let pendingPresentation else { return }
    self.pendingPresentation = nil
    performShow(pendingPresentation)
  }

  private func applyPresentation(_ presentation: Presentation, animated: Bool) {
    guard let panel else { return }
    position = presentation.position
    installContent(presentation.content, on: panel, size: presentation.size)

    let targetFrame = frame(for: presentation.size, position: presentation.position)
    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        panel.animator().setFrame(targetFrame, display: true)
      }
    } else {
      panel.setFrame(targetFrame, display: true)
    }
  }

  private func installContent(_ content: AnyView, on panel: HistoryFloatingPanel, size: CGSize) {
    let hostingView = NSHostingView(rootView: content)
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor

    let containerView = HistoryFloatingContainerView()
    containerView.frame = NSRect(origin: .zero, size: size)
    containerView.autoresizingMask = [.width, .height]
    containerView.addSubview(hostingView)

    NSLayoutConstraint.activate([
      hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
      hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
    ])

    panel.contentView = containerView
    panel.applyCornerRadius(HistoryFloatingPanel.cornerRadius)
    panel.invalidateShadow()
  }

  private func frame(for size: CGSize, position: HistoryPanelPosition) -> NSRect {
    let screen = ScreenUtility.activeScreen()
    let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
    return NSRect(origin: origin, size: size)
  }

  private func transitionFrame(for targetFrame: NSRect, isShowing: Bool) -> NSRect {
    let deltaY: CGFloat = position == .topCenter ? 18 : -18
    let direction = isShowing ? deltaY : -deltaY
    var frame = targetFrame
    frame.origin.y += direction
    return frame
  }

  private func handlePanelDidResignKey() {
    guard state == .showing || state == .visible else { return }
    onPanelDidResignKey?()
  }

  private func repositionPanel() {
    guard let panel = panel, state != .hiding else { return }
    let size = panel.frame.size
    let screen = ScreenUtility.activeScreen()
    let origin = position.calculateOrigin(for: size, on: screen, padding: padding)

    if reduceMotion {
      panel.setFrameOrigin(origin)
    } else {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.25
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        panel.animator().setFrameOrigin(origin)
      }
    }
  }
}

private final class HistoryFloatingContainerView: NSVisualEffectView {
  private var defaultsObserver: NSObjectProtocol?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configureLayer()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    if let defaultsObserver {
      NotificationCenter.default.removeObserver(defaultsObserver)
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyStyle()
  }

  private func configureLayer() {
    state = .active
    blendingMode = .behindWindow
    wantsLayer = true
    defaultsObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.applyStyle()
    }
    applyStyle()
  }

  private func applyStyle() {
    let style = HistoryBackgroundStyle.currentStoredStyle()
    layer?.cornerRadius = HistoryFloatingPanel.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true

    switch style {
    case .hud:
      material = .hudWindow
      layer?.backgroundColor = resolvedHUDBackgroundColor.cgColor
    case .solid:
      material = .underWindowBackground
      layer?.backgroundColor = resolvedSolidBackgroundColor.cgColor
    }
  }

  private var resolvedHUDBackgroundColor: NSColor {
    switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .darkAqua:
      return NSColor(
        srgbRed: 0.07,
        green: 0.08,
        blue: 0.11,
        alpha: 0.12
      )
    default:
      return NSColor(
        srgbRed: 1.0,
        green: 1.0,
        blue: 1.0,
        alpha: 0.14
      )
    }
  }

  private var resolvedSolidBackgroundColor: NSColor {
    switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .darkAqua:
      return NSColor(
        srgbRed: 0.09,
        green: 0.10,
        blue: 0.14,
        alpha: 0.94
      )
    default:
      return NSColor(
        srgbRed: 0.95,
        green: 0.96,
        blue: 0.98,
        alpha: 0.96
      )
    }
  }
}
