//
//  AnnotateSidebarView.swift
//  ClaudeShot
//
//  Left sidebar for background and styling settings
//

import SwiftUI

/// Left sidebar with background customization options
struct AnnotateSidebarView: View {
  @ObservedObject var state: AnnotateState
  
  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        noneButton

        // Compact gradient section
        gradientSection

        // Wallpaper section
        wallpaperSection

        // Compact color section
        colorSection

        Divider().background(Color(nsColor: .separatorColor))

        // Sliders section
        slidersSection

        // Alignment section
        alignmentSection

        // Ratio section
        // ratioSection

        // Text styling section (shown when text annotation is selected)
        if state.selectedTextAnnotation != nil {
          Divider().background(Color(nsColor: .separatorColor))
          TextStylingSection(state: state)
        }
        // General annotation properties (non-text selected)
        else if state.selectedAnnotation != nil {
          Divider().background(Color(nsColor: .separatorColor))
          AnnotationPropertiesSection(state: state)
        }

        // Blur type section (shown when blur tool is active)
        if state.selectedTool == .blur {
          Divider().background(Color(nsColor: .separatorColor))
          BlurTypeSection(state: state)
        }

        // Mockup section (shown when mockup mode is active)
        if state.editorMode == .mockup {
          Divider().background(Color(nsColor: .separatorColor))
          MockupControlsSection(state: state)
        }

        Spacer(minLength: Spacing.lg)
      }
      .padding(Spacing.md)
    }
    .frame(maxHeight: .infinity)
//    .background(Color(nsColor: .scrubberTexturedBackground))
  }
  
  // MARK: - None Button

  private var noneButton: some View {
    Button {
      state.backgroundStyle = .none
      state.padding = 0

    } label: {
      Text("None")
        .font(Typography.labelMedium)
        .foregroundColor(SidebarColors.labelPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: Size.radiusSm)
            .fill(state.backgroundStyle == .none ? Color.accentColor.opacity(0.3) : SidebarColors.itemDefault)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Size.radiusSm)
            .stroke(state.backgroundStyle == .none ? Color.accentColor : Color.clear, lineWidth: Size.strokeSelected)
        )
    }
    .buttonStyle(.plain)
  }
  
  // MARK: - Sections
  
  private var gradientSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: "Gradients")

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.backgroundColumns), spacing: GridConfig.gap) {
        ForEach(GradientPreset.allCases) { preset in
          GradientPresetButton(
            preset: preset,
            isSelected: state.backgroundStyle == .gradient(preset)
          ) {

            if state.padding <= 0 {
              state.padding = 24
            }

            state.backgroundStyle = .gradient(preset)
          }
        }
      }
    }
  }

  private var wallpaperSection: some View {
    SidebarWallpaperSection(state: state)
  }

  private var colorSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: "Colors")
      CompactColorSwatchGrid(selectedColor: colorBinding)
    }
  }
  
  private var colorBinding: Binding<Color?> {
    Binding(
      get: {
        if case .solidColor(let color) = state.backgroundStyle {
          return color
        }
        return nil
      },
      set: { newColor in
        if let color = newColor {
          state.backgroundStyle = .solidColor(color)
        }
      }
    )
  }
  
  private var slidersSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      CompactSliderRow(
        label: "Padding",
        value: Binding(
          get: { state.padding },
          set: { newValue in
            state.padding = newValue
            // Auto-apply white background when padding increases from 0
            if newValue > 0 && state.backgroundStyle == .none {
              state.backgroundStyle = .solidColor(.white)
            }
          }
        ),
        range: 0...300,
        onDragging: { isDragging, value in
          state.previewPadding = isDragging ? value : nil
        }
      )
      CompactSliderRow(
        label: "Shadow",
        value: $state.shadowIntensity,
        range: 0...1,
        onDragging: { isDragging, value in
          state.previewShadowIntensity = isDragging ? value : nil
        }
      )
      CompactSliderRow(
        label: "Corners",
        value: $state.cornerRadius,
        range: 0...60,
        onDragging: { isDragging, value in
          state.previewCornerRadius = isDragging ? value : nil
        }
      )
    }
  }
  
  private var alignmentSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: "Alignment")
      AlignmentGrid(selected: $state.imageAlignment, onAlignmentChange: { newAlignment in
        print("DEBUG [Alignment]: Callback fired with newAlignment = \(newAlignment)")
        print("DEBUG [Alignment]: Current padding = \(state.padding), backgroundStyle = \(state.backgroundStyle)")

        // Auto-apply padding when alignment changes from center
        if state.padding < 24 && newAlignment != .center {
          state.padding = 24
          print("DEBUG [Alignment]: Set padding to 24")
          // Also apply background if none
          if state.backgroundStyle == .none {
            state.backgroundStyle = .solidColor(.white)
            print("DEBUG [Alignment]: Set background to white")
          }
        }

        print("DEBUG [Alignment]: After - padding = \(state.padding), alignment = \(state.imageAlignment)")
      })
    }
  }
  
  // private var ratioSection: some View {
  //   VStack(alignment: .leading, spacing: 6) {
  //     SidebarSectionHeader(title: "Ratio")
  //     Picker("", selection: $state.aspectRatio) {
  //       ForEach(AspectRatioOption.allCases) { option in
  //         Text(option.rawValue).tag(option)
  //       }
  //     }
  //     .pickerStyle(.menu)
  //     .labelsHidden()
  //     .frame(maxWidth: .infinity, alignment: .leading)
  //   }
  // }
}

// MARK: - Compact Components

struct CompactColorSwatchGrid: View {
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

struct CompactSliderRow: View {
  let label: String
  @Binding var value: CGFloat
  let range: ClosedRange<CGFloat>
  var onDragging: ((Bool, CGFloat) -> Void)? = nil

  @State private var localValue: CGFloat = 0
  @State private var isDragging: Bool = false
  @State private var textValue: String = ""
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(label)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
        Spacer()
        TextField("", text: $textValue)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary.opacity(0.9))
          .multilineTextAlignment(.trailing)
          .textFieldStyle(.plain)
          .frame(width: 36)
          .padding(.horizontal, Spacing.xs)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: Size.radiusXs)
              .fill(SidebarColors.itemDefault)
          )
          .focused($isTextFieldFocused)
          .onAppear {
            textValue = String(format: "%.0f", value)
          }
          .onChange(of: localValue) { _, newValue in
            if !isTextFieldFocused {
              textValue = String(format: "%.0f", newValue)
            }
          }
          .onChange(of: isTextFieldFocused) { _, focused in
            if !focused {
              applyTextValue()
            }
          }
          .onSubmit {
            applyTextValue()
            isTextFieldFocused = false
          }
      }
      Slider(
        value: $localValue,
        in: range,
        onEditingChanged: { editing in
          isDragging = editing
          if !editing {
            // Sync to binding only when drag ends
            value = localValue
            onDragging?(false, localValue)
          } else {
            // Drag started
            onDragging?(true, localValue)
          }
        }
      )
      .controlSize(.small)
    }
    .onAppear { localValue = value }
    .onChange(of: localValue) { _, newValue in
      // Update preview in real-time during drag
      if isDragging {
        onDragging?(true, newValue)
      }
    }
    .onChange(of: value) { _, newValue in
      // External changes sync to local (e.g., preset selection)
      if !isDragging { localValue = newValue }
    }
  }

  private func applyTextValue() {
    if let newValue = Double(textValue) {
      let clampedValue = min(max(CGFloat(newValue), range.lowerBound), range.upperBound)
      localValue = clampedValue
      value = clampedValue
      textValue = String(format: "%.0f", clampedValue)
    } else {
      textValue = String(format: "%.0f", localValue)
    }
  }
}
