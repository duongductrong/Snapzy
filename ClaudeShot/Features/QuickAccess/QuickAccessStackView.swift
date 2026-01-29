//
//  QuickAccessStackView.swift
//  ClaudeShot
//
//  Vertical stacked container view for quick access cards
//

import SwiftUI

/// Displays a vertical stack of quick access cards
struct QuickAccessStackView: View {
  @ObservedObject var manager: QuickAccessManager
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  var body: some View {
    VStack(spacing: QuickAccessLayout.cardSpacing) {
      ForEach(manager.items) { item in
        QuickAccessCardView(
          item: item,
          manager: manager,
          onHover: nil
        )
        .id(item.id)
        .transition(cardTransition)
      }
    }
    .padding(QuickAccessLayout.containerPadding)
    .animation(
      reduceMotion ? nil : QuickAccessAnimations.cardInsert,
      value: manager.items.map(\.id)
    )
  }

  private var cardTransition: AnyTransition {
    if reduceMotion {
      return .opacity
    }
    return .asymmetric(
      insertion: .move(edge: .trailing)
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0.9)),
      removal: .move(edge: .leading)
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0.85))
    )
  }
}
