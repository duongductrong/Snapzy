//
//  VideoEditorSidebarComponents.swift
//  ClaudeShot
//
//  Dedicated sidebar components for video editor (decoupled from Annotate)
//

import SwiftUI

// MARK: - Section Header

struct VideoSidebarSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(Typography.sectionHeader)
      .foregroundColor(SidebarColors.labelSecondary)
  }
}

// MARK: - Gradient Preset Button

struct VideoGradientPresetButton: View {
  let preset: GradientPreset
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      RoundedRectangle(cornerRadius: Size.radiusMd)
        .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Color Swatch Grid

struct VideoColorSwatchGrid: View {
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

// MARK: - Slider Row

struct VideoSliderRow: View {
  let label: String
  @Binding var value: CGFloat
  let range: ClosedRange<CGFloat>

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(label)
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelSecondary)
        Spacer()
        Text(String(format: "%.0f", value))
          .font(Typography.labelSmall)
          .foregroundColor(SidebarColors.labelTertiary)
      }
      Slider(value: $value, in: range)
        .controlSize(.small)
    }
  }
}

// MARK: - System Wallpaper Button (Cached)

struct VideoSystemWallpaperButton: View {
  let item: SystemWallpaperManager.WallpaperItem
  let isSelected: Bool
  let action: () -> Void

  @State private var thumbnail: NSImage?

  var body: some View {
    Button(action: action) {
      Group {
        if let thumbnail = thumbnail {
          Image(nsImage: thumbnail)
            .resizable()
            .aspectRatio(1, contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay(
              ProgressView()
                .scaleEffect(0.5)
            )
        }
      }
      .clipped()
      .cornerRadius(Size.radiusMd)
      .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
    .onAppear {
      loadThumbnail()
    }
  }

  private func loadThumbnail() {
    // Check cache first (sync)
    if let cached = SystemWallpaperManager.shared.cachedThumbnail(for: item.thumbnailURL ?? item.fullImageURL) {
      thumbnail = cached
      return
    }
    // Load async with caching
    SystemWallpaperManager.shared.loadThumbnail(for: item) { image in
      thumbnail = image
    }
  }
}

// MARK: - Custom Wallpaper Button (Cached)

struct VideoCustomWallpaperButton: View {
  let url: URL
  let isSelected: Bool
  let action: () -> Void

  @State private var thumbnail: NSImage?

  var body: some View {
    Button(action: action) {
      Group {
        if let thumbnail = thumbnail {
          Image(nsImage: thumbnail)
            .resizable()
            .aspectRatio(1, contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay(
              ProgressView()
                .scaleEffect(0.5)
            )
        }
      }
      .frame(height: Size.gridItem)
      .clipped()
      .cornerRadius(Size.radiusMd)
      .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
    .onAppear {
      loadThumbnail()
    }
  }

  private func loadThumbnail() {
    // Create a temporary WallpaperItem for custom URLs
    let item = SystemWallpaperManager.WallpaperItem(
      fullImageURL: url,
      thumbnailURL: nil,
      name: url.lastPathComponent
    )
    SystemWallpaperManager.shared.loadThumbnail(for: item) { image in
      thumbnail = image
    }
  }
}

// MARK: - Add Wallpaper Button

struct VideoAddWallpaperButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      RoundedRectangle(cornerRadius: Size.radiusMd)
        .fill(SidebarColors.itemDefault)
        .overlay(
          Image(systemName: "plus")
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(SidebarColors.labelSecondary)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Size.radiusMd)
            .stroke(SidebarColors.borderDefault, lineWidth: Size.strokeDefault)
        )
    }
    .buttonStyle(.plain)
  }
}
