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
  @State private var searchGroups: [PreferencesSearchGroup] = []
  /// Result last opened from the list, so keyboard moves continue from it.
  @State private var activeResultID: String?
  @FocusState private var isSearchFocused: Bool

  /// L10n strings are fixed for the app's lifetime, so the index is built once.
  private static let searchEngine = PreferencesSearchEngine.standard()

  private var isSearching: Bool {
    !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Results in display order: each page row, then its settings.
  private var flatResults: [PreferencesSearchEntry] {
    searchGroups.flatMap { group in
      [group.pageResult?.entry ?? PreferencesSearchEntry(page: group.tab)] + group.settings.map(\.entry)
    }
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
    .onChange(of: query) { newValue in
      searchGroups = Self.searchEngine.groupedSearch(newValue)
      activeResultID = nil
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
          let results = flatResults
          if let entry = results.first(where: { $0.id == activeResultID }) ?? results.first {
            open(entry)
          }
        }
        .onMoveCommand(perform: moveSelection)
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
    if searchGroups.isEmpty {
      Text(L10n.PreferencesGeneral.sidebarSearchNoResults)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    } else {
      VStack(spacing: 10) {
        ForEach(searchGroups) { group in
          VStack(spacing: 2) {
            PreferencesSidebarRow(
              tab: group.tab,
              isSelected: isPageRowSelected(group.tab)
            ) {
              open(group.pageResult?.entry ?? PreferencesSearchEntry(page: group.tab))
            }

            ForEach(group.settings) { result in
              PreferencesSidebarSearchResultRow(
                result: result,
                isSelected: activeResultID == result.id
              ) {
                open(result.entry)
              }
            }
          }
        }
      }
    }
  }

  private func isPageRowSelected(_ tab: PreferencesTab) -> Bool {
    guard navigationState.selectedTab == tab else { return false }
    return activeResultID == nil || activeResultID == tab.rawValue
  }

  private func open(_ entry: PreferencesSearchEntry) {
    activeResultID = entry.id
    navigationState.reveal(entry)
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
    let step: Int
    switch direction {
    case .up:
      step = -1
    case .down:
      step = 1
    default:
      return
    }

    if isSearching {
      let order = flatResults
      guard !order.isEmpty else { return }
      let current = order.firstIndex { $0.id == activeResultID }
      let next = current.map { min(max($0 + step, 0), order.count - 1) } ?? (step > 0 ? 0 : order.count - 1)
      open(order[next])
      return
    }

    let order = PreferencesTab.sidebarOrder
    let current = order.firstIndex(of: navigationState.selectedTab)
    let next = current.map { min(max($0 + step, 0), order.count - 1) } ?? 0
    navigationState.select(order[next])
  }
}

// MARK: - Search Result Row

/// A setting inside a page, indented under that page's row, with its section as context.
private struct PreferencesSidebarSearchResultRow: View {
  let result: PreferencesSearchResult
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  /// Lines the title up with the page title above (row padding + icon + spacing).
  private static let leadingInset: CGFloat = 7 + 22 + 9

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 1) {
        Text(highlightedTitle)
          .font(.system(size: 12))
          .foregroundStyle(Color.primary)
          .lineLimit(2)
        if let section = result.entry.section, !section.isEmpty {
          Text(section)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, Self.leadingInset)
      .padding(.trailing, 7)
      .padding(.vertical, 5)
      .background {
        Radius.controlRect(forHeight: 32)
          .fill(Color.primary.opacity(isSelected ? 0.08 : (isHovering ? 0.045 : 0)))
      }
      .contentShape(Radius.controlRect(forHeight: 32))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(result.entry.detail ?? "")
    .accessibilityLabel([result.entry.title, result.entry.section].compactMap { $0 }.joined(separator: ", "))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// The title with the characters the query matched set in semibold.
  private var highlightedTitle: AttributedString {
    let title = result.entry.title
    var attributed = AttributedString(title)
    for range in result.titleHighlights {
      guard let attributedRange = Range(range, in: attributed) else { continue }
      attributed[attributedRange].font = .system(size: 12, weight: .semibold)
    }
    return attributed
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
        PreferencesSidebarIcon(tab: tab, size: 22, duotone: true)
        Text(tab.title)
          .font(.system(size: 13, weight: isSelected ? .medium : .regular))
          .foregroundStyle(Color.primary)
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

/// Glyph tint for a settings tile: one hue in a pastel band that sits light on the near-black
/// tile, washed toward white at the top and settling into the full color at the bottom
/// (Droppy / App Store dark-icon look). Every tint shares that band, so pages each get their
/// own color while the sidebar still reads as one family.
struct PreferencesIconTint: Equatable {
  /// Hue in degrees on the color wheel.
  var hue: Double
  var saturation: Double = 0.6

  static let blue = PreferencesIconTint(hue: 214)
  static let periwinkle = PreferencesIconTint(hue: 238)
  static let graphite = PreferencesIconTint(hue: 225, saturation: 0.07)

  /// Near-white silver for the primary layer of a duotone glyph, so the tint reads as an accent.
  static var silver: LinearGradient {
    LinearGradient(
      colors: [Color(white: 0.98), Color(white: 0.76)],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  var gradient: LinearGradient {
    LinearGradient(
      colors: [
        Color(hue: wrapped(hue - 3), saturation: saturation * 0.55, brightness: 1),
        Color(hue: wrapped(hue + 3), saturation: saturation, brightness: 0.86),
      ],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  private func wrapped(_ degrees: Double) -> Double {
    (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
  }
}

extension PreferencesTab {
  /// Each page's glyph color, picked to match what the glyph depicts; neighbours within a
  /// sidebar group never share a hue family.
  var iconTint: PreferencesIconTint {
    switch self {
    case .general: return .graphite
    case .capture: return .blue
    case .quickAccess: return PreferencesIconTint(hue: 262)
    case .shortcuts: return .periwinkle
    case .annotate: return PreferencesIconTint(hue: 350)
    case .history: return PreferencesIconTint(hue: 40, saturation: 0.66)
    case .menuBar: return PreferencesIconTint(hue: 174)
    case .cloud: return PreferencesIconTint(hue: 198)
    case .permissions: return PreferencesIconTint(hue: 18, saturation: 0.64)
    case .commandLine: return PreferencesIconTint(hue: 305, saturation: 0.5)
    case .advanced: return .graphite
    case .about: return .blue
    }
  }
}

/// System Settings-style squircle: one near-black tile for every page, each glyph tinted in
/// its page's color. About uses the menu bar brand mark on the same tile. `duotone` (page
/// heroes) draws the glyph silver with the page color as its accent layer.
struct PreferencesSidebarIcon: View {
  let tab: PreferencesTab
  var size: CGFloat = 22
  var duotone = false

  var body: some View {
    if tab == .shortcuts && duotone {
      PreferencesIconTile(size: size, tint: tab.iconTint, duotone: true) {
        // ⌘ is a single-layer symbol; tinted fills behind its loops and centre give it the
        // accent layer, so the silver outline reads like a keycap legend.
        ZStack {
          ForEach(0..<4, id: \.self) { corner in
            Circle()
              .fill(.secondary)
              .frame(width: size * 0.11, height: size * 0.11)
              .offset(
                x: size * (corner % 2 == 0 ? -0.15 : 0.15),
                y: size * (corner < 2 ? -0.15 : 0.15)
              )
          }
          Radius.rect(size * 0.02)
            .fill(.secondary)
            .frame(width: size * 0.2, height: size * 0.2)
          Image(systemName: tab.symbol)
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
        }
      }
    } else if tab == .commandLine && duotone {
      PreferencesIconTile(size: size, tint: tab.iconTint, duotone: true) {
        // The prompt is cut out of a single-layer symbol, too thin to carry an accent. Keep the
        // window silver like the ⌘ tile, so the cut-out prompt shows the dark tile through it.
        Image(systemName: tab.symbol)
          .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
          .foregroundStyle(.primary)
      }
    } else if tab == .about {
      PreferencesIconTile(size: size, tint: tab.iconTint) {
        // MenubarIcon's visible mark fills ~75% of its canvas; scale so it matches symbol weight.
        Image("MenubarIcon")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: size * 0.78, height: size * 0.78)
      }
    } else {
      PreferencesSymbolTile(symbol: tab.symbol, size: size, tint: tab.iconTint, duotone: duotone)
    }
  }
}

/// A bold rounded SF Symbol on the near-black settings tile. Duotone renders the symbol's
/// layers as a palette: silver body, tinted accent.
struct PreferencesSymbolTile: View {
  let symbol: String
  var size: CGFloat = 22
  var tint: PreferencesIconTint = .blue
  var duotone = false

  var body: some View {
    PreferencesIconTile(size: size, tint: tint, duotone: duotone) {
      Image(systemName: symbol)
        .symbolRenderingMode(duotone ? .palette : .monochrome)
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
  var tint: PreferencesIconTint = .blue
  var duotone = false
  @ViewBuilder let glyph: () -> Glyph

  private var isLarge: Bool { size > 36 }

  var body: some View {
    let shape = isLarge ? Radius.rect(size * 0.24) : Radius.controlRect(forHeight: size)
    styledGlyph
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

  @ViewBuilder
  private var styledGlyph: some View {
    if duotone {
      glyph().foregroundStyle(PreferencesIconTint.silver, tint.gradient)
    } else {
      glyph().foregroundStyle(tint.gradient)
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
