//
//  WindowSurfacePaletteTests.swift
//  SnapzyTests
//
//  Unit tests for WindowSurfacePalette and ThemeManager appearance behavior.
//

import AppKit
import Combine
@testable import Snapzy
import XCTest

@MainActor
final class WindowSurfacePaletteTests: XCTestCase {
  private var cancellables: Set<AnyCancellable> = []

  override func tearDown() {
    cancellables.removeAll()
    super.tearDown()
  }

  func testBackgroundColorForAppearanceMode_returnsWindowBackgroundColor() {
    let systemColor = WindowSurfacePalette.backgroundColor(for: .system)
    let darkColor = WindowSurfacePalette.backgroundColor(for: .dark)
    let lightColor = WindowSurfacePalette.backgroundColor(for: .light)

    XCTAssertEqual(systemColor, NSColor.windowBackgroundColor)
    XCTAssertEqual(darkColor, NSColor.windowBackgroundColor)
    XCTAssertEqual(lightColor, NSColor.windowBackgroundColor)
  }

  func testBackgroundColorForAppearance_resolvesForAquaAndDarkAqua() throws {
    let aquaAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
    let darkAquaAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

    let lightResolved = WindowSurfacePalette.backgroundColor(for: aquaAppearance)
    let darkResolved = WindowSurfacePalette.backgroundColor(for: darkAquaAppearance)

    let lightRGB = try XCTUnwrap(lightResolved.usingColorSpace(.sRGB))
    let darkRGB = try XCTUnwrap(darkResolved.usingColorSpace(.sRGB))

    // Light appearance window background should be visibly brighter than dark appearance
    XCTAssertGreaterThan(lightRGB.brightnessComponent, darkRGB.brightnessComponent)
  }

  func testPaletteLightAndDarkBases_areValidAndDistinct() throws {
    let lightBase = WindowSurfacePalette.lightBase
    let darkBase = WindowSurfacePalette.darkBase

    let lightRGB = try XCTUnwrap(lightBase.usingColorSpace(.sRGB))
    let darkRGB = try XCTUnwrap(darkBase.usingColorSpace(.sRGB))

    XCTAssertGreaterThan(lightRGB.brightnessComponent, darkRGB.brightnessComponent)
  }

  func testThemeManagerNsAppearance_matchesPreferredAppearance() {
    let manager = ThemeManager.shared
    let original = manager.preferredAppearance
    defer { manager.preferredAppearance = original }

    manager.preferredAppearance = .system
    XCTAssertNil(manager.nsAppearance)

    manager.preferredAppearance = .light
    XCTAssertEqual(manager.nsAppearance?.name, .aqua)

    manager.preferredAppearance = .dark
    XCTAssertEqual(manager.nsAppearance?.name, .darkAqua)
  }

  func testThemeManager_preferredAppearanceMutation_publishesObjectWillChange() {
    let manager = ThemeManager.shared
    let original = manager.preferredAppearance
    defer { manager.preferredAppearance = original }

    let targetAppearance: AppearanceMode = (original == .dark) ? .light : .dark

    let expectation = expectation(description: "objectWillChange emitted on preferredAppearance change")
    manager.objectWillChange
      .first()
      .sink { _ in
        expectation.fulfill()
      }
      .store(in: &cancellables)

    manager.preferredAppearance = targetAppearance
    wait(for: [expectation], timeout: 2.0)
  }
}
