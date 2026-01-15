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
  let onCopy: () -> Void
  let onOpenFinder: () -> Void
  let onDismiss: () -> Void

  @State private var isHovering = false
  @State private var appeared = false

  private let cardWidth: CGFloat = 160
  private let cardHeight: CGFloat = 100
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
    .opacity(appeared ? 1 : 0)
    .scaleEffect(appeared ? 1 : 0.8)
    .offset(y: appeared ? 0 : 20)
    .onAppear {
      withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
        appeared = true
      }
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

      // Action buttons (horizontal, centered) - text-based
      HStack(spacing: 8) {
        CardTextButton(label: "Copy") {
          onCopy()
        }

        CardTextButton(label: "Folder") {
          onOpenFinder()
        }
      }
    }
  }

  private var dismissButton: some View {
    VStack {
      HStack {
        Spacer()
        Button(action: onDismiss) {
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
