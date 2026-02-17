//
//  TextStylingSection.swift
//  Snapzy
//
//  Sidebar section for text annotation styling controls
//

import SwiftUI

/// Sidebar section for styling text annotations
struct TextStylingSection: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    if let annotation = state.selectedTextAnnotation {
      VStack(alignment: .leading, spacing: 10) {
        SidebarSectionHeader(title: "Text Style")

        // Font size slider
        fontSizeSlider(for: annotation)

        // Text color picker
        textColorPicker(for: annotation)

        // Background color picker
        backgroundColorPicker(for: annotation)
      }
    }
  }

  // MARK: - Font Size Slider

  private func fontSizeSlider(for annotation: AnnotationItem) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text("Size")
          .font(.system(size: 10))
          .foregroundColor(.secondary)
        Spacer()
        Text("\(Int(annotation.properties.fontSize))pt")
          .font(.system(size: 10))
          .foregroundColor(.secondary.opacity(0.7))
      }
      Slider(
        value: Binding(
          get: { annotation.properties.fontSize },
          set: { state.updateAnnotationProperties(id: annotation.id, fontSize: $0) }
        ),
        in: 12...72,
        step: 1
      )
      .controlSize(.small)
    }
  }

  // MARK: - Text Color Picker

  private func textColorPicker(for annotation: AnnotationItem) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Text Color")
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      HStack(spacing: 4) {
        ForEach(textColors, id: \.self) { color in
          Button {
            state.updateAnnotationProperties(id: annotation.id, strokeColor: color)
          } label: {
            Circle()
              .fill(color)
              .frame(width: 24, height: 24)
              .overlay(
                Circle()
                  .stroke(
                    colorsMatch(annotation.properties.strokeColor, color) ? Color.accentColor : Color.secondary.opacity(0.5),
                    lineWidth: colorsMatch(annotation.properties.strokeColor, color) ? 2 : 1
                  )
              )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: - Background Color Picker

  private func backgroundColorPicker(for annotation: AnnotationItem) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Background")
        .font(.system(size: 10))
        .foregroundColor(.secondary)

      HStack(spacing: 4) {
        // None/transparent button
        Button {
          state.updateAnnotationProperties(id: annotation.id, fillColor: .clear)
        } label: {
          Text("None")
            .font(.system(size: 9))
            .foregroundColor(.primary)
            .frame(width: 36, height: 24)
            .background(
              RoundedRectangle(cornerRadius: 4)
                .fill(annotation.properties.fillColor == .clear ? Color.blue.opacity(0.3) : Color.primary.opacity(0.1))
            )
        }
        .buttonStyle(.plain)

        // Color swatches for background
        ForEach(backgroundColors, id: \.self) { color in
          Button {
            state.updateAnnotationProperties(id: annotation.id, fillColor: color)
          } label: {
            Circle()
              .fill(color)
              .frame(width: 24, height: 24)
              .overlay(
                Circle()
                  .stroke(
                    colorsMatch(annotation.properties.fillColor, color) ? Color.accentColor : Color.secondary.opacity(0.5),
                    lineWidth: colorsMatch(annotation.properties.fillColor, color) ? 2 : 1
                  )
              )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: - Color Definitions

  private var textColors: [Color] {
    [.white, .black, .red, .orange, .yellow, .green, .blue]
  }

  private var backgroundColors: [Color] {
    [.white, .black, .yellow, .blue]
  }

  /// Compare colors for UI selection state
  /// - Note: Uses SwiftUI Color equality which may have precision limits across color spaces
  ///   (e.g., sRGB vs Display P3). This is acceptable for UI selection purposes.
  private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
    return a == b
  }
}
