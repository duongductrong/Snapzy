//
//  AnnotateSidebarSections.swift
//  ClaudeShot
//
//  Section components for the annotation sidebar
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Gradient Section

struct SidebarGradientSection: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SidebarSectionHeader(title: "Gradients")

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
        ForEach(GradientPreset.allCases) { preset in
          GradientPresetButton(
            preset: preset,
            isSelected: state.backgroundStyle == .gradient(preset)
          ) {
            state.backgroundStyle = .gradient(preset)
          }
        }
      }
    }
  }
}

// MARK: - Wallpaper Section

struct SidebarWallpaperSection: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SidebarSectionHeader(title: "Wallpapers")

      HStack(spacing: 8) {
        WallpaperPlaceholder()
        WallpaperPlaceholder()

        Button {
          addWallpaper()
        } label: {
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
            .foregroundColor(.white.opacity(0.3))
            .frame(width: 44, height: 44)
            .overlay(
              Image(systemName: "plus")
                .foregroundColor(.white.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func addWallpaper() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false

    if panel.runModal() == .OK, let url = panel.url {
      state.backgroundStyle = .wallpaper(url)
    }
  }
}

// MARK: - Blurred Section

struct SidebarBlurredSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SidebarSectionHeader(title: "Blurred")

      HStack(spacing: 8) {
        BlurredPlaceholder()
        BlurredPlaceholder()
      }
    }
  }
}

// MARK: - Color Section

struct SidebarColorSection: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SidebarSectionHeader(title: "Plain color")
      ColorSwatchGrid(selectedColor: colorBinding)
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
}

// MARK: - Sliders Section

struct SidebarSlidersSection: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SliderRow(label: "Padding", value: $state.padding, range: 0...100)
      SliderRow(label: "Inset", value: $state.inset, range: 0...50)

      Toggle("Auto-balance", isOn: $state.autoBalance)
        .font(.system(size: 12))
        .foregroundColor(.white.opacity(0.8))
        .padding(.leading, 4)

      SliderRow(label: "Shadow", value: $state.shadowIntensity, range: 0...1)
      SliderRow(label: "Corners", value: $state.cornerRadius, range: 0...32)
    }
  }
}
