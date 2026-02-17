//
//  AboutFeatureCard.swift
//  Snapzy
//
//  Feature highlight card for About settings tab
//

import SwiftUI

struct AboutFeatureCard: View {
  let icon: String
  let iconColor: Color
  let title: String
  let description: String

  @State private var isHovering = false

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.md) {
      // Icon
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(iconColor)
        .frame(width: 36, height: 36)
        .background(iconColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Size.radiusMd))

      // Text
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))

        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 0)
    }
    .padding(Spacing.md)
    .background(Color.primary.opacity(isHovering ? 0.06 : 0.03))
    .clipShape(RoundedRectangle(cornerRadius: Size.radiusLg))
    .overlay(
      RoundedRectangle(cornerRadius: Size.radiusLg)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    )
    .scaleEffect(isHovering ? 1.02 : 1.0)
    .animation(.easeInOut(duration: 0.15), value: isHovering)
    .onHover { isHovering = $0 }
  }
}

#Preview {
  AboutFeatureCard(
    icon: "camera.viewfinder",
    iconColor: .blue,
    title: "Screen Capture",
    description: "Capture windows, regions, or full screen"
  )
  .frame(width: 300)
  .padding()
}
