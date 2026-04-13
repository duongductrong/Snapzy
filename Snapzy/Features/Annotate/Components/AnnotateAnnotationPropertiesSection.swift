//
//  AnnotationPropertiesSection.swift
//  Snapzy
//
//  Sidebar section for editing selected annotation properties
//

import SwiftUI

/// Property editing section for selected annotations
struct AnnotationPropertiesSection: View {
  @ObservedObject var state: AnnotateState

  private var annotation: AnnotationItem? {
    state.selectedAnnotation
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      SidebarSectionHeader(title: L10n.AnnotateUI.annotation)

      // Stroke color
      strokeColorPicker

      // Stroke width (for non-text)
      if !isTextAnnotation {
        strokeWidthSlider
      }

      // Fill color (for shapes)
      if supportsFillColor {
        fillColorPicker
      }
    }
  }

  // MARK: - Computed Properties

  private var isTextAnnotation: Bool {
    guard let ann = annotation else { return false }
    if case .text = ann.type { return true }
    return false
  }

  private var supportsFillColor: Bool {
    guard let ann = annotation else { return false }
    switch ann.type {
    case .rectangle, .filledRectangle, .oval: return true
    default: return false
    }
  }

  // MARK: - Subviews

  private var strokeColorPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.Common.color)
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      ColorPickerRow(
        selectedColor: strokeColorBinding,
        colors: [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]
      )
    }
  }

  private var strokeWidthSlider: some View {
    CompactSliderRow(
      label: L10n.Common.stroke,
      value: strokeWidthBinding,
      range: 1...20
    )
  }

  private var fillColorPicker: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.Common.fill)
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      ColorPickerRow(
        selectedColor: fillColorBinding,
        colors: [.clear, .red, .orange, .yellow, .green, .blue, .purple, .white]
      )
    }
  }

  // MARK: - Bindings

  private var strokeColorBinding: Binding<Color> {
    Binding(
      get: { annotation?.properties.strokeColor ?? .red },
      set: { newColor in
        guard let id = state.selectedAnnotationId else { return }
        state.updateAnnotationProperties(id: id, strokeColor: newColor)
      }
    )
  }

  private var strokeWidthBinding: Binding<CGFloat> {
    Binding(
      get: { annotation?.properties.strokeWidth ?? 3 },
      set: { newWidth in
        guard let id = state.selectedAnnotationId else { return }
        state.updateAnnotationProperties(id: id, strokeWidth: newWidth)
      }
    )
  }

  private var fillColorBinding: Binding<Color> {
    Binding(
      get: { annotation?.properties.fillColor ?? .clear },
      set: { newColor in
        guard let id = state.selectedAnnotationId else { return }
        state.updateAnnotationProperties(id: id, fillColor: newColor)
      }
    )
  }
}

// MARK: - Supporting Views

struct ColorPickerRow: View {
  @Binding var selectedColor: Color
  let colors: [Color]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(colors, id: \.self) { color in
        Button {
          selectedColor = color
        } label: {
          colorSwatch(color)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func colorSwatch(_ color: Color) -> some View {
    ZStack {
      if color == .clear {
        // Show "none" indicator for clear
        Circle()
          .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
          .frame(width: 20, height: 20)
        Image(systemName: "xmark")
          .font(.system(size: 8))
          .foregroundColor(.secondary)
      } else {
        Circle()
          .fill(color)
          .frame(width: 20, height: 20)
          .overlay(
            Circle()
              .stroke(
                selectedColor == color ? Color.accentColor : Color.secondary.opacity(0.5),
                lineWidth: selectedColor == color ? 2 : 1
              )
          )
      }
    }
  }
}
