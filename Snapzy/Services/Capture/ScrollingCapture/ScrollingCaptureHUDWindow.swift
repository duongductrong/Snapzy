//
//  ScrollingCaptureHUDWindow.swift
//  Snapzy
//
//  Floating control HUD for scrolling capture sessions.
//

import AppKit
import Combine
import SwiftUI

final class ScrollingCaptureHUDWindow: NSPanel {
  private var anchorRect: CGRect
  private var modelObservation: AnyCancellable?

  init(
    anchorRect: CGRect,
    model: ScrollingCaptureSessionModel,
    onStart: @escaping () -> Void,
    onDone: @escaping () -> Void,
    onCancel: @escaping () -> Void,
    onToggleAutoScroll: @escaping () -> Void
  ) {
    self.anchorRect = anchorRect

    super.init(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    isFloatingPanel = true
    level = .popUpMenu
    isOpaque = false
    backgroundColor = .clear
    sharingType = .none
    hasShadow = true
    hidesOnDeactivate = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    appearance = ThemeManager.shared.nsAppearance
    contentView = NSHostingView(rootView: ScrollingCaptureHUDView(
      model: model,
      onStart: onStart,
      onDone: onDone,
      onCancel: onCancel,
      onToggleAutoScroll: onToggleAutoScroll
    ))

    modelObservation = model.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async {
        self?.refreshContentSize()
      }
    }

    refreshContentSize()
  }

  func updateAnchorRect(_ rect: CGRect) {
    anchorRect = rect
    refreshContentSize()
  }

  func refreshContentSize() {
    guard let contentView else { return }

    contentView.layoutSubtreeIfNeeded()
    let size = Self.resolvedContentSize(for: contentView.fittingSize)
    setContentSize(size)
    position(near: anchorRect, size: size)
  }

  nonisolated static func resolvedContentSize(for fittingSize: CGSize) -> CGSize {
    CGSize(
      width: max(180, fittingSize.width.rounded(.up)),
      height: max(34, fittingSize.height.rounded(.up))
    )
  }

  private func position(near rect: CGRect, size: CGSize) {
    guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main else {
      return
    }

    let visible = screen.visibleFrame
    let x = min(max(visible.minX + 12, rect.midX - size.width / 2), visible.maxX - size.width - 12)
    let y = min(visible.maxY - size.height - 12, rect.maxY + 16)
    setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
