//
//  DesktopIconManager.swift
//  Snapzy
//
//  Service to temporarily hide desktop icons and widgets via system preferences
//

import AppKit
import Foundation

@MainActor
final class DesktopIconManager {
  static let shared = DesktopIconManager()

  private(set) var isHidden = false
  private var previousWidgetHideValue: Bool?

  private init() {}

  // MARK: - Public API

  /// Hide desktop icons and widgets, then wait for system to apply changes
  func hideIcons() async {
    guard !isHidden else { return }

    previousWidgetHideValue = readWidgetHideState()

    setCreateDesktop(false)
    setWidgetsHidden(true)

    restartFinder()
    restartDock()

    // Wait for BOTH Finder and Dock to restart (not just Finder)
    await waitForProcessesReady()

    // Stabilization delay — WallpaperAgent needs time to re-render wallpaper
    // after Dock restart. Without this, ScreenCaptureKit captures a black background.
    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

    isHidden = true
  }

  /// Restore desktop icons and widgets, then wait for system to apply changes
  func restoreIcons() async {
    guard isHidden else { return }

    setCreateDesktop(true)
    setWidgetsHidden(previousWidgetHideValue ?? false)

    restartFinder()
    restartDock()

    await waitForProcessesReady()
    isHidden = false
  }

  /// Synchronous restore for cleanup/error paths — fires and forgets
  func restoreIconsSync() {
    guard isHidden else { return }

    setCreateDesktop(true)
    setWidgetsHidden(previousWidgetHideValue ?? false)

    restartFinder()
    restartDock()
    isHidden = false
  }

  // MARK: - Desktop Icons (Finder)

  private func setCreateDesktop(_ value: Bool) {
    runDefaults(["write", "com.apple.finder", "CreateDesktop", "-bool", value ? "true" : "false"])
  }

  private func restartFinder() {
    runProcess("/usr/bin/killall", arguments: ["Finder"])
  }

  // MARK: - Widgets (WindowManager, macOS Sonoma 14.0+)

  private func readWidgetHideState() -> Bool? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["read", "com.apple.WindowManager", "StandardHideWidgets"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try? process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return output == "1"
  }

  private func setWidgetsHidden(_ hidden: Bool) {
    runDefaults(["write", "com.apple.WindowManager", "StandardHideWidgets", "-bool", hidden ? "true" : "false"])
  }

  private func restartDock() {
    runProcess("/usr/bin/killall", arguments: ["Dock"])
  }

  // MARK: - Helpers

  private func runDefaults(_ arguments: [String]) {
    runProcess("/usr/bin/defaults", arguments: arguments)
  }

  private func runProcess(_ path: String, arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    try? process.run()
    process.waitUntilExit()
  }

  // MARK: - Wait for Process Restart

  /// Poll until both Finder and Dock are running after being killed
  private func waitForProcessesReady() async {
    let maxAttempts = 30 // 30 × 100ms = 3s max
    for _ in 0..<maxAttempts {
      let apps = NSWorkspace.shared.runningApplications
      let finderRunning = apps.contains { $0.bundleIdentifier == "com.apple.finder" }
      let dockRunning = apps.contains { $0.bundleIdentifier == "com.apple.dock" }

      if finderRunning && dockRunning { return }

      try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }
  }
}
