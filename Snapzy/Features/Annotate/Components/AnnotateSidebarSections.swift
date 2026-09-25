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
      SidebarSectionHeader(title: L10n.Common.gradients)

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
  let state: AnnotateState
  @StateObject private var wallpaperManager = SystemWallpaperManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: L10n.Common.wallpapers)

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.backgroundColumns), spacing: GridConfig.gap) {
        // Bundled default wallpapers
        ForEach(wallpaperManager.defaultWallpapers) { item in
          DefaultWallpaperButton(
            item: item,
            isSelected: isDefaultWallpaperSelected(item)
          ) {
            selectDefaultWallpaper(item)
          }
        }

        // Custom wallpapers from disk
        ForEach(wallpaperManager.customWallpapers) { item in
          CustomWallpaperButton(
            url: item.fullImageURL,
            isSelected: isUrlSelected(item.fullImageURL),
            action: {
              selectCustomWallpaper(item)
            },
            onRemove: {
              removeCustomWallpaper(item)
            })
        }

        // Add button
        AddWallpaperButton {
          addWallpaper()
        }
      }

      // Loading indicator
      if wallpaperManager.isLoading {
        HStack {
          ProgressView()
            .scaleEffect(0.6)
          Text(L10n.AnnotateUI.loadingWallpapers)
            .font(Typography.labelSmall)
            .foregroundColor(SidebarColors.labelSecondary)
        }
      }
    }
    .task {
      await wallpaperManager.loadDefaultWallpapers()
    }
  }

  private func isUrlSelected(_ url: URL) -> Bool {
    if case .wallpaper(let selectedUrl) = state.backgroundStyle {
      return selectedUrl == url
    }
    return false
  }

  private func isDefaultWallpaperSelected(_ item: SystemWallpaperManager.WallpaperItem) -> Bool {
    if case .wallpaper(let url) = state.backgroundStyle {
      return url == item.fullImageURL
    }
    return false
  }

  private func selectDefaultWallpaper(_ item: SystemWallpaperManager.WallpaperItem) {
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
      if let item = wallpaperManager.addCustomWallpaper(url) {
        selectCustomWallpaper(item)
      }
    }
  }

  private func selectCustomWallpaper(_ item: SystemWallpaperManager.WallpaperItem) {
    if state.padding <= 0 {
      state.padding = 24
    }
    state.backgroundStyle = .wallpaper(item.fullImageURL)
  }

  private func removeCustomWallpaper(_ item: SystemWallpaperManager.WallpaperItem) {
    let url = item.fullImageURL
    wallpaperManager.removeCustomWallpaper(item)

    if case .wallpaper(let selectedUrl) = state.backgroundStyle, selectedUrl == url {
      state.resetCanvasEffectsToNone()
    }
  }
}

// MARK: - Blurred Section

struct SidebarBlurredSection: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: L10n.AnnotateUI.blurredBackground)

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.backgroundColumns), spacing: GridConfig.gap) {
        ForEach(BlurredBackgroundEffect.allCases) { effect in
          BlurredBackgroundEffectButton(
            effect: effect,
            backgroundStyle: state.backgroundStyle,
            previewImage: previewImage,
            isSelected: isSelected(effect)
          ) {
            select(effect)
          }
          .disabled(!state.backgroundStyle.supportsBlurredBackgroundEffect)
        }
      }
    }
  }

  private func isSelected(_ effect: BlurredBackgroundEffect) -> Bool {
    state.isBlurredBackgroundEffectActive && state.blurredBackgroundEffect == effect
  }

  private func select(_ effect: BlurredBackgroundEffect) {
    guard state.backgroundStyle.supportsBlurredBackgroundEffect else { return }
    if isSelected(effect) {
      if case .blurred(let url) = state.backgroundStyle {
        state.backgroundStyle = .wallpaper(url)
      }
      state.isBlurredBackgroundEnabled = false
      return
    }
    if state.padding <= 0 {
      state.padding = 24
    }
    if case .blurred(let url) = state.backgroundStyle {
      state.backgroundStyle = .wallpaper(url)
    }
    state.blurredBackgroundEffect = effect
    state.isBlurredBackgroundEnabled = true
  }

  private var previewImage: NSImage? {
    guard let url = state.backgroundStyle.blurredEffectImageURL else { return nil }
    return state.cachedBackgroundImage(for: url)
  }
}

// MARK: - Color Section

struct SidebarColorSection: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: L10n.Common.colors)
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
        label: L10n.Common.padding,
        value: $state.padding,
        range: 0...100,
        onDragging: { isDragging, value in
          state.previewPadding = isDragging ? value : nil
        }
      )
      SliderRow(
        label: L10n.Common.inset,
        value: $state.inset,
        range: 0...50,
        onDragging: { isDragging, value in
          state.previewInset = isDragging ? value : nil
        }
      )

      Toggle(L10n.AnnotateUI.autoBalance, isOn: $state.autoBalance)
        .font(Typography.body)
        .foregroundColor(SidebarColors.labelPrimary.opacity(0.8))
        .padding(.leading, Spacing.xs)

      SliderRow(
        label: L10n.Common.shadow,
        value: $state.shadowIntensity,
        range: 0...1,
        onDragging: { isDragging, value in
          state.previewShadowIntensity = isDragging ? value : nil
        }
      )
      SliderRow(
        label: L10n.Common.corners,
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

  private let columns = [
    GridItem(.flexible(), spacing: Spacing.sm),
    GridItem(.flexible(), spacing: Spacing.sm),
    GridItem(.flexible(), spacing: Spacing.sm),
    GridItem(.flexible(), spacing: Spacing.sm)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      SidebarSectionHeader(title: L10n.AnnotateUI.blurType)

      LazyVGrid(columns: columns, spacing: Spacing.sm) {
        ForEach(BlurType.allCases) { blurType in
          BlurTypeButton(
            blurType: blurType,
            isSelected: state.blurType == blurType
          ) {
            state.blurType = blurType
          }
        }
      }

      let description: String = {
        switch state.blurType {
        case .pixelated: return L10n.AnnotateUI.pixelatedBlurDescription
        case .gaussian: return L10n.AnnotateUI.gaussianBlurDescription
        case .hexagonal: return L10n.AnnotateUI.hexagonalBlurDescription
        case .crystallized: return L10n.AnnotateUI.crystallizedBlurDescription
        case .pointillism: return L10n.AnnotateUI.pointillismBlurDescription
        case .halftone: return L10n.AnnotateUI.halftoneBlurDescription
        case .tape: return L10n.AnnotateUI.tapeBlurDescription
        case .washi: return L10n.AnnotateUI.washiBlurDescription
        }
      }()
      Text(description)
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
        Capsule(style: .continuous)
          .fill(backgroundColor)
      )
      .overlay(
        Capsule(style: .continuous)
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
