//
//  FloatingCardView.swift
//  ZapShot
//
//  Single floating screenshot card with hover interactions
//

import SwiftUI

/// Displays a single screenshot preview with hover-activated actions
struct FloatingCardView: View {
  let item: ScreenshotItem
  let manager: FloatingScreenshotManager

  @State private var isHovering = false

  private let cardWidth: CGFloat = 180
  private let cardHeight: CGFloat = 112.5
  private let cornerRadius: CGFloat = 10

  var body: some View {
    ZStack(alignment: .center) {
      // Thumbnail with blur effect on hover
      Image(nsImage: item.thumbnail)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
        .blur(radius: isHovering ? 2 : 0)
        .cornerRadius(cornerRadius)

      // Hover overlay with buttons
      if isHovering {
        hoverOverlay
          .transition(.opacity.combined(with: .scale(scale: 0.95)))
      }

      // Dismiss button (top-right, only visible on hover)
      if isHovering {
        dismissButton
          .transition(.opacity)
      }
    }
    .frame(width: cardWidth, height: cardHeight)
    .background(
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.black.opacity(0.1))
    )
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.2)) {
        isHovering = hovering
      }
    }
    .onTapGesture(count: 2) {
      openAnnotation()
    }
  }

  private func openAnnotation() {
    Task { @MainActor in
      AnnotateManager.shared.openAnnotation(for: item)
    }
  }

  private var hoverOverlay: some View {
    ZStack {
      // Dimming overlay
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.black.opacity(0.4))

      // Action buttons (vertical, centered) - Copy and Save only
      VStack(spacing: 8) {
        CardTextButton(label: "Copy") {
          manager.copyToClipboard(id: item.id)
        }

        CardTextButton(label: "Save") {
          manager.openInFinder(id: item.id)
        }
      }
    }
  }

  private var dismissButton: some View {
    VStack {
      HStack {
        Spacer()
        Button(action: { manager.removeScreenshot(id: item.id) }) {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(
              Circle()
                .fill(Color.black.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
        .padding(6)
      }
      Spacer()
    }
  }
}
