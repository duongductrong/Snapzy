//
//  FloatingStackView.swift
//  ZapShot
//
//  Container view for stacked floating screenshot cards
//

import SwiftUI

/// Displays a vertical stack of floating screenshot cards
struct FloatingStackView: View {
  @ObservedObject var manager: FloatingScreenshotManager

  private let spacing: CGFloat = 8
  private let padding: CGFloat = 10

  var body: some View {
    VStack(spacing: spacing) {
      ForEach(manager.items) { item in
        FloatingCardView(item: item, manager: manager)
          .id(item.id)
          .transition(
            .asymmetric(
              insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: 15)),
              removal: .opacity.combined(with: .scale(scale: 0.85))
            )
          )
      }
    }
    .padding(padding)
    .animation(.spring(response: 0.3, dampingFraction: 0.75, blendDuration: 0), value: manager.items.map(\.id))
  }
}
