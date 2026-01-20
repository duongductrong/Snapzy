//
//  QuickAccessStackView.swift
//  ZapShot
//
//  Container view for stacked quick access screenshot cards
//

import SwiftUI

/// Displays a vertical stack of quick access screenshot cards
struct QuickAccessStackView: View {
  @ObservedObject var manager: QuickAccessManager

  var body: some View {
    VStack(spacing: QuickAccessLayout.cardSpacing) {
      ForEach(manager.items) { item in
        QuickAccessCardView(item: item, manager: manager)
          .id(item.id)
          .transition(
            .asymmetric(
              insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: 15)),
              removal: .opacity.combined(with: .scale(scale: 0.85))
            )
          )
      }
    }
    .padding(QuickAccessLayout.containerPadding)
    .animation(.spring(response: 0.3, dampingFraction: 0.75, blendDuration: 0), value: manager.items.map(\.id))
  }
}
