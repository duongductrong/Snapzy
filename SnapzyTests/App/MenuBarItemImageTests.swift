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

  /// The hiding policy keys off the representation: a bitmap rep keeps drawing on
  /// SDK 26.2-linked release builds even with the setting off, so glyphs must stay
  /// symbol-backed and let `preferredImageVisibility` decide visibility.
  func testSymbol_isSymbolBackedNotRasterized() {
    guard let image = MenuBarItemImage.symbol("crop") else {
      return XCTFail("Expected an image for a built-in symbol")
    }

    XCTAssertFalse(
      image.representations.contains { $0 is NSBitmapImageRep },
      "Rasterizing would bypass the off-by-default setting on release builds, got \(image.representations.map { NSStringFromClass(type(of: $0)) })"
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

  /// Menus size the image well from the glyph's natural size, so the helper must not
  /// rescale the symbol it hands back.
  func testSymbol_preservesNaturalGlyphSize() {
    let reference = NSImage(systemSymbolName: "crop", accessibilityDescription: nil)
    let image = MenuBarItemImage.symbol("crop")

    guard let reference, let image else {
      return XCTFail("Expected both the reference and helper images")
    }
    XCTAssertEqual(image.size.width, reference.size.width, accuracy: 0.5)
    XCTAssertEqual(image.size.height, reference.size.height, accuracy: 0.5)
  }

  /// macOS 27 hides menu images by policy and hands apps `preferredImageVisibility` as
  /// the opt-out. With the setting on, the helper must set it on the entries that carry
  /// a glyph, and leave separators and text-only rows alone. Below macOS 27 the property
  /// does not exist, so the call has to be a no-op that still cannot crash.
  func testEnableIcons_marksGlyphBearingItemsVisible() {
    let previous = MenuBarCustomizationStore.shared.showItemIcons
    MenuBarCustomizationStore.shared.setShowItemIcons(true)
    defer { MenuBarCustomizationStore.shared.setShowItemIcons(previous) }

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

  /// With the setting off, AppKit's macOS 27 default must stay in charge: rows keep
  /// `.automatic` (0) instead of being forced visible.
  func testEnableIcons_settingOff_leavesRowsAutomatic() {
    let previous = MenuBarCustomizationStore.shared.showItemIcons
    MenuBarCustomizationStore.shared.setShowItemIcons(false)
    defer { MenuBarCustomizationStore.shared.setShowItemIcons(previous) }

    let item = NSMenuItem(title: "Row", action: nil, keyEquivalent: "")
    item.image = MenuBarItemImage.symbol("crop")
    let menu = NSMenu()
    menu.addItem(item)

    MenuBarItemImage.enableIcons(in: menu)

    XCTAssertEqual(
      rawImageVisibility(of: item) ?? 0,
      0,
      "The off-by-default setting must not opt rows out of AppKit's hiding policy"
    )
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
