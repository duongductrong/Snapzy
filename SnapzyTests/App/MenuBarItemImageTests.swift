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

  /// Regression: importing a high-resolution transparent PNG (e.g. 256×256 hollow ring)
  /// must scale into the 18×18pt menu bar canvas rather than multiplying raw pixel dimensions.
  func testCustomStatusImage_scalesHighResTransparentPNGInto18ptCanvas() throws {
    let pixelSize = 256
    let sourceImage = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    sourceImage.lockFocus()
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()
    let ring = NSBezierPath()
    ring.appendOval(in: NSRect(x: 28, y: 28, width: 200, height: 200))
    ring.appendOval(in: NSRect(x: 84, y: 84, width: 88, height: 88))
    ring.windingRule = .evenOdd
    NSColor.black.setFill()
    ring.fill()
    sourceImage.unlockFocus()

    let tiff = try XCTUnwrap(sourceImage.tiffRepresentation)
    let bmp = try XCTUnwrap(NSBitmapImageRep(data: tiff))
    let png = try XCTUnwrap(bmp.representation(using: .png, properties: [:]))

    let customURL = try XCTUnwrap(MenuBarIconRenderer.shared.customIconURL)
    let backupData = try? Data(contentsOf: customURL)
    defer {
      if let backupData {
        try? backupData.write(to: customURL)
      } else {
        try? FileManager.default.removeItem(at: customURL)
      }
    }

    try FileManager.default.createDirectory(
      at: customURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try png.write(to: customURL, options: .atomic)

    let rendered = try XCTUnwrap(MenuBarIconRenderer.shared.statusImage(for: .custom))
    XCTAssertEqual(rendered.size, NSSize(width: 18, height: 18))
    XCTAssertTrue(rendered.isTemplate)

    let cgRendered = try XCTUnwrap(rendered.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let alphaBounds = try XCTUnwrap(
      MenuBarIconRenderer.alphaBoundingBox(of: cgRendered),
      "Rendered 18pt icon must contain visible ring pixels, not a blank hollow crop"
    )
    let occupancy = max(
      alphaBounds.width / CGFloat(cgRendered.width),
      alphaBounds.height / CGFloat(cgRendered.height)
    )
    XCTAssertGreaterThan(occupancy, 0.75, "Visible ring should fill ~89% of the 18pt canvas")
    XCTAssertLessThanOrEqual(occupancy, 1.0)
  }
}
