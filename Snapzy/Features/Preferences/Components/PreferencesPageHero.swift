//
//  PreferencesPageHero.swift
//  Snapzy
//
//  Droppy-style page chrome: a large icon-tile hero that names the page, and the
//  expandable card headers (tile, title, subtitle, chevron) that list its groups.
//

import SwiftUI

struct PreferencesPageHero: View {
  let tab: PreferencesTab
  let subtitle: String

  var body: some View {
    VStack(spacing: 12) {
      PreferencesSidebarIcon(tab: tab, size: 72, duotone: true)

      VStack(spacing: 4) {
        Text(tab.title)
          .font(.system(size: 26, weight: .bold, design: .rounded))
          .foregroundStyle(Color.primary)

        Text(subtitle)
          .font(.system(size: 13))
          .foregroundStyle(Color.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 420)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 4)
    .padding(.bottom, 12)
    .textCase(nil)
    .accessibilityElement(children: .combine)
  }
}

/// Header row of an expandable settings card: tile, title, subtitle, chevron. Clicking
/// anywhere on it opens or closes the card's rows beneath it; Reset shows while open.
struct PreferencesExpandableCardHeader: View {
  let symbol: String
  let title: String
  let subtitle: String
  var help: String? = nil
  var tint: PreferencesIconTint = .blue
  @Binding var isExpanded: Bool
  var onReset: (() -> Void)? = nil

  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 12) {
      PreferencesSymbolTile(symbol: symbol, size: 30, tint: tint, duotone: true)

      VStack(alignment: .leading, spacing: 2) {
        titleText
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundStyle(Color.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 8)

      if isExpanded, let onReset {
        Button(L10n.Common.reset, action: onReset)
          .buttonStyle(.borderless)
          .font(.caption)
          .transition(.opacity)
      }

      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.secondary.opacity(isHovering || isExpanded ? 1 : 0.6))
        .rotationEffect(.degrees(isExpanded ? 90 : 0))
        .accessibilityHidden(true)
    }
    .padding(.vertical, 2)
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(.easeInOut(duration: 0.2)) {
        isExpanded.toggle()
      }
    }
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.15), value: isHovering)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isButton)
  }

  @ViewBuilder
  private var titleText: some View {
    let text = Text(title)
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(Color.primary)
    if let help, !help.isEmpty {
      text.hint(help, variant: .icon(.info))
    } else {
      text
    }
  }
}
