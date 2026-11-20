//
//  MenuBarItemImageTests.swift
//  SnapzyTests
//
//  Unit tests for the glyph images handed to status bar menu items.
//

@testable import Snapzy
import XCTest

@MainActor
final class MenuBarItemImageTests: XCTestCase {
  func testSymbol_returnsImageForKnownSymbolAndNilForUnknownName() {
    XCTAssertNotNil(MenuBarItemImage.symbol("crop"))
    XCTAssertNotNil(MenuBarItemImage.symbol("text.viewfinder"))
    XCTAssertNil(MenuBarItemImage.symbol("definitely.not.a.real.symbol.name"))
  }

  /// macOS 27 stopped drawing symbol-backed image reps inside `NSMenu`, so the
  /// helper must hand the menu item something the menu drawing path accepts.
  func testSymbol_isBitmapBackedRatherThanSymbolBacked() {
    guard let image = MenuBarItemImage.symbol("crop") else {
      return XCTFail("Expected an image for a built-in symbol")
    }

    XCTAssertTrue(
      image.representations.contains { $0 is NSBitmapImageRep },
      "Menu item glyphs must be bitmap backed, got \(image.representations.map { NSStringFromClass(type(of: $0)) })"
    )
    XCTAssertFalse(
      image.representations.contains { NSStringFromClass(type(of: $0)).contains("Symbol") },
      "Menu item glyphs must not keep the SF Symbol rep"
    )
  }

  func testSymbol_keepsTemplateRendering() {
    let image = MenuBarItemImage.symbol("gear")
    XCTAssertTrue(image?.isTemplate == true, "Template tinting keeps glyphs legible in both appearances")
  }

  func testSymbol_keepsAccessibilityDescription() {
    let image = MenuBarItemImage.symbol("crop", accessibilityDescription: "Capture Area")
    XCTAssertEqual(image?.accessibilityDescription, "Capture Area")
  }

  /// Rasterizing at the wrong size either squashes the glyph or overflows the
  /// menu's image well, so the logical size must follow the symbol itself.
  func testSymbol_preservesNaturalGlyphSize() {
    let reference = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
    let image = MenuBarItemImage.symbol("crop")

    guard let reference, let image else {
      return XCTFail("Expected both the reference and helper images")
    }
    XCTAssertEqual(image.size.width, reference.size.width, accuracy: 0.5)
    XCTAssertEqual(image.size.height, reference.size.height, accuracy: 0.5)
  }

  /// A bitmap rep with no drawn content would render as blank space, which is
  /// the same user-visible failure as the missing glyph this replaces.
  func testSymbol_containsDrawnPixels() {
    guard let image = MenuBarItemImage.symbol("crop"),
          let rep = image.representations.first as? NSBitmapImageRep else {
      return XCTFail("Expected a bitmap representation")
    }

    var paintedPixels = 0
    for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
      for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
        if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
          paintedPixels += 1
        }
      }
    }
    XCTAssertGreaterThan(paintedPixels, 0, "Rasterized glyph is empty")
  }
}
