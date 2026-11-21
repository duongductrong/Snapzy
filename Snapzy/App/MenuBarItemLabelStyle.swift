//
//  MenuBarItemLabelStyle.swift
//  Snapzy
//
//  SwiftUI counterpart of MenuBarItemImage: whether a menu row draws its icon.
//

import SwiftUI

/// Shows or hides a menu row's icon the way `MenuBarItemImage.enableIcons(in:)` does for an
/// `NSMenu`, so SwiftUI menus follow the same "Show icons in menus" setting instead of the
/// system default alone.
///
/// SwiftUI hides menu item symbols on macOS 27 too (radar 170480710) and names
/// `.labelStyle(.titleAndIcon)` as the opt-out; with the setting off the row is reduced to
/// its title, which is what the system renders on its own.
struct MenuBarItemLabelStyle: LabelStyle {
  let showsIcon: Bool

  func makeBody(configuration: Configuration) -> some View {
    if showsIcon {
      Label {
        configuration.title
      } icon: {
        configuration.icon
      }
      .labelStyle(.titleAndIcon)
    } else {
      configuration.title
    }
  }
}

extension View {
  /// Applies the "Show icons in menus" rule to a SwiftUI menu row label.
  ///
  /// Rows that use a checkmark symbol as their selection marker follow the rule too: with
  /// the setting off they look exactly as the system renders them today, and turning it on
  /// brings the marker back. Rows whose icon is their only content are left alone — hiding
  /// those empties the row instead of collapsing a column.
  func menuBarRowIcon(showsIcon: Bool) -> some View {
    labelStyle(MenuBarItemLabelStyle(showsIcon: showsIcon))
  }
}
