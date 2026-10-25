//
//  PreferencesSidebarView.swift
//  Snapzy
//
//  Settings sidebar: search field, profile header, then grouped icon rows.
//

import AppKit
import SwiftUI

struct PreferencesSidebarView: View {
  @ObservedObject var navigationState: PreferencesNavigationState

  @State private var query = ""
  @FocusState private var isSearchFocused: Bool

  private var isSearching: Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var searchResults: [PreferencesTab] {
    PreferencesTab.sidebarOrder.filter { $0.matches(query) }
  }

  var body: some View {
    VStack(spacing: 0) {
      searchField
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 10)

      ScrollView(.vertical, showsIndicators: false) {
        Group {
          if isSearching {
            searchResultList
          } else {
            browseContent
          }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
      }
      .focusable()
      .modifier(SidebarFocusEffectDisabledModifier())
      .onMoveCommand(perform: moveSelection)

    }
    .background {
      // ⌘F jumps to the search field, like Finder and System Settings.
      Button("") { isSearchFocused = true }
        .keyboardShortcut("f", modifiers: .command)
        .hidden()
    }
  }

  // MARK: - Search

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)

      TextField(L10n.PreferencesGeneral.sidebarSearchPlaceholder, text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .focused($isSearchFocused)
        .onSubmit {
          if let first = searchResults.first {
            navigationState.select(first)
          }
        }
        .onExitCommand { query = "" }

      if isSearching {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 30)
    .background(Capsule().fill(Color.primary.opacity(0.06)))
    .overlay(Capsule().strokeBorder(Color.primary.opacity(isSearchFocused ? 0.12 : 0.04), lineWidth: 1))
  }

  @ViewBuilder
  private var searchResultList: some View {
    if searchResults.isEmpty {
      Text(L10n.PreferencesGeneral.sidebarSearchNoResults)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    } else {
      VStack(spacing: 2) {
        ForEach(searchResults) { tab in
          row(for: tab)
        }
      }
    }
  }

  // MARK: - Browse

  private var browseContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      PreferencesSidebarProfileHeader(isSelected: navigationState.selectedTab == .about) {
        navigationState.select(.about)
      }

      ForEach(Array(PreferencesTab.groups.enumerated()), id: \.offset) { _, group in
        VStack(spacing: 2) {
          ForEach(group) { tab in
            row(for: tab)
          }
        }
      }
    }
  }

  private func row(for tab: PreferencesTab) -> some View {
    PreferencesSidebarRow(tab: tab, isSelected: navigationState.selectedTab == tab) {
      navigationState.select(tab)
    }
  }

  // MARK: - Keyboard

  private func moveSelection(_ direction: MoveCommandDirection) {
    let order = isSearching ? searchResults : PreferencesTab.sidebarOrder
    guard !order.isEmpty else { return }
    let current = order.firstIndex(of: navigationState.selectedTab)
    let next: Int
    switch direction {
    case .up:
      next = max((current ?? order.count) - 1, 0)
    case .down:
      next = min((current ?? -1) + 1, order.count - 1)
    default:
      return
    }
    navigationState.select(order[next])
  }
}

// MARK: - Row

private struct PreferencesSidebarRow: View {
  let tab: PreferencesTab
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  private static let height: CGFloat = 32

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        PreferencesSidebarIcon(tab: tab, size: 22)
        Text(tab.title)
          .font(.system(size: 13, weight: isSelected ? .medium : .regular))
          .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 7)
      .frame(height: Self.height)
      .background {
        Radius.controlRect(forHeight: Self.height)
          .fill(Color.primary.opacity(isSelected ? 0.08 : (isHovering ? 0.045 : 0)))
      }
      .contentShape(Radius.controlRect(forHeight: Self.height))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - Icon

/// System Settings-style squircle: one near-black tile with a bold white glyph for every page,
/// so the sidebar reads calm and uniform whatever the system icon style is. About uses the
/// menu bar brand mark on the same tile.
struct PreferencesSidebarIcon: View {
  let tab: PreferencesTab
  var size: CGFloat = 22

  var body: some View {
    if tab == .about {
      PreferencesIconTile(size: size) {
        // MenubarIcon's visible mark fills ~75% of its canvas; scale so it matches symbol weight.
        Image("MenubarIcon")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: size * 0.78, height: size * 0.78)
      }
    } else {
      PreferencesSymbolTile(symbol: tab.symbol, size: size)
    }
  }
}

/// A bold rounded SF Symbol on the near-black settings tile.
struct PreferencesSymbolTile: View {
  let symbol: String
  var size: CGFloat = 22

  var body: some View {
    PreferencesIconTile(size: size) {
      Image(systemName: symbol)
        .symbolRenderingMode(.monochrome)
        .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
    }
  }
}

/// Near-black glossy tile (Droppy-style): deep falloff toward the bottom, with a rim that
/// catches light at the top edge and fades out, so it reads like a tiny app icon.
/// Corner scales with `size`, so the same tile works from sidebar rows up to page heroes.
/// No drop shadow at any size; large tiles take an Icon Composer-style specular rim.
struct PreferencesIconTile<Glyph: View>: View {
  var size: CGFloat
  @ViewBuilder let glyph: () -> Glyph

  private var isLarge: Bool { size > 36 }

  var body: some View {
    let shape = isLarge ? Radius.rect(size * 0.24) : Radius.controlRect(forHeight: size)
    glyph()
      .foregroundStyle(Color.white)
      .frame(width: size, height: size)
      .background {
        shape.fill(LinearGradient(
          colors: [Color(white: 0.18), Color(white: 0.05)],
          startPoint: .top,
          endPoint: .bottom
        ))
      }
      .overlay {
        if isLarge {
          specularRim(shape)
        } else {
          shape.strokeBorder(
            LinearGradient(
              colors: [Color.white.opacity(0.24), Color.white.opacity(0.04)],
              startPoint: .top,
              endPoint: .bottom
            ),
            lineWidth: 0.5
          )
        }
      }
  }

  /// Light hits the top-left edge and glints again at the bottom-right, like the glass edge
  /// Icon Composer renders on macOS 26 icons; a dark inner hairline keeps the rim off the fill.
  private func specularRim(_ shape: RoundedRectangle) -> some View {
    let rimWidth = size * 0.022
    return ZStack {
      shape.strokeBorder(
        LinearGradient(
          stops: [
            .init(color: Color.white.opacity(0.55), location: 0),
            .init(color: Color.white.opacity(0.16), location: 0.3),
            .init(color: Color.white.opacity(0.05), location: 0.55),
            .init(color: Color.white.opacity(0.32), location: 1),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        lineWidth: rimWidth
      )
      shape
        .inset(by: rimWidth)
        .strokeBorder(Color.black.opacity(0.55), lineWidth: 0.75)
    }
  }
}

struct PreferencesAppIconImage: View {
  var size: CGFloat

  var body: some View {
    Image(nsImage: NSApp.applicationIconImage)
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
  }
}

// MARK: - Focus Effect Disabled Modifier (macOS 13 compat)

private struct SidebarFocusEffectDisabledModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 14.0, *) {
      content.focusEffectDisabled()
    } else {
      content
    }
  }
}
