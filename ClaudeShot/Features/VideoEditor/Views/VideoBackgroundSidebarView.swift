//
//  VideoBackgroundSidebarView.swift
//  ClaudeShot
//
//  Background customization sidebar for video editor
//

import SwiftUI

/// Sidebar content for video background and padding customization
struct VideoBackgroundSidebarView: View {
  @ObservedObject var state: VideoEditorState

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        noneButton
        gradientSection
        colorSection

        Divider().background(Color(nsColor: .separatorColor))

        slidersSection

        Spacer(minLength: Spacing.lg)
      }
      .padding(Spacing.md)
    }
    .frame(maxHeight: .infinity)
  }

  // MARK: - None Button

  private var noneButton: some View {
    Button {
      state.backgroundStyle = .none
      state.backgroundPadding = 0
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

  // MARK: - Gradient Section

  private var gradientSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      VideoSidebarSectionHeader(title: "Gradients")

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.backgroundColumns), spacing: GridConfig.gap) {
        ForEach(GradientPreset.allCases) { preset in
          VideoGradientPresetButton(
            preset: preset,
            isSelected: state.backgroundStyle == .gradient(preset)
          ) {
            if state.backgroundPadding <= 0 {
              state.backgroundPadding = 24
            }
            state.backgroundStyle = .gradient(preset)
          }
        }
      }
    }
  }

  // MARK: - Color Section

  private var colorSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      VideoSidebarSectionHeader(title: "Colors")
      VideoColorSwatchGrid(selectedColor: colorBinding)
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
          if state.backgroundPadding <= 0 {
            state.backgroundPadding = 24
          }
          state.backgroundStyle = .solidColor(color)
        }
      }
    )
  }

  // MARK: - Sliders Section

  private var slidersSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      VideoSliderRow(
        label: "Padding",
        value: Binding(
          get: { state.backgroundPadding },
          set: { newValue in
            state.backgroundPadding = newValue
            // Auto-apply white background when padding increases from 0
            if newValue > 0 && state.backgroundStyle == .none {
              state.backgroundStyle = .solidColor(.white)
            }
          }
        ),
        range: 0...100
      )
      VideoSliderRow(label: "Shadow", value: $state.backgroundShadowIntensity, range: 0...1)
      VideoSliderRow(label: "Corners", value: $state.backgroundCornerRadius, range: 0...32)
    }
  }
}
