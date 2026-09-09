//
//  PreferencesWindowController.swift
//  Snapzy
//
//  Dedicated window controller for Preferences/Settings window.
//  Directly manages NSWindow lifecycle, size constraints, and activation policy (.regular ↔ .accessory).
//

import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
  static let shared = PreferencesWindowController()

  private(set) var window: NSWindow?

  var isVisible: Bool { window?.isVisible ?? false }

  /// Default content size: wide enough for sidebar and grouped form cards,
  /// tall enough for long panes without excessive initial scrolling.
  static let defaultContentSize = CGSize(width: 800, height: 620)

  /// Minimum window size to prevent label truncation.
  static let minimumContentSize = CGSize(width: 700, height: 520)

  private var didElevateActivationPolicy = false

  override private init() {
    super.init()
  }

  /// Presents the Preferences window, optionally navigating directly to a specific tab.
  func show(tab: PreferencesTab? = nil) {
    if let tab {
      PreferencesNavigationState.shared.select(tab)
    }

    // Elevate to regular app so Snapzy appears in the top-left menu bar and takes key focus
    if !didElevateActivationPolicy {
      NSApp.setActivationPolicy(.regular)
      didElevateActivationPolicy = true
      DiagnosticLogger.shared.log(.debug, .ui, "Activation policy elevated for preferences window")
    }

    NSApp.activate(ignoringOtherApps: true)

    let window = self.window ?? makeWindow()
    self.window = window

    if !window.isVisible {
      window.center()
    }
    window.makeKeyAndOrderFront(nil)
    configureNonCollapsibleSidebar()
  }

  /// Closes the Preferences window.
  func close() {
    window?.performClose(nil)
  }

  /// Ensures the underlying AppKit split view item for the sidebar cannot be collapsed.
  private func configureNonCollapsibleSidebar() {
    DispatchQueue.main.async { [weak self] in
      guard let window = self?.window,
            let splitView = window.contentView?.firstDescendant(ofType: NSSplitView.self),
            let splitViewController = splitView.delegate as? NSSplitViewController,
            let sidebarItem = splitViewController.splitViewItems.first else {
        return
      }

      if sidebarItem.canCollapse {
        sidebarItem.canCollapse = false
      }
      if sidebarItem.isCollapsed {
        sidebarItem.isCollapsed = false
      }
    }
  }

  private func makeWindow() -> NSWindow {
    let created = NSWindow(
      contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    created.title = PreferencesNavigationState.shared.selectedTab.title
    created.delegate = self
    created.isReleasedWhenClosed = false
    created.level = .normal
    created.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
    created.contentMinSize = Self.minimumContentSize

    // Let the sidebar material run the full height under the titlebar behind the traffic lights
    created.titlebarAppearsTransparent = true

    let rootView = PreferencesView()
    created.contentView = NSHostingView(rootView: rootView)

    return created
  }

  // MARK: - NSWindowDelegate

  func windowWillClose(_ notification: Notification) {
    // Check if any visible normal windows remain
    let visibleWindows = NSApp.windows.filter { win in
      win.isVisible &&
      win !== self.window &&
      win.className != "NSStatusBarWindow" &&
      win.level == .normal
    }

    // If no normal windows remain, revert back to accessory (menu bar only) mode
    if visibleWindows.isEmpty && didElevateActivationPolicy {
      NSApp.setActivationPolicy(.accessory)
      didElevateActivationPolicy = false
      DiagnosticLogger.shared.log(.debug, .ui, "Activation policy restored to accessory after preferences closed")
    }
  }
}
