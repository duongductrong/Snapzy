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
        FloatingCardView(
          item: item,
          onCopy: {
            manager.copyToClipboard(id: item.id)
            withAnimation(.easeOut(duration: 0.2)) {
              manager.removeScreenshot(id: item.id)
            }
          },
          onOpenFinder: {
            manager.openInFinder(id: item.id)
            withAnimation(.easeOut(duration: 0.2)) {
              manager.removeScreenshot(id: item.id)
            }
          },
          onDismiss: {
            withAnimation(.easeOut(duration: 0.2)) {
              manager.removeScreenshot(id: item.id)
            }
          }
        )
        .transition(
          .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity.combined(with: .scale(scale: 0.8))
          )
        )
      }
    }
    .padding(padding)
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.items.count)
  }
}
