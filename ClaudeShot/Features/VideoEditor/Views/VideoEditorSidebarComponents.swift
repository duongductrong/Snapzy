//
//  VideoEditorSidebarComponents.swift
//  ClaudeShot
//
//  Dedicated sidebar components for video editor (decoupled from Annotate)
//

import SwiftUI

// MARK: - Section Header

struct VideoSidebarSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(Typography.sectionHeader)
      .foregroundColor(SidebarColors.labelSecondary)
  }
}

// MARK: - Gradient Preset Button

struct VideoGradientPresetButton: View {
  let preset: GradientPreset
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      RoundedRectangle(cornerRadius: Size.radiusMd)
        .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Color Swatch Grid

struct VideoColorSwatchGrid: View {
  @Binding var selectedColor: Color?

  private let colors: [Color] = [
    .red, .orange, .yellow, .green, .blue, .purple, .pink, .gray, .white, .black
  ]

  var body: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.colorColumns), spacing: GridConfig.gap) {
      ForEach(colors, id: \.self) { color in
        Button {
          selectedColor = color
        } label: {
          Circle()
            .fill(color)
            .colorSwatchStyle(isSelected: selectedColor == color)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

// MARK: - Slider Row

struct VideoSliderRow: View {
  let label: String
  @Binding var value: CGFloat
  let range: ClosedRange<CGFloat>

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(label)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
        Spacer()
        Text(String(format: "%.0f", value))
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelTertiary)
      }
      Slider(value: $value, in: range)
        .controlSize(.small)
    }
  }
}
