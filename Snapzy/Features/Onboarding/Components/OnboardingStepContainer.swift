//
//  OnboardingStepContainer.swift
//  Snapzy
//
//  Reusable container for onboarding steps — consistent width, vertical centering, scroll fallback
//

import SwiftUI

struct OnboardingStepContainer<Content: View>: View {
  var onBack: (() -> Void)? = nil
  @ViewBuilder let content: () -> Content

  var body: some View {
    ZStack {
      GeometryReader { proxy in
        ScrollView(.vertical, showsIndicators: false) {
          VStack(spacing: 0) {
            content()
          }
          .frame(maxWidth: 480)
          // Center within the area the page indicator does not cover, and pad by the same
          // amount so tall steps scroll to a stop above the dots instead of under them.
          .frame(
            maxWidth: .infinity,
            minHeight: max(0, proxy.size.height - VSDesignSystem.Metrics.pageIndicatorArea)
          )
          .padding(.horizontal, 40)
          .padding(.bottom, VSDesignSystem.Metrics.pageIndicatorArea)
        }
      }

      // Back button — fixed at center-left, doesn't scroll.
      // Offset upward by titlebar height (28pt) to visually center within the content area
      // below the transparent titlebar, plus the indicator area so it centers in the same
      // region as the content above and keeps its tuned offset from that content's center.
      if let onBack {
        VStack {
          Spacer()
          HStack {
            BackButton(action: onBack)
              .padding(.leading, 24)
            Spacer()
          }
          Spacer()
        }
        .padding(.bottom, 28 + VSDesignSystem.Metrics.pageIndicatorArea)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Back Button

private struct BackButton: View {
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: "arrow.left")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(VSDesignSystem.Colors.tertiary)
        .frame(width: 32, height: 32)
        .background(
          Circle()
            .fill(isHovered ? VSDesignSystem.Colors.cardFill : Color.clear)
        )
        .overlay(
          Circle()
            .stroke(VSDesignSystem.Colors.cardStroke, lineWidth: 1)
        )
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.15)) {
        isHovered = hovering
      }
    }
  }
}
