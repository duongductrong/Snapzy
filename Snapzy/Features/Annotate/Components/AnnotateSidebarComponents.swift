//
//  AnnotateSidebarComponents.swift
//  Snapzy
//
//  Reusable components for the annotation sidebar
//

import SwiftUI

// MARK: - Section Header

struct SidebarSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(Typography.sectionHeader)
      .foregroundColor(SidebarColors.labelSecondary)
  }
}

// MARK: - Gradient Preset Button

struct GradientPresetButton: View {
  let preset: GradientPreset
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      RoundedRectangle(cornerRadius: Size.radiusMd)
        .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Placeholders

struct WallpaperPlaceholder: View {
  var body: some View {
    RoundedRectangle(cornerRadius: Size.radiusMd)
      .fill(Color.gray.opacity(0.3))
      .frame(width: Size.gridItem, height: Size.gridItem)
  }
}

// MARK: - Wallpaper Preset Button

struct WallpaperPresetButton: View {
  let preset: WallpaperPreset
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      RoundedRectangle(cornerRadius: Size.radiusMd)
        .fill(preset.gradient)
        .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Custom Wallpaper Button

struct CustomWallpaperButton: View {
  let url: URL
  let isSelected: Bool
  let action: () -> Void
  let onRemove: () -> Void

  @State private var thumbnail: NSImage?
  @State private var isHovering = false

  var body: some View {
    ZStack(alignment: .topLeading) {
      Button(action: action) {
        Group {
          if let thumbnail = thumbnail {
            Image(nsImage: thumbnail)
              .resizable()
              .aspectRatio(1, contentMode: .fill)
          } else {
            Color.gray.opacity(0.3)
          }
        }
        .clipped()
        .sidebarItemStyle(isSelected: isSelected)
      }
      .buttonStyle(.plain)

      if isHovering {
        Button(action: onRemove) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.65))
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .help("Remove custom wallpaper")
        .offset(x: -4, y: -4)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
      }
    }
    .animation(.easeInOut(duration: 0.15), value: isHovering)
    .onHover { isHovering = $0 }
    .onAppear {
      loadThumbnail()
    }
  }

  private func loadThumbnail() {
    // Use SystemWallpaperManager's downsampling for custom URLs too
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

struct AddWallpaperButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(.primary.opacity(0.5))
        .actionButtonStyle()
    }
    .buttonStyle(.plain)
  }
}

// MARK: - System Wallpaper Button

struct SystemWallpaperButton: View {
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
          Color.gray.opacity(0.3)
        }
      }
      .clipped()
      .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
    .onAppear {
      loadCachedThumbnail()
    }
  }

  private func loadCachedThumbnail() {
    // Check cache first (sync)
    let cacheKey = item.thumbnailURL ?? item.fullImageURL
    if let cached = SystemWallpaperManager.shared.cachedThumbnail(for: cacheKey) {
      thumbnail = cached
      return
    }

    // Load async with downsampling (callback-based, no continuation)
    SystemWallpaperManager.shared.loadThumbnail(for: item) { image in
      thumbnail = image
    }
  }
}

// MARK: - Grant Access Button

struct GrantAccessButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: Spacing.xs) {
        Image(systemName: "folder.badge.plus")
          .font(.system(size: 16, weight: .medium))
        Text("Grant")
          .font(Typography.labelSmall)
      }
      .foregroundColor(.primary.opacity(0.5))
      .actionButtonStyle()
    }
    .buttonStyle(.plain)
  }
}

struct BlurredPlaceholder: View {
  var body: some View {
    RoundedRectangle(cornerRadius: Size.radiusMd)
      .fill(Color.gray.opacity(0.2))
      .frame(width: Size.gridItem, height: Size.gridItem)
      .blur(radius: 2)
  }
}

// MARK: - Color Swatch Grid

struct ColorSwatchGrid: View {
  @Binding var selectedColor: Color?

  private let colors: [[Color]] = [
    [.red, .orange, .yellow, .green, .blue, .purple, .pink],
    [.gray, .white, .black, Color(white: 0.3), Color(white: 0.5), Color(white: 0.7), Color(white: 0.9)]
  ]

  var body: some View {
    VStack(spacing: Spacing.sm) {
      ForEach(0..<colors.count, id: \.self) { row in
        HStack(spacing: Spacing.sm) {
          ForEach(0..<colors[row].count, id: \.self) { col in
            ColorSwatch(
              color: colors[row][col],
              isSelected: selectedColor == colors[row][col]
            ) {
              selectedColor = colors[row][col]
            }
          }
        }
      }
    }
  }
}

struct ColorSwatch: View {
  let color: Color
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Circle()
        .fill(color)
        .colorSwatchStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Slider Row

struct SliderRow: View {
  let label: String
  @Binding var value: CGFloat
  let range: ClosedRange<CGFloat>
  var onDragging: ((Bool, CGFloat) -> Void)? = nil

  @State private var localValue: CGFloat = 0
  @State private var isDragging: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(label)
        .font(Typography.labelMedium)
        .foregroundColor(SidebarColors.labelSecondary)

      Slider(
        value: $localValue,
        in: range,
        onEditingChanged: { editing in
          isDragging = editing
          onDragging?(editing, localValue)
          if !editing {
            // Sync to binding only when drag ends
            value = localValue
          }
        }
      )
      .controlSize(.small)
    }
    .onAppear { localValue = value }
    .onChange(of: value) { newValue in
      // External changes sync to local (e.g., preset selection)
      if !isDragging { localValue = newValue }
    }
  }
}

// MARK: - Alignment Grid

struct AlignmentGrid: View {
  @Binding var selected: ImageAlignment
  var onAlignmentChange: ((ImageAlignment) -> Void)? = nil

  private let alignments: [[ImageAlignment]] = [
    [.topLeft, .top, .topRight],
    [.left, .center, .right],
    [.bottomLeft, .bottom, .bottomRight]
  ]

  var body: some View {
    VStack(spacing: 2) {
      ForEach(0..<3, id: \.self) { row in
        HStack(spacing: 2) {
          ForEach(0..<3, id: \.self) { col in
            AlignmentCell(
              alignment: alignments[row][col],
              isSelected: selected == alignments[row][col]
            ) {
              let newAlignment = alignments[row][col]
              selected = newAlignment
              onAlignmentChange?(newAlignment)
            }
          }
        }
      }
    }
    .padding(Spacing.xs)
    .background(SidebarColors.itemDefault)
    .cornerRadius(Size.radiusSm)
  }
}

struct AlignmentCell: View {
  let alignment: ImageAlignment
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Rectangle()
        .fill(backgroundColor)
        .frame(width: 20, height: 20)
        .cornerRadius(Size.radiusXs)
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }

  private var backgroundColor: Color {
    if isSelected { return .accentColor }
    if isHovering { return SidebarColors.itemHover }
    return Color.secondary.opacity(0.3)
  }
}
