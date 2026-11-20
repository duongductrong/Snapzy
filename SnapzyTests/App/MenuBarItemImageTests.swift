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

  /// macOS 27 hides menu images by policy and hands apps `preferredImageVisibility` as
  /// the opt-out. The helper must set it on the entries that carry a glyph, and leave
  /// separators and text-only rows alone. Below macOS 27 the property does not exist,
  /// so the call has to be a no-op that still cannot crash.
  func testEnableIcons_marksGlyphBearingItemsVisible() {
    let submenu = NSMenu(title: "Sub")
    let child = NSMenuItem(title: "Child", action: nil, keyEquivalent: "")
    child.image = MenuBarItemImage.symbol("crop")
    submenu.addItem(child)

    let parent = NSMenuItem(title: "Parent", action: nil, keyEquivalent: "")
    parent.image = MenuBarItemImage.symbol("gear")
    parent.submenu = submenu

    let menu = NSMenu()
    menu.addItem(parent)
    menu.addItem(.separator())
    let textOnly = NSMenuItem(title: "Text only", action: nil, keyEquivalent: "")
    menu.addItem(textOnly)

    MenuBarItemImage.enableIcons(in: menu)

    if rawImageVisibility(of: parent) != nil {
      XCTAssertEqual(rawImageVisibility(of: parent), 1, "Rows with a glyph need the documented opt-out")
      XCTAssertEqual(rawImageVisibility(of: child), 1, "Submenu rows need the same opt-out")
      XCTAssertEqual(rawImageVisibility(of: textOnly), 0, "Rows without a glyph stay untouched")
    } else {
      XCTAssertNil(rawImageVisibility(of: child), "Below macOS 27 there is no such property, so the call must leave it alone")
    }
  }

  /// Reads `preferredImageVisibility` the way the helper writes it. The property is not
  /// in the macOS 26 SDK headers CI builds against, so naming it directly would not
  /// compile there; 0 is `.automatic`, 1 is `.visible`.
  private func rawImageVisibility(of item: NSMenuItem) -> Int? {
    guard item.responds(to: Selector(("preferredImageVisibility"))) else { return nil }
    return (item.value(forKey: "preferredImageVisibility") as? NSNumber)?.intValue
  }

  func testEnableIcons_acceptsNilAndEmptyMenus() {
    MenuBarItemImage.enableIcons(in: nil)
    MenuBarItemImage.enableIcons(in: NSMenu())
  }
}
