//
//  AboutLinkCard.swift
//  Snapzy
//
//  Link card component for About settings tab
//

import SwiftUI

struct AboutLinkCard: View {
  let icon: String
  let title: String
  let subtitle: String
  let url: String

  @State private var isHovering = false

  var body: some View {
    Button(action: {
      if let url = URL(string: url) {
        NSWorkspace.shared.open(url)
      }
    }) {
      VStack(spacing: Spacing.sm) {
        Image(systemName: icon)
          .font(.title2)
          .foregroundColor(.accentColor)

        VStack(spacing: 2) {
          Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.primary)

          Text(subtitle)
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.md)
      .background(Color.primary.opacity(isHovering ? 0.08 : 0.04))
      .clipShape(RoundedRectangle(cornerRadius: Size.radiusLg))
      .overlay(
        RoundedRectangle(cornerRadius: Size.radiusLg)
          .stroke(Color.primary.opacity(0.08), lineWidth: 1)
      )
      .scaleEffect(isHovering ? 1.03 : 1.0)
      .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }
}

#Preview {
  AboutLinkCard(
    icon: "globe",
    title: "Website",
    subtitle: "github.com/duongductrong",
    url: "https://github.com"
  )
  .frame(width: 150)
  .padding()
}
