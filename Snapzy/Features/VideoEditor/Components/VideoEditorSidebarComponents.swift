//
//  VideoEditorSidebarComponents.swift
//  Snapzy
//
//  Dedicated sidebar components for video editor (decoupled from Annotate)
//

import SwiftUI

private enum VideoEditorSidebarChrome {
  static let cornerRadius: CGFloat = 20
  static let shadowRadius: CGFloat = 18
  static let shadowYOffset: CGFloat = 10
  static let railCornerRadius: CGFloat = 18

  static var panelFill: Color {
    Color(nsColor: .controlBackgroundColor).opacity(0.96)
  }

  static var panelStroke: Color {
    Color.primary.opacity(0.06)
  }

  static var panelShadow: Color {
    Color.black.opacity(0.08)
  }

  static var railFill: Color {
    Color(nsColor: .windowBackgroundColor).opacity(0.92)
  }

  static var railStroke: Color {
    Color.primary.opacity(0.05)
  }
}

private struct VideoEditorSidebarPanelStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .clipShape(RoundedRectangle(cornerRadius: VideoEditorSidebarChrome.cornerRadius, style: .continuous))
      .background(
        RoundedRectangle(cornerRadius: VideoEditorSidebarChrome.cornerRadius, style: .continuous)
          .fill(VideoEditorSidebarChrome.panelFill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: VideoEditorSidebarChrome.cornerRadius, style: .continuous)
          .stroke(VideoEditorSidebarChrome.panelStroke, lineWidth: 1)
      )
      .shadow(
        color: VideoEditorSidebarChrome.panelShadow,
        radius: VideoEditorSidebarChrome.shadowRadius,
        x: 0,
        y: VideoEditorSidebarChrome.shadowYOffset
      )
  }
}

private struct VideoEditorSidebarRailStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: VideoEditorSidebarChrome.railCornerRadius, style: .continuous)
          .fill(VideoEditorSidebarChrome.railFill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: VideoEditorSidebarChrome.railCornerRadius, style: .continuous)
          .stroke(VideoEditorSidebarChrome.railStroke, lineWidth: 1)
      )
  }
}

extension View {
  func videoEditorSidebarPanel() -> some View {
    modifier(VideoEditorSidebarPanelStyle())
  }

  func videoEditorSidebarRail() -> some View {
    modifier(VideoEditorSidebarRailStyle())
  }
}

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
