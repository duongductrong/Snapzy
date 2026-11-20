//
//  MenuBarItemImage.swift
//  Snapzy
//
//  SF Symbol images for status bar menu entries.
//

import AppKit

/// Builds the glyph shown to the left of a menu item title.
///
/// macOS 27 no longer draws symbol-backed image reps inside `NSMenu`: the row is
/// laid out, the glyph is skipped. Rasterizing into a template bitmap rep keeps
/// the icon on every supported system, which is also how the menu bar status
/// image itself is produced (`MenuBarIconRenderer`).
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
