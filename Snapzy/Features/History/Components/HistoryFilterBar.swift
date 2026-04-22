//
//  HistoryFilterBar.swift
//  Snapzy
//
//  Filter tab bar for capture history types
//

import SwiftUI

struct HistoryFilterBar: View {
  @Binding var selectedFilter: CaptureHistoryType?
  let counts: [CaptureHistoryType?: Int]

  private let filters: [(label: String, icon: String, type: CaptureHistoryType?)] = [
    ("All", "square.grid.2x2", nil),
    ("Screenshots", CaptureHistoryType.screenshot.systemIconName, .screenshot),
    ("Videos", CaptureHistoryType.video.systemIconName, .video),
    ("GIFs", CaptureHistoryType.gif.systemIconName, .gif),
  ]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(filters, id: \.label) { filter in
        FilterPill(
          label: filter.label,
          icon: filter.icon,
          count: counts[filter.type] ?? 0,
          isSelected: selectedFilter == filter.type
        ) {
          withAnimation(.easeInOut(duration: 0.15)) {
            selectedFilter = filter.type
          }
        }
      }
      Spacer()
    }
  }
}

private struct FilterPill: View {
  @Environment(\.colorScheme) private var colorScheme

  let label: String
  let icon: String
  let count: Int
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 12, weight: .medium))
        Text(label)
          .font(.system(size: 13, weight: .medium))
        if count > 0 {
          Text("\(count)")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(isSelected ? 0.18 : (colorScheme == .dark ? 0.12 : 0.84)))
            .clipShape(Capsule())
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(backgroundFill)
      .foregroundColor(isSelected ? .white : .primary)
      .clipShape(Capsule())
      .overlay(
        Capsule()
          .stroke(borderColor, lineWidth: 1)
      )
    }
    .buttonStyle(PlainButtonStyle())
  }

  private var backgroundFill: AnyShapeStyle {
    if isSelected {
      return AnyShapeStyle(
        LinearGradient(
          colors: [
            Color.accentColor.opacity(0.98),
            Color.accentColor.opacity(0.84),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )
    }

    return AnyShapeStyle(.regularMaterial)
  }

  private var borderColor: Color {
    if isSelected {
      return Color.white.opacity(0.15)
    }

    return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
  }
}
