//
//  AnnotateSidebarComponents.swift
//  ClaudeShot
//
//  Reusable components for the annotation sidebar
//

import SwiftUI

// MARK: - Section Header

struct SidebarSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(.secondary)
      .textCase(.uppercase)
  }
}

// MARK: - Gradient Preset Button

struct GradientPresetButton: View {
  let preset: GradientPreset
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      RoundedRectangle(cornerRadius: 6)
        .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: 44, height: 44)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Placeholders

struct WallpaperPlaceholder: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 6)
      .fill(Color.gray.opacity(0.3))
      .frame(width: 44, height: 44)
  }
}

struct BlurredPlaceholder: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 6)
      .fill(Color.gray.opacity(0.2))
      .frame(width: 44, height: 44)
      .blur(radius: 2)
  }
}

// MARK: - Color Swatch Grid

struct ColorSwatchGrid: View {
  @Binding var selectedColor: Color?

  private let colors: [[Color]] = [
    [.red, .orange, .yellow, .green, .blue, .purple, .pink],
    [.gray, .white, .black, Color(white: 0.3), Color(white: 0.5), Color(white: 0.7), Color(white: 0.9)]
  ]

  var body: some View {
    VStack(spacing: 6) {
      ForEach(0..<colors.count, id: \.self) { row in
        HStack(spacing: 6) {
          ForEach(0..<colors[row].count, id: \.self) { col in
            ColorSwatch(
              color: colors[row][col],
              isSelected: selectedColor == colors[row][col]
            ) {
              selectedColor = colors[row][col]
            }
          }
        }
      }
    }
  }
}

struct ColorSwatch: View {
  let color: Color
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Circle()
        .fill(color)
        .frame(width: 24, height: 24)
        .overlay(
          Circle()
            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: isSelected ? 2 : 1)
        )
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Slider Row

struct SliderRow: View {
  let label: String
  @Binding var value: CGFloat
  let range: ClosedRange<CGFloat>

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Slider(value: $value, in: range)
        .controlSize(.small)
    }
  }
}

// MARK: - Alignment Grid

struct AlignmentGrid: View {
  @Binding var selected: ImageAlignment

  private let alignments: [[ImageAlignment]] = [
    [.topLeft, .top, .topRight],
    [.left, .center, .right],
    [.bottomLeft, .bottom, .bottomRight]
  ]

  var body: some View {
    VStack(spacing: 2) {
      ForEach(0..<3, id: \.self) { row in
        HStack(spacing: 2) {
          ForEach(0..<3, id: \.self) { col in
            AlignmentCell(
              alignment: alignments[row][col],
              isSelected: selected == alignments[row][col]
            ) {
              selected = alignments[row][col]
            }
          }
        }
      }
    }
    .padding(4)
    .background(Color.secondary.opacity(0.1))
    .cornerRadius(6)
  }
}

struct AlignmentCell: View {
  let alignment: ImageAlignment
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Rectangle()
        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.3))
        .frame(width: 20, height: 20)
        .cornerRadius(3)
    }
    .buttonStyle(.plain)
  }
}
