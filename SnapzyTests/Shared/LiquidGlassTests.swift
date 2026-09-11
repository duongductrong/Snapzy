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

  func testToolbarButton_defaultsToStandardTreatment() {
    // Only toolbars that opted in should pick up glass; VideoEditor must keep its current look.
    let button = ToolbarButton(icon: "crop", isSelected: false) {}
    XCTAssertEqual(button.treatment, .standard)

    let glassButton = ToolbarButton(treatment: .glass, icon: "crop", isSelected: true) {}
    XCTAssertEqual(glassButton.treatment, .glass)
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
