//
//  LiquidGlassToggleRenderTests.swift
//  SnapzyTests
//
//  Regression: the Liquid Glass preference must switch rendering live, in both directions.
//

import AppKit
import CryptoKit
import SwiftUI
import XCTest

@testable import Snapzy

@MainActor
final class LiquidGlassToggleRenderTests: XCTestCase {

  /// Regression: `LiquidGlassSurfaceModifier` resolved the native/legacy path through the static
  /// `LiquidGlassCapabilities.usesNativeGlass(for:)`, which reads `UserDefaults` without a SwiftUI
  /// dependency. Flipping the preference wrote the setting but never invalidated the view, so the
  /// surface stayed on whichever path it first rendered until something else forced a redraw (or
  /// the app relaunched). The modifier now observes the preference through `@AppStorage` and passes
  /// it into the resolution function, so this test mounts a live hosting view and asserts that the
  /// rendered pixels change on, off, and back on.
  func testToggleSwitchesGlassSurfaceRenderingLive() throws {
    try XCTSkipUnless(
      LiquidGlassCapabilities.isSystemSupported,
      "Native Liquid Glass requires macOS 26+; the preference cannot change rendering below that."
    )

    let defaults = UserDefaults.standard
    let originalPref = defaults.object(forKey: PreferencesKeys.useLiquidGlass)
    let originalRuntime = LiquidGlassCapabilities.runtimeLegacyOverride
    defer {
      defaults.set(originalPref, forKey: PreferencesKeys.useLiquidGlass)
      LiquidGlassCapabilities.runtimeLegacyOverride = originalRuntime
    }

    defaults.set(true, forKey: PreferencesKeys.useLiquidGlass)
    LiquidGlassCapabilities.runtimeLegacyOverride = nil

    let host = NSHostingView(
      rootView: ZStack {
        Color.white
        Text("hi")
          .padding()
          .liquidGlassSurface(shape: Capsule())
      }
    )
    host.frame = NSRect(x: 0, y: 0, width: 220, height: 80)
    let window = NSWindow(
      contentRect: host.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.close() }

    drainRunLoop(0.6)
    let nativeSnapshot = snapshotHash(host)

    // OFF: the composite fallback must take over immediately.
    defaults.set(false, forKey: PreferencesKeys.useLiquidGlass)
    drainRunLoop(0.5)
    let legacySnapshot = snapshotHash(host)
    drainRunLoop(0.3)
    XCTAssertEqual(
      legacySnapshot,
      snapshotHash(host),
      "The composite fallback must render deterministically"
    )
    XCTAssertNotEqual(
      legacySnapshot,
      nativeSnapshot,
      "Turning Liquid Glass off must remove the native effect without a relaunch"
    )

    // ON: native glass must come back on the same view instance.
    defaults.set(true, forKey: PreferencesKeys.useLiquidGlass)
    drainRunLoop(0.5)
    XCTAssertNotEqual(
      snapshotHash(host),
      legacySnapshot,
      "Turning Liquid Glass back on must re-apply the native effect without a relaunch"
    )
  }

  // MARK: - Helpers

  private func drainRunLoop(_ interval: TimeInterval) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: interval))
  }

  private func snapshotHash(_ view: NSView) -> String {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      return "unavailable"
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
      return "unavailable"
    }
    return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
  }
}
