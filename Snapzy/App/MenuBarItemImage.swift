//
//  MenuBarItemImage.swift
//  Snapzy
//
//  SF Symbol images for menu entries, plus the opt-in that keeps them on screen.
//

import AppKit

/// Hands menus plain SF Symbols and, when the user opts in, applies Apple's documented
/// visibility opt-out to every image-bearing row.
///
/// macOS 27 hides menu item images by default (radars 170477566 and 179374305), and the
/// policy keys off the representation: symbol-backed images are hidden on every linked
/// SDK, while a rasterized bitmap still draws on builds linked against SDK 26.2 — which
/// is what CI and releases use. Rasterizing here would therefore keep icons on screen
/// even with the setting off, so glyphs stay symbol-backed and `preferredImageVisibility`
/// is the only thing deciding visibility.
@MainActor
enum MenuBarItemImage {
  /// Returns an image safe to assign to `NSMenuItem.image`.
  static func symbol(
    _ name: String,
    accessibilityDescription: String? = nil
  ) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
  }

  /// Marks every image-bearing entry of a menu, including submenus, to stay visible —
  /// but only while the user has opted in. With the setting off the rows keep
  /// `.automatic`, so AppKit's macOS 27 default applies unchanged.
  ///
  /// `NSMenu` has no menu-wide switch, so the property is set per item. Separators and
  /// imageless entries are skipped: they render the same either way.
  static func enableIcons(in menu: NSMenu?) {
    guard MenuBarCustomizationStore.shared.drawsItemIcons else { return }
    for item in menu?.items ?? [] {
      if !item.isSeparatorItem, item.image != nil {
        item.preferImageVisible()
      }
      enableIcons(in: item.submenu)
    }
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
