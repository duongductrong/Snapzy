//
//  VideoEditorSidebarComponents.swift
//  Snapzy
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
      Radius.rect(Radius.tile)
        .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Color Swatch Grid

struct VideoColorSwatchGrid: View {
  @Binding var selectedColor: Color?
  @ObservedObject private var paletteStore = AnnotateColorPaletteStore.shared
  @State private var draftCustomColor = Color.red

  private let colors: [Color] = [
    .red, .orange, .yellow, .green, .blue, .purple, .pink, .gray, .white, .black
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.colorColumns),
        spacing: GridConfig.gap
      ) {
        ForEach(colors, id: \.self) { color in
          Button {
            selectedColor = color
          } label: {
            Circle()
              .fill(color)
              .colorSwatchStyle(isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color))
          }
          .buttonStyle(.plain)
        }

        ForEach(paletteStore.customColors, id: \.self) { color in
          AnnotateColorSwatchButton(
            color: color,
            isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
            size: nil,
            onDelete: {
              paletteStore.removeColor(color)
            }
          ) {
            selectedColor = color
          }
        }

        AnnotateCustomColorPickerControl(
          selectedColor: customColorBinding,
          draftColor: $draftCustomColor,
          swatchSize: nil
        )
      }
    }
  }

  private var customColorBinding: Binding<Color> {
    Binding(
      get: { selectedColor ?? draftCustomColor },
      set: { color in
        draftCustomColor = color
        selectedColor = color
      }
    )
  }
}

// MARK: - Slider Row

struct VideoSliderRow: View {
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
            Radius.controlRect(forHeight: 17)
              .fill(SidebarColors.itemDefault)
          )
          .focused($isTextFieldFocused)
          .onAppear {
            textValue = String(format: "%.0f", value)
          }
          .onChange(of: localValue) { newValue in
            if !isTextFieldFocused {
              textValue = String(format: "%.0f", newValue)
            }
          }
          .onChange(of: isTextFieldFocused) { focused in
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
    .onChange(of: localValue) { newValue in
      // Update preview in real-time during drag
      if isDragging {
        onDragging?(true, newValue)
      }
    }
    .onChange(of: value) { newValue in
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

// MARK: - Default Wallpaper Button (Cached)

struct VideoDefaultWallpaperButton: View {
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
      .cornerRadius(Radius.tile)
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
  let onRemove: () -> Void
  let action: () -> Void

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
            Rectangle()
              .fill(Color.gray.opacity(0.15))
              .overlay(
                ProgressView()
                  .scaleEffect(0.5)
              )
          }
        }
        .clipped()
        .cornerRadius(Radius.tile)
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
        .help(L10n.AnnotateUI.removeCustomWallpaper)
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
    // Keep custom wallpaper rendering path identical with system wallpapers.
    if let cached = SystemWallpaperManager.shared.cachedThumbnail(for: url) {
      thumbnail = cached
      return
    }

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
      Image(systemName: "plus")
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(SidebarColors.labelSecondary)
        .actionButtonStyle()
    }
    .buttonStyle(.plain)
  }
}
