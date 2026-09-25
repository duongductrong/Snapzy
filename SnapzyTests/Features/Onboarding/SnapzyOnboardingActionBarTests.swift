//
//  SnapzyOnboardingActionBarTests.swift
//  SnapzyTests
//
//  Behavioural coverage for the shared onboarding navigation actions.
//

import AppKit
import CryptoKit
@testable import Snapzy
import SwiftUI
import XCTest

@MainActor
final class SnapzyOnboardingActionBarTests: XCTestCase {
  func testDispatchesSkipAndContinueActions() {
    var didSkip = false
    var didContinue = false

    let actionBar = SnapzyOnboardingActionBar(
      skipTitle: "Skip",
      continueTitle: "Continue",
      continueKey: "↩",
      onSkip: { didSkip = true },
      onContinue: { didContinue = true }
    )

    actionBar.onSkip?()
    actionBar.onContinue()

    XCTAssertTrue(didSkip)
    XCTAssertTrue(didContinue)
  }

  func testPreferenceSwitchesActionBarBetweenNativeAndFallbackRendering() throws {
    try XCTSkipUnless(
      LiquidGlassCapabilities.isSystemSupported,
      "Native onboarding Liquid Glass requires macOS 26+."
    )

    let defaults = UserDefaults.standard
    let originalPreference = defaults.object(forKey: PreferencesKeys.useLiquidGlass)
    let originalRuntimeOverride = LiquidGlassCapabilities.runtimeLegacyOverride
    defer {
      defaults.set(originalPreference, forKey: PreferencesKeys.useLiquidGlass)
      LiquidGlassCapabilities.runtimeLegacyOverride = originalRuntimeOverride
    }

    defaults.set(true, forKey: PreferencesKeys.useLiquidGlass)
    LiquidGlassCapabilities.runtimeLegacyOverride = nil

    let host = NSHostingView(
      rootView: ZStack {
        LinearGradient(
          colors: [.indigo, .black],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        SnapzyOnboardingActionBar(
          skipTitle: "Skip",
          continueTitle: "Finish",
          continueKey: "↩",
          onSkip: {},
          onContinue: {}
        )
      }
      .environment(\.colorScheme, .dark)
    )
    host.frame = NSRect(x: 0, y: 0, width: 320, height: 96)

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

    defaults.set(false, forKey: PreferencesKeys.useLiquidGlass)
    drainRunLoop(0.5)
    let fallbackSnapshot = snapshotHash(host)

    XCTAssertNotEqual(
      fallbackSnapshot,
      nativeSnapshot,
      "Disabling Liquid Glass must replace the native onboarding buttons with the fallback group."
    )
  }

  func testLiquidGlassModesPreserveOriginalCompactGeometry() {
    let legacySize = fittedSize(for: .legacy)

    XCTAssertEqual(legacySize.height, 40, accuracy: 0.5)

    guard LiquidGlassCapabilities.isSystemSupported else { return }

    let nativeSize = fittedSize(for: .native)
    XCTAssertEqual(nativeSize.height, 40, accuracy: 0.5)
    XCTAssertEqual(nativeSize.width, legacySize.width, accuracy: 0.5)
  }

  private func fittedSize(for renderMode: LiquidGlassRenderMode) -> NSSize {
    let host = NSHostingView(
      rootView: SnapzyOnboardingActionBar(
        skipTitle: "Skip",
        continueTitle: "Continue",
        continueKey: "↩",
        onSkip: {},
        onContinue: {}
      )
      .environment(\.liquidGlassRenderMode, renderMode)
    )
    host.layoutSubtreeIfNeeded()
    return host.fittingSize
  }

  private func drainRunLoop(_ interval: TimeInterval) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: interval))
  }

  private func snapshotHash(_ view: NSView) -> String {
    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      return "unavailable"
    }
    view.cacheDisplay(in: view.bounds, to: representation)
    guard let data = representation.representation(using: .png, properties: [:]) else {
      return "unavailable"
    }
    return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
  }
}
