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

  static let defaultSize = CGSize(width: 1360, height: 840)
  static let minSize = CGSize(width: 1140, height: 680)

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
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )

    window.title = "Snapzy Design Studio"
    window.minSize = Self.minSize
    window.contentView = hostingView
    window.delegate = self
    window.isReleasedWhenClosed = false

    return window
  }

  func windowWillClose(_ notification: Notification) {
    let visibleWindows = NSApp.windows.filter { win in
      win.isVisible &&
      win !== self.window &&
      win.className != "NSStatusBarWindow" &&
      win.level == .normal
    }

    if visibleWindows.isEmpty && didElevateActivationPolicy {
      NSApp.setActivationPolicy(.accessory)
      didElevateActivationPolicy = false
      DiagnosticLogger.shared.log(.debug, .ui, "Activation policy restored to accessory after studio closed")
    }
  }
}
