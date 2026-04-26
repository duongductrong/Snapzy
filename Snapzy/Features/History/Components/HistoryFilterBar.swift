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
  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var backgroundStyle: HistoryBackgroundStyle = .defaultStyle
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
          .font(.system(size: 11, weight: .semibold))
        Text(label)
          .font(.system(size: 12, weight: .semibold))
        if count > 0 {
          Text("\(count)")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(pillCountBackground.opacity(isSelected ? 0.18 : 1))
            .clipShape(Capsule())
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(backgroundFill)
      .foregroundColor(isSelected ? .white : .primary.opacity(0.82))
      .clipShape(Capsule())
      .overlay(
        Capsule()
          .stroke(borderColor, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
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

    if backgroundStyle == .solid {
      return colorScheme == .dark
        ? AnyShapeStyle(Color.white.opacity(0.07))
        : AnyShapeStyle(Color.white.opacity(0.76))
    }

    return colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.08))
      : AnyShapeStyle(Color.black.opacity(0.05))
  }

  private var borderColor: Color {
    if isSelected {
      return Color.white.opacity(0.15)
    }

    return colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.64)
  }

  private var pillCountBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.84)
  }
}
