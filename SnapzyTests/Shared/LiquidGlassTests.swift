//
//  LiquidGlassTests.swift
//  SnapzyTests
//
//  Behavioural tests for Liquid Glass capability gating, appearance adaptation, and controls.
//

import AppKit
import SwiftUI
import XCTest

@testable import Snapzy

@MainActor
final class LiquidGlassTests: XCTestCase {

  // MARK: - Helpers

  /// Resolves a dynamic SwiftUI `Color` against a specific appearance.
  private func resolve(_ color: Color, in name: NSAppearance.Name) throws -> NSColor {
    let appearance = try XCTUnwrap(NSAppearance(named: name))
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
      resolved = NSColor(color).usingColorSpace(.sRGB)
    }
    return try XCTUnwrap(resolved)
  }

  // MARK: - Capabilities

  func testCapabilities_nativeGlassTracksHostOSAndForceFlag() {
    let expected: Bool
    if #available(macOS 26.0, *) {
      expected = !LiquidGlassCapabilities.forcesLegacyGlass
    } else {
      expected = false
    }
    XCTAssertEqual(LiquidGlassCapabilities.hasNativeLiquidGlass, expected)
  }

  func testCapabilities_backdropSubstrateOnlyCompensatesOnLegacyPath() {
    let resolved = LiquidGlassTokens.backdropSubstrate(LiquidGlassTokens.baseDarkness)
    if LiquidGlassCapabilities.hasNativeLiquidGlass {
      XCTAssertEqual(resolved, LiquidGlassTokens.baseDarkness, accuracy: 0.001)
    } else {
      // The AppKit vibrancy backdrop already darkens, so the substrate must be pulled back.
      XCTAssertLessThan(resolved, LiquidGlassTokens.baseDarkness)
      XCTAssertEqual(
        resolved,
        LiquidGlassTokens.baseDarkness * LiquidGlassTokens.fallbackSubstrateScale,
        accuracy: 0.001
      )
    }
  }

  // MARK: - Appearance Adaptation

  func testTokens_isDarkClassifiesBothAppearances() throws {
    XCTAssertTrue(LiquidGlassTokens.isDark(try XCTUnwrap(NSAppearance(named: .darkAqua))))
    XCTAssertFalse(LiquidGlassTokens.isDark(try XCTUnwrap(NSAppearance(named: .aqua))))
  }

  /// Regression: ink was hardcoded white, making glass buttons invisible in the Light theme
  /// of the Annotate window and the Preferences pane.
  func testTokens_primaryInkInvertsBetweenAppearances() throws {
    let onDark = try resolve(LiquidGlassTokens.inkPrimary, in: .darkAqua)
    let onLight = try resolve(LiquidGlassTokens.inkPrimary, in: .aqua)

    XCTAssertGreaterThan(onDark.brightnessComponent, 0.9, "Ink over Dark Aqua must be near-white")
    XCTAssertLessThan(onLight.brightnessComponent, 0.1, "Ink over Aqua must be near-black")
  }

  func testTokens_substrateAndVeilAreInverses() throws {
    let substrateOnDark = try resolve(LiquidGlassTokens.substrateFill, in: .darkAqua)
    let veilOnDark = try resolve(LiquidGlassTokens.veilFill, in: .darkAqua)
    XCTAssertLessThan(substrateOnDark.brightnessComponent, veilOnDark.brightnessComponent)

    let substrateOnLight = try resolve(LiquidGlassTokens.substrateFill, in: .aqua)
    let veilOnLight = try resolve(LiquidGlassTokens.veilFill, in: .aqua)
    XCTAssertGreaterThan(substrateOnLight.brightnessComponent, veilOnLight.brightnessComponent)
  }

  func testTokens_veilOpacityIsRestrainedInLightAppearance() {
    XCTAssertEqual(LiquidGlassTokens.veilOpacity(0.20, isDark: true), 0.20, accuracy: 0.001)
    XCTAssertLessThan(
      LiquidGlassTokens.veilOpacity(0.20, isDark: false),
      LiquidGlassTokens.veilOpacity(0.20, isDark: true)
    )
  }

  // MARK: - Highlight Resolution

  func testHighlight_noneSuppressesTheStroke() {
    // `.none` is what keeps the surface from stacking a second identical stroke on top of
    // `LiquidGlassRimBorder`'s specular pass.
    XCTAssertNil(LiquidGlassHighlight.none.stops)
    XCTAssertNotNil(LiquidGlassHighlight.specular.stops)
    XCTAssertNotNil(LiquidGlassHighlight.custom(top: 0.24, bottom: 0.08).stops)
  }

  // MARK: - Controls

  func testChromeEmphasis_overlayOutweighsStandard() {
    // Overlay chrome sits on screenshots and video frames, so it needs a heavier substrate than
    // chrome that sits on a window backdrop we control.
    XCTAssertGreaterThan(
      LiquidGlassChromeEmphasis.overlay.restingSubstrate,
      LiquidGlassChromeEmphasis.standard.restingSubstrate
    )
    XCTAssertGreaterThan(
      LiquidGlassChromeEmphasis.overlay.activeSubstrate,
      LiquidGlassChromeEmphasis.standard.activeSubstrate
    )
  }

  func testChromeEmphasis_activeStateIsAlwaysHeavierThanResting() {
    for emphasis in [LiquidGlassChromeEmphasis.standard, .overlay] {
      XCTAssertGreaterThan(emphasis.activeSubstrate, emphasis.restingSubstrate)
      XCTAssertGreaterThan(emphasis.activeTint, emphasis.restingTint)
    }
  }

  /// Regression: Quick Access card buttons are always visible, so their hover channel was first
  /// `substrate`/`tint` (knobs `.glassEffect` ignores) and then a fill behind the surface — which
  /// the native path does not sample either. The tint is the only channel it honours, so any
  /// emphasis used for persistent chrome has to move it.
  func testChromeEmphasis_persistentChromeSignalsHoverThroughTheTint() throws {
    let resting = try XCTUnwrap(LiquidGlassChromeEmphasis.overlay.glassTint(isActive: false))
    let active = try XCTUnwrap(LiquidGlassChromeEmphasis.overlay.glassTint(isActive: true))

    XCTAssertGreaterThan(
      try resolve(active, in: .aqua).alphaComponent,
      try resolve(resting, in: .aqua).alphaComponent,
      "Hover must deepen the overlay tint, which is the one state change native glass renders"
    )
  }

  /// Overlay chrome floats over an arbitrary capture, so it cannot let `.glassEffect` resolve
  /// light over a white screenshot and strand its white ink. It pins the material dark through
  /// the tint — the only knob that survives on the native path.
  func testChromeEmphasis_overlayGlassPinsItselfDarkInBothAppearances() throws {
    for appearance in [NSAppearance.Name.darkAqua, .aqua] {
      for isActive in [false, true] {
        let tint = try XCTUnwrap(LiquidGlassChromeEmphasis.overlay.glassTint(isActive: isActive))
        let resolved = try resolve(tint, in: appearance)

        XCTAssertLessThan(resolved.brightnessComponent, 0.1, "Overlay tint must be dark")
        // Heavy enough to carry white ink over a white screenshot, light enough that the surface
        // still reads as glass rather than a grey slab.
        XCTAssertGreaterThan(resolved.alphaComponent, 0.30)
        XCTAssertLessThan(resolved.alphaComponent, 0.55)
      }
    }
  }

  /// Toolbar chrome sits on a backdrop we control, so it takes no tint of its own and leaves the
  /// selection tint to the caller.
  func testChromeEmphasis_standardChromeTakesNoTintOfItsOwn() {
    XCTAssertNil(LiquidGlassChromeEmphasis.standard.glassTint(isActive: false))
    XCTAssertNil(LiquidGlassChromeEmphasis.standard.glassTint(isActive: true))
  }

  /// Overlay ink is deliberately *not* adaptive — its glass is pinned dark in both appearances.
  func testTokens_overlayInkStaysLightInBothAppearances() throws {
    for appearance in [NSAppearance.Name.darkAqua, .aqua] {
      let resolved = try resolve(LiquidGlassTokens.inkOverlay, in: appearance)
      XCTAssertGreaterThan(resolved.brightnessComponent, 0.9)
    }
  }

  // MARK: - Ink on Tinted Glass

  /// Regression: a tinted glass surface floods itself with the tint, so ink that follows the app
  /// appearance drew black glyphs on the Annotate toolbar's blue selected tools and on the Video
  /// Editor transport in Light theme. Ink on a tint resolves against the tint.
  func testTokens_inkOnDarkTintStaysLightInBothAppearances() throws {
    guard LiquidGlassCapabilities.hasNativeLiquidGlass else {
      // The composite drops `glassTint` outright, so there is no tint to resolve against.
      XCTAssertEqual(
        try resolve(LiquidGlassTokens.ink(onTint: .accentColor), in: .aqua),
        try resolve(LiquidGlassTokens.inkPrimary, in: .aqua)
      )
      return
    }

    for appearance in [NSAppearance.Name.darkAqua, .aqua] {
      for tint in [Color.accentColor, .blue, .red] {
        let resolved = try resolve(LiquidGlassTokens.ink(onTint: tint), in: appearance)
        XCTAssertGreaterThan(
          resolved.brightnessComponent,
          0.9,
          "A saturated tint is dark in both appearances, so its ink stays light"
        )
      }
    }
  }

  /// A bright tint — a yellow or orange accent — flips the ink instead of shipping white on yellow.
  func testTokens_inkOnBrightTintFlipsDark() throws {
    try XCTSkipUnless(LiquidGlassCapabilities.hasNativeLiquidGlass)

    let resolved = try resolve(LiquidGlassTokens.ink(onTint: .yellow), in: .aqua)
    XCTAssertLessThan(resolved.brightnessComponent, 0.2)
  }

  /// An untinted surface has nothing to resolve against, so the ink stays appearance-adaptive.
  func testTokens_inkWithoutTintFallsBackToTheAdaptiveInk() throws {
    for appearance in [NSAppearance.Name.darkAqua, .aqua] {
      XCTAssertEqual(
        try resolve(LiquidGlassTokens.ink(onTint: nil), in: appearance),
        try resolve(LiquidGlassTokens.inkPrimary, in: appearance)
      )
    }
  }

  func testLiquidGlassActionButton_actionDispatch() {
    var didCallAction = false
    let actionButton = LiquidGlassActionButton(
      title: "Save",
      icon: "square.and.arrow.down",
      trailingKey: "⌘S",
      emphasis: .primary,
      capsule: true
    ) {
      didCallAction = true
    }

    actionButton.action()
    XCTAssertTrue(didCallAction)
  }

  func testLiquidGlassSegmentedControl_selectionWritesThroughBinding() {
    var currentSelection = "Capture"
    let binding = Binding<String>(
      get: { currentSelection },
      set: { currentSelection = $0 }
    )

    let control = LiquidGlassSegmentedControl(
      items: ["Capture", "Record", "OCR"],
      selection: binding
    ) { item in
      Text(item)
    }

    XCTAssertEqual(control.items.count, 3)
    binding.wrappedValue = "Record"
    XCTAssertEqual(currentSelection, "Record")
  }

  func testLiquidGlassActionBar_dispatchesBothActions() {
    var cancelCalled = false
    var confirmCalled = false

    let actionBar = LiquidGlassActionBar(
      cancelTitle: "Skip",
      confirmTitle: "Next",
      confirmKey: "↩",
      isConfirmEnabled: true,
      isBusy: false,
      onCancel: { cancelCalled = true },
      onConfirm: { confirmCalled = true }
    )

    actionBar.onCancel?()
    actionBar.onConfirm()

    XCTAssertTrue(cancelCalled)
    XCTAssertTrue(confirmCalled)
  }
}
