//
//  MenuBarItemImage.swift
//  Snapzy
//
//  SF Symbol images for status bar menu entries.
//

import AppKit

/// Builds the glyph shown to the left of a menu item title, and asks menus to draw it.
///
/// macOS 27 stopped drawing symbol-backed image reps inside `NSMenu`: the row is laid
/// out, the glyph is skipped. Two mechanisms are applied, because the release notes
/// describe them for different builds:
///
/// - Rasterizing into a template bitmap rep keeps the glyph on every supported system,
///   which is also how the menu bar status image itself is produced
///   (`MenuBarIconRenderer`).
/// - `NSMenuItem.preferredImageVisibility = .visible` is the documented opt-out
///   (radars 170477566 and 179374305) and the only path guaranteed to survive a tightening
///   of the policy for apps linked on the macOS 27 SDK, where non-symbol images are
///   supposed to be hidden too. It is applied through the runtime because it does not
///   exist before macOS 27, which is also why the rasterization still carries the older
///   systems and the older toolchains.
@MainActor
enum MenuBarItemImage {
  /// Returns an image safe to assign to `NSMenuItem.image`.
  static func symbol(
    _ name: String,
    accessibilityDescription: String? = nil
  ) -> NSImage? {
    // No symbol configuration: the glyph keeps the size menus already drew.
    guard let symbol = NSImage(
      systemSymbolName: name,
      accessibilityDescription: accessibilityDescription
    ) else {
      return nil
    }
    return rasterized(symbol)
  }

  /// Marks every image-bearing entry of a menu, including submenus, to stay visible.
  ///
  /// `NSMenu` has no menu-wide switch, so the property is set per item. Separators and
  /// imageless entries are skipped: they render the same either way, and touching them
  /// only adds noise to the diff of a future audit.
  static func enableIcons(in menu: NSMenu?) {
    for item in menu?.items ?? [] {
      if !item.isSeparatorItem, item.image != nil {
        item.preferImageVisible()
      }
      enableIcons(in: item.submenu)
    }
  }

  /// Draws the symbol once into an alpha bitmap at the display scale, keeping the
  /// logical point size so the menu lays the glyph out exactly as before.
  private static func rasterized(_ image: NSImage) -> NSImage {
    let size = image.size
    let scale = max(2, NSScreen.screens.first?.backingScaleFactor ?? 2)
    let pixelsWide = max(1, Int((size.width * scale).rounded()))
    let pixelsHigh = max(1, Int((size.height * scale).rounded()))

    if let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: pixelsWide,
      pixelsHigh: pixelsHigh,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) {
      rep.size = size
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
      image.draw(in: NSRect(origin: .zero, size: size))
      NSGraphicsContext.restoreGraphicsState()

      let raster = NSImage(size: size)
      raster.addRepresentation(rep)
      raster.isTemplate = image.isTemplate
      raster.accessibilityDescription = image.accessibilityDescription
      return raster
    }

    return image
  }
}

private extension NSMenuItem {
  /// Asks AppKit to keep this item's image on screen.
  ///
  /// `preferredImageVisibility` is declared `API_AVAILABLE(macos(27.0))`, so a direct
  /// reference only compiles against the macOS 27 SDK headers — and the project builds
  /// with Xcode 26.2 in CI. The property is an Objective-C one over an `NSInteger` enum
  /// (`Visible = 1`), so it is set through the runtime instead: binaries linked against
  /// the older SDK still get the documented switch when they run on macOS 27.
  func preferImageVisible() {
    let getter = Selector(("preferredImageVisibility"))
    let setter = Selector(("setPreferredImageVisibility:"))
    guard responds(to: getter), responds(to: setter) else { return }
    setValue(NSNumber(value: 1), forKey: "preferredImageVisibility")
  }
}
