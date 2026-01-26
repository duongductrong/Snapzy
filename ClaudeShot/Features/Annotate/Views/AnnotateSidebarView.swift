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
      VStack(alignment: .leading, spacing: 12) {
        noneButton
        
        // Compact gradient section
        gradientSection
        
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

        // Mockup section (shown when mockup tool is active)
        if state.selectedTool == .mockup {
          Divider().background(Color(nsColor: .separatorColor))
          MockupControlsSection(state: state)
        }

        Spacer(minLength: 20)
      }
      .padding(12)
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
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(state.backgroundStyle == .none ? Color.blue.opacity(0.3) : Color.primary.opacity(0.1))
        )
    }
    .buttonStyle(.plain)
  }
  
  // MARK: - Sections
  
  private var gradientSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      SidebarSectionHeader(title: "Gradients")
      
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
        ForEach(GradientPreset.allCases) { preset in
          GradientPresetButton(
            preset: preset,
            isSelected: state.backgroundStyle == .gradient(preset)
          ) {
            
            if (state.padding <= 0) {
              state.padding = 24
            }
            
            state.backgroundStyle = .gradient(preset)
          }
        }
      }
    }
  }
  
  private var colorSection: some View {
    VStack(alignment: .leading, spacing: 6) {
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
    VStack(alignment: .leading, spacing: 10) {
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
        range: 0...300
      )
      CompactSliderRow(label: "Shadow", value: $state.shadowIntensity, range: 0...1)
      CompactSliderRow(label: "Corners", value: $state.cornerRadius, range: 0...60)
    }
  }
  
  private var alignmentSection: some View {
    VStack(alignment: .leading, spacing: 6) {
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
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
      ForEach(colors, id: \.self) { color in
        Button {
          selectedColor = color
        } label: {
          Circle()
            .fill(color)
            .frame(width: 28, height: 28)
            .overlay(
              Circle()
                .stroke(selectedColor == color ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: selectedColor == color ? 2 : 1)
            )
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

  @State private var textValue: String = ""
  @FocusState private var isTextFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(label)
          .font(.system(size: 10))
          .foregroundColor(.secondary)
        Spacer()
        TextField("", text: $textValue)
          .font(.system(size: 10))
          .foregroundColor(.secondary.opacity(0.9))
          .multilineTextAlignment(.trailing)
          .textFieldStyle(.plain)
          .frame(width: 36)
          .padding(.horizontal, 4)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.primary.opacity(0.05))
          )
          .focused($isTextFieldFocused)
          .onAppear {
            textValue = String(format: "%.0f", value)
          }
          .onChange(of: value) { _, newValue in
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
      Slider(value: $value, in: range)
        .controlSize(.small)
    }
  }

  private func applyTextValue() {
    if let newValue = Double(textValue) {
      let clampedValue = min(max(CGFloat(newValue), range.lowerBound), range.upperBound)
      value = clampedValue
      textValue = String(format: "%.0f", clampedValue)
    } else {
      textValue = String(format: "%.0f", value)
    }
  }
}
