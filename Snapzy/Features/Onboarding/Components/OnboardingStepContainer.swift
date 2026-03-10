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
          .frame(maxWidth: .infinity, minHeight: proxy.size.height)
          .padding(.horizontal, 40)
        }
      }

      // Back arrow — fixed at center-left, doesn't scroll
      if let onBack {
        VStack {
          Spacer()
          HStack {
            Button {
              onBack()
            } label: {
              Image(systemName: "arrow.left")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(VSDesignSystem.Colors.tertiary)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.leading, 24)

            Spacer()
          }
          Spacer()
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
