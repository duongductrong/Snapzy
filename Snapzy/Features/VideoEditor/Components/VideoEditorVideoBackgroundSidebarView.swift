//
//  VideoEditorVideoBackgroundSidebarView.swift
//  Snapzy
//
//  Background customization sidebar for video editor
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar content for video background and padding customization
struct VideoBackgroundSidebarView: View {
  @ObservedObject var state: VideoEditorState
  @StateObject private var wallpaperManager = SystemWallpaperManager.shared
  @State private var aspectRatioOrientation: AspectRatioOrientation = .horizontal

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        noneButton
        gradientSection
        wallpaperSection
        colorSection

        Divider()

        slidersSection
        ratioSection

        Spacer(minLength: Spacing.lg)
      }
      .padding(Spacing.md)
    }
    .frame(maxHeight: .infinity)
    .onAppear {
      syncAspectRatioOrientationWithExportPreset()
    }
    .onChange(of: state.exportSettings.dimensionPreset) { _ in
      syncAspectRatioOrientationWithExportPreset()
    }
  }

  // MARK: - None Button

  private var noneButton: some View {
    Button {
      state.backgroundStyle = .none
      state.backgroundPadding = 0
    } label: {
      Text(L10n.Common.none)
        .font(Typography.labelMedium)
        .foregroundColor(SidebarColors.labelPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
          Capsule(style: .continuous)
            .fill(state.backgroundStyle == .none ? Color.accentColor.opacity(0.3) : SidebarColors.itemDefault)
        )
        .overlay(
          Capsule(style: .continuous)
            .stroke(state.backgroundStyle == .none ? Color.accentColor : Color.clear, lineWidth: Size.strokeSelected)
        )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Gradient Section

  private var gradientSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      VideoSidebarSectionHeader(title: L10n.Common.gradients)

      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.backgroundColumns),
        spacing: GridConfig.gap
      ) {
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

  // MARK: - Wallpaper Section

  private var wallpaperSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      VideoSidebarSectionHeader(title: L10n.Common.wallpapers)

      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.backgroundColumns),
        spacing: GridConfig.gap
      ) {
        // Bundled default wallpapers
        ForEach(wallpaperManager.defaultWallpapers) { item in
          VideoDefaultWallpaperButton(
            item: item,
            isSelected: isDefaultWallpaperSelected(item)
          ) {
            selectDefaultWallpaper(item)
          }
        }

        // Custom wallpapers
        ForEach(wallpaperManager.customWallpapers) { item in
          VideoCustomWallpaperButton(
            url: item.fullImageURL,
            isSelected: isWallpaperUrlSelected(item.fullImageURL),
            onRemove: {
              removeCustomWallpaper(item)
            }
          ) {
            selectCustomWallpaper(item)
          }
        }

        // Add button
        VideoAddWallpaperButton {
          addCustomWallpaper()
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

  // MARK: - Wallpaper Helpers

  private func isDefaultWallpaperSelected(_ item: SystemWallpaperManager.WallpaperItem) -> Bool {
    if case .wallpaper(let url) = state.backgroundStyle {
      return url == item.fullImageURL
    }
    return false
  }

  private func isWallpaperUrlSelected(_ url: URL) -> Bool {
    if case .wallpaper(let selectedUrl) = state.backgroundStyle {
      return selectedUrl == url
    }
    return false
  }

  private func selectDefaultWallpaper(_ item: SystemWallpaperManager.WallpaperItem) {
    if state.backgroundPadding <= 0 {
      state.backgroundPadding = 24
    }
    state.backgroundStyle = .wallpaper(item.fullImageURL)
  }

  private func selectCustomWallpaper(_ item: SystemWallpaperManager.WallpaperItem) {
    if state.backgroundPadding <= 0 {
      state.backgroundPadding = 24
    }
    state.backgroundStyle = .wallpaper(item.fullImageURL)
  }

  private func addCustomWallpaper() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false

    if panel.runModal() == .OK, let url = panel.url {
      if let item = wallpaperManager.addCustomWallpaper(url) {
        selectCustomWallpaper(item)
      }
    }
  }

  private func removeCustomWallpaper(_ item: SystemWallpaperManager.WallpaperItem) {
    let url = item.fullImageURL
    wallpaperManager.removeCustomWallpaper(item)

    if case .wallpaper(let selectedUrl) = state.backgroundStyle, selectedUrl == url {
      state.backgroundStyle = .none
      state.backgroundPadding = 0
    }
  }

  // MARK: - Color Section

  private var colorSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      VideoSidebarSectionHeader(title: L10n.Common.colors)
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
        label: L10n.Common.padding,
        value: Binding(
          get: { state.backgroundPadding },
          set: { newValue in
            state.backgroundPadding = newValue
            // Auto-apply white background when padding increases from 0
            if newValue > 0, state.backgroundStyle == .none {
              state.backgroundStyle = .solidColor(.white)
            }
          }
        ),
        range: 0 ... 300
      )
      VideoSliderRow(label: L10n.Common.shadow, value: $state.backgroundShadowIntensity, range: 0 ... 1)
      VideoSliderRow(label: L10n.Common.corners, value: $state.backgroundCornerRadius, range: 0 ... 60)
    }
  }

  // MARK: - Ratio Section

  private var ratioSection: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack(spacing: Spacing.sm) {
        VideoSidebarSectionHeader(title: L10n.AnnotateUI.backgroundRatio)
        Spacer(minLength: 0)
        aspectRatioOrientationPicker
      }
      .frame(maxWidth: .infinity)

      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: 3),
        spacing: GridConfig.gap
      ) {
        ForEach(AspectRatioOption.allCases) { option in
          AspectRatioOptionButton(
            option: option,
            isSelected: selectedAspectRatioOption == option,
            orientation: aspectRatioOrientation
          ) {
            applyBackgroundRatio(option)
          }
        }
      }
    }
  }

  private var aspectRatioOrientationPicker: some View {
    Picker("", selection: Binding(
      get: { aspectRatioOrientation },
      set: { newOrientation in
        aspectRatioOrientation = newOrientation
        reapplySelectedBackgroundRatioForCurrentOrientation()
      }
    )) {
      ForEach(AspectRatioOrientation.allCases) { orientation in
        Image(systemName: orientation.systemImageName)
          .tag(orientation)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .controlSize(.mini)
    .fixedSize(horizontal: true, vertical: false)
    .help(L10n.AnnotateUI.toggleAspectRatioOrientation)
  }

  private var selectedAspectRatioOption: AspectRatioOption? {
    switch state.exportSettings.dimensionPreset {
    case .original:
      .auto
    case .percent90,
         .percent80,
         .percent60,
         .percent50,
         .percent40,
         .percent30,
         .percent20:
      nil
    case .custom:
      .free
    case .ratio1x1:
      .square
    case .ratio4x3,
         .ratio3x4:
      .ratio4x3
    case .ratio3x2,
         .ratio2x3:
      .ratio3x2
    case .ratio16x9,
         .ratio9x16:
      .ratio16x9
    }
  }

  private func applyBackgroundRatio(_ option: AspectRatioOption) {
    var settings = state.exportSettings

    switch option {
    case .auto:
      settings.dimensionPreset = .original
    case .free:
      let resolvedSize = settings.exportSize(from: state.naturalSize)
      let fallbackSize = CGSize(width: settings.customWidth, height: settings.customHeight)
      let currentSize = VideoEditorExportLayout.evenSize(
        resolvedSize == .zero ? fallbackSize : resolvedSize
      )
      settings.dimensionPreset = .custom
      settings.customWidth = Int(currentSize.width)
      settings.customHeight = Int(currentSize.height)
      settings.aspectRatioLocked = false
    case .square:
      settings.dimensionPreset = .ratio1x1
      settings.aspectRatioLocked = true
    case .ratio4x3:
      settings.dimensionPreset = aspectRatioOrientation == .vertical ? .ratio3x4 : .ratio4x3
      settings.aspectRatioLocked = true
    case .ratio3x2:
      settings.dimensionPreset = aspectRatioOrientation == .vertical ? .ratio2x3 : .ratio3x2
      settings.aspectRatioLocked = true
    case .ratio16x9:
      settings.dimensionPreset = aspectRatioOrientation == .vertical ? .ratio9x16 : .ratio16x9
      settings.aspectRatioLocked = true
    }

    state.updateExportSettings(settings)
  }

  private func reapplySelectedBackgroundRatioForCurrentOrientation() {
    guard let selectedAspectRatioOption,
          selectedAspectRatioOption.supportsOrientation
    else { return }

    applyBackgroundRatio(selectedAspectRatioOption)
  }

  private func syncAspectRatioOrientationWithExportPreset() {
    switch state.exportSettings.dimensionPreset {
    case .ratio3x4,
         .ratio2x3,
         .ratio9x16:
      aspectRatioOrientation = .vertical
    case .ratio4x3,
         .ratio3x2,
         .ratio16x9:
      aspectRatioOrientation = .horizontal
    default:
      break
    }
  }
}
