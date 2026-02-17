//
//  AnnotateSidebarSections.swift
//  Snapzy
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
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: "Gradients")

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.backgroundColumns), spacing: GridConfig.gap) {
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
  @StateObject private var systemManager = SystemWallpaperManager.shared
  @State private var customWallpapers: [URL] = []

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: "Wallpapers")

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.backgroundColumns), spacing: GridConfig.gap) {
        // 3 bundled presets
        // ForEach(WallpaperPreset.allCases) { preset in
        //   WallpaperPresetButton(
        //     preset: preset,
        //     isSelected: isPresetSelected(preset)
        //   ) {
        //     selectPreset(preset)
        //   }
        // }

        // System wallpapers
        ForEach(systemManager.systemWallpapers) { item in
          SystemWallpaperButton(
            item: item,
            isSelected: isSystemWallpaperSelected(item)
          ) {
            selectSystemWallpaper(item)
          }
        }

        // Custom wallpapers from disk
        ForEach(customWallpapers, id: \.self) { url in
          CustomWallpaperButton(
            url: url,
            isSelected: isUrlSelected(url)
          ) {
            if state.padding <= 0 {
              state.padding = 24
            }
            state.backgroundStyle = .wallpaper(url)
          }
        }

        // Add button
        AddWallpaperButton {
          addWallpaper()
        }
      }

      // Loading indicator
      if systemManager.isLoading {
        HStack {
          ProgressView()
            .scaleEffect(0.6)
          Text("Loading system wallpapers...")
            .font(Typography.labelSmall)
            .foregroundColor(SidebarColors.labelSecondary)
        }
      }
    }
    .task {
      await systemManager.loadSystemWallpapers()
    }
  }

  private func isPresetSelected(_ preset: WallpaperPreset) -> Bool {
    if case .wallpaper(let url) = state.backgroundStyle {
      return url.absoluteString == "preset://\(preset.rawValue)"
    }
    return false
  }

  private func isUrlSelected(_ url: URL) -> Bool {
    if case .wallpaper(let selectedUrl) = state.backgroundStyle {
      return selectedUrl == url
    }
    return false
  }

  private func isSystemWallpaperSelected(_ item: SystemWallpaperManager.WallpaperItem) -> Bool {
    if case .wallpaper(let url) = state.backgroundStyle {
      return url == item.fullImageURL
    }
    return false
  }

  private func selectPreset(_ preset: WallpaperPreset) {
    if state.padding <= 0 {
      state.padding = 24
    }
    state.backgroundStyle = .wallpaper(URL(string: "preset://\(preset.rawValue)")!)
  }

  private func selectSystemWallpaper(_ item: SystemWallpaperManager.WallpaperItem) {
    if state.padding <= 0 {
      state.padding = 24
    }
    state.backgroundStyle = .wallpaper(item.fullImageURL)
  }

  private func addWallpaper() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false

    if panel.runModal() == .OK, let url = panel.url {
      customWallpapers.append(url)
      if state.padding <= 0 {
        state.padding = 24
      }
      state.backgroundStyle = .wallpaper(url)
    }
  }
}

// MARK: - Blurred Section

struct SidebarBlurredSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: "Blurred")

      HStack(spacing: GridConfig.gap) {
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
    VStack(alignment: .leading, spacing: Spacing.sm) {
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
    VStack(alignment: .leading, spacing: Spacing.md) {
      SliderRow(
        label: "Padding",
        value: $state.padding,
        range: 0...100,
        onDragging: { isDragging, value in
          state.previewPadding = isDragging ? value : nil
        }
      )
      SliderRow(
        label: "Inset",
        value: $state.inset,
        range: 0...50,
        onDragging: { isDragging, value in
          state.previewInset = isDragging ? value : nil
        }
      )

      Toggle("Auto-balance", isOn: $state.autoBalance)
        .font(Typography.body)
        .foregroundColor(SidebarColors.labelPrimary.opacity(0.8))
        .padding(.leading, Spacing.xs)

      SliderRow(
        label: "Shadow",
        value: $state.shadowIntensity,
        range: 0...1,
        onDragging: { isDragging, value in
          state.previewShadowIntensity = isDragging ? value : nil
        }
      )
      SliderRow(
        label: "Corners",
        value: $state.cornerRadius,
        range: 0...32,
        onDragging: { isDragging, value in
          state.previewCornerRadius = isDragging ? value : nil
        }
      )
    }
  }
}

// MARK: - Blur Type Section

struct BlurTypeSection: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: "Blur Type")

      HStack(spacing: Spacing.sm) {
        ForEach(BlurType.allCases) { blurType in
          BlurTypeButton(
            blurType: blurType,
            isSelected: state.blurType == blurType
          ) {
            state.blurType = blurType
          }
        }
      }

      Text(state.blurType == .pixelated
           ? "Pixelated blur for redacting sensitive content"
           : "Smooth Gaussian blur similar to CSS filter")
        .font(Typography.labelSmall)
        .foregroundColor(SidebarColors.labelSecondary)
        .padding(.top, 2)
    }
  }
}

struct BlurTypeButton: View {
  let blurType: BlurType
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: Spacing.xs) {
        Image(systemName: blurType.icon)
          .font(.system(size: 16))
          .foregroundColor(isSelected ? .accentColor : SidebarColors.labelPrimary)

        Text(blurType.displayName)
          .font(Typography.labelSmall)
          .fontWeight(.medium)
          .foregroundColor(isSelected ? .accentColor : SidebarColors.labelSecondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.sm)
      .background(
        RoundedRectangle(cornerRadius: Size.radiusMd)
          .fill(backgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Size.radiusMd)
          .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: Size.strokeDefault + 0.5)
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }

  private var backgroundColor: Color {
    if isSelected {
      return SidebarColors.itemSelected
    } else if isHovering {
      return SidebarColors.itemHover
    }
    return SidebarColors.itemDefault
  }
}
