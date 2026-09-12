//
//  LiquidGlassPlaygroundWindowController.swift
//  Snapzy
//
//  Window controller for opening the interactive Liquid Glass Playground & Version Inspector.
//

import AppKit
import SwiftUI

@MainActor
final class LiquidGlassPlaygroundWindowController: NSObject, NSWindowDelegate {
  static let shared = LiquidGlassPlaygroundWindowController()

  private(set) var window: NSWindow?

  var isVisible: Bool { window?.isVisible ?? false }

  static let defaultSize = CGSize(width: 960, height: 720)
  static let minSize = CGSize(width: 820, height: 600)

  private var didElevateActivationPolicy = false

  override private init() {
    super.init()
  }

  func show() {
    #if !DEBUG
    return
    #else
    if !didElevateActivationPolicy {
      NSApp.setActivationPolicy(.regular)
      didElevateActivationPolicy = true
    }

    NSApp.activate(ignoringOtherApps: true)

    let window = self.window ?? makeWindow()
    self.window = window

    if !window.isVisible {
      window.center()
    }
    window.makeKeyAndOrderFront(nil)
    #endif
  }

  func close() {
    window?.performClose(nil)
  }

  private func makeWindow() -> NSWindow {
    let hostingView = NSHostingView(rootView: LiquidGlassPlaygroundView())
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: Self.defaultSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    window.title = "Bản Điều Chỉnh Liquid Glass (macOS 13–15 vs 26+)"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .visible
    window.minSize = Self.minSize
    window.contentView = hostingView
    window.delegate = self
    window.isReleasedWhenClosed = false

    return window
  }

  func windowWillClose(_ notification: Notification) {
    // Keep window reference for faster reopen, or let it stay ready
  }
}
