//
//  SnapzyKeycapView.swift
//  Snapzy
//
//  Physical Mac keycap chip and row components for keyboard shortcut display.
//

import SwiftUI

struct SnapzyKeycapChip: View {
  var label: String
  var emphasis: Bool = false

  private var height: CGFloat { 19 }

  var body: some View {
    Text(label)
      .font(.system(size: SnapzyOnboardingType.keycap + 1, weight: .semibold, design: .rounded))
      .foregroundStyle(emphasis ? SnapzyGlassInk.primary : SnapzyGlassInk.muted)
      .padding(.horizontal, 5.5)
      .frame(minWidth: height, minHeight: height)
      .background {
        ZStack {
          RoundedRectangle(cornerRadius: 5.5, style: .continuous)
            .fill(Color.black.opacity(0.24))

          RoundedRectangle(cornerRadius: 5.5, style: .continuous)
            .fill(Color.white.opacity(emphasis ? 0.20 : 0.08))

          RoundedRectangle(cornerRadius: 5.5, style: .continuous)
            .strokeBorder(
              LinearGradient(
                colors: [
                  Color.white.opacity(emphasis ? 0.36 : 0.16),
                  Color.white.opacity(emphasis ? 0.10 : 0.04),
                ],
                startPoint: .top,
                endPoint: .bottom
              ),
              lineWidth: SnapzySurfaceGlass.specularLineWidth
            )
        }
      }
      .fixedSize()
  }
}

struct SnapzyKeycapRow: View {
  var keys: [String]
  var emphasis: Bool = false

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
        SnapzyKeycapChip(label: key, emphasis: emphasis)
      }
    }
  }
}
