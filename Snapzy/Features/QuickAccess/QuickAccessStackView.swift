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
    let visibleItems = manager.items.filter {
      $0.isShownInPanel(hideCardWhenWindowOpen: manager.hideCardWhenWindowOpen)
    }

    VStack(spacing: QuickAccessLayout.cardSpacing) {
      Spacer(minLength: 0)
      ForEach(visibleItems) { item in
        QuickAccessCardView(
          item: item,
          manager: manager,
          onHover: nil
        )
        .id(item.id)
        .transition(cardTransition(for: item))
      }
    }
    .frame(width: QuickAccessLayout.scaledCardWidth(manager.overlayScale))
    .padding(QuickAccessLayout.containerPadding)
    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: visibleItems.count)
  }

  private func cardTransition(for item: QuickAccessItem) -> AnyTransition {
    if reduceMotion {
      return .opacity
    }
    
    switch manager.animationStyle {
    case .scale:
      return .asymmetric(
        insertion: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity),
        removal: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity)
      )
    case .slide:
      let edge: Edge = manager.position.isLeftSide ? .leading : .trailing
      return .asymmetric(
        insertion: .move(edge: edge).combined(with: .opacity),
        removal: .move(edge: edge).combined(with: .opacity)
      )
    }
  }
}
