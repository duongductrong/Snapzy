//
//  ScrollingCapturePreviewWindow.swift
//  Snapzy
//
//  Floating non-interactive preview window for scrolling capture sessions.
//

import AppKit
import SwiftUI

final class ScrollingCapturePreviewWindow: NSPanel {
  private var anchorRect: CGRect

  init(anchorRect: CGRect, model: ScrollingCaptureSessionModel) {
    self.anchorRect = anchorRect

    super.init(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    isFloatingPanel = true
    // Keep the preview above the interactive region overlay (.floating)
    // while still leaving the HUD on top at .popUpMenu.
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    hidesOnDeactivate = false
    ignoresMouseEvents = true
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    contentView = NSHostingView(rootView: ScrollingCapturePreviewView(model: model))

    let size = contentView?.fittingSize ?? CGSize(width: 244, height: 236)
    setContentSize(size)
    position(near: anchorRect, size: size)
  }

  func updateAnchorRect(_ rect: CGRect) {
    anchorRect = rect
    position(near: rect, size: frame.size)
  }

  private func position(near rect: CGRect, size: CGSize) {
    guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main else {
      return
    }

    let visible = screen.visibleFrame
    let preferredX = rect.maxX + 20
    let fallbackX = rect.minX - size.width - 20
    let x = preferredX + size.width <= visible.maxX - 12
      ? preferredX
      : max(visible.minX + 12, fallbackX)
    let y = min(max(visible.minY + 12, rect.midY - size.height / 2), visible.maxY - size.height - 12)
    setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: false)
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
