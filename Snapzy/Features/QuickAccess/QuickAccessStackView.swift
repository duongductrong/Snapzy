//
//  QuickAccessStackView.swift
//  Snapzy
//
//  Vertical stacked container view for quick access cards
//

import SwiftUI

/// Displays a vertical stack of quick access cards, bottom-aligned in fixed-size panel
struct QuickAccessStackView: View {
  @ObservedObject var manager: QuickAccessManager
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  var body: some View {
    VStack(spacing: QuickAccessLayout.cardSpacing) {
      Spacer(minLength: 0)
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
  }

  private var cardTransition: AnyTransition {
    if reduceMotion {
      return .opacity
    }
    return .asymmetric(
      insertion: .move(edge: .trailing)
        .combined(with: .opacity),
      removal: .move(edge: .trailing)
        .combined(with: .opacity)
    )
  }
}
