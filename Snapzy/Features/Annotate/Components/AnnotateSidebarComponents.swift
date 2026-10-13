//
//  AnnotateSidebarComponents.swift
//  Snapzy
//
//  Reusable components for the annotation sidebar
//

import AppKit
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
      Radius.rect(Radius.tile)
        .fill(LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Placeholders

struct WallpaperPlaceholder: View {
  var body: some View {
    Radius.rect(Radius.tile)
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
      Radius.rect(Radius.tile)
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

// MARK: - Default Wallpaper Button

struct DefaultWallpaperButton: View {
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
        Text(L10n.Onboarding.grantAccess)
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
    Radius.rect(Radius.tile)
      .fill(Color.gray.opacity(0.2))
      .frame(width: Size.gridItem, height: Size.gridItem)
      .blur(radius: 2)
  }
}

struct BlurredBackgroundEffectButton: View {
  let effect: BlurredBackgroundEffect
  let backgroundStyle: BackgroundStyle
  let previewImage: NSImage?
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        previewLayer

        effect.tintColor
          .opacity(effect.tintOpacity)
      }
      .clipped()
      .sidebarItemStyle(isSelected: isSelected)
    }
    .buttonStyle(.plain)
    .help(effect.displayName)
  }

  @ViewBuilder
  private var previewLayer: some View {
    switch backgroundStyle {
    case let .solidColor(color):
      color
        .brightness(effect.brightness)
    case .wallpaper, .blurred:
      if let previewImage {
        Image(nsImage: previewImage)
          .resizable()
          .aspectRatio(1, contentMode: .fill)
          .blur(radius: min(effect.blurRadius / 4, 8))
          .saturation(effect.saturation)
          .brightness(effect.brightness)
      } else {
        placeholderLayer
      }
    case .none, .gradient:
      placeholderLayer
    }
  }

  private var placeholderLayer: some View {
    LinearGradient(
      colors: [.secondary.opacity(0.25), .secondary.opacity(0.08)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .blur(radius: min(effect.blurRadius / 4, 8))
  }
}

// MARK: - Color Swatch Grid

struct ColorSwatchGrid: View {
  @Binding var selectedColor: Color?
  @ObservedObject private var paletteStore = AnnotateColorPaletteStore.shared
  @State private var draftCustomColor = Color.red

  private let colors: [[Color]] = [
    [.red, .orange, .yellow, .green, .blue, .purple, .pink],
    [.gray, .white, .black, Color(white: 0.3), Color(white: 0.5), Color(white: 0.7), Color(white: 0.9)],
  ]

  var body: some View {
    VStack(spacing: Spacing.sm) {
      ForEach(0 ..< colors.count, id: \.self) { row in
        HStack(spacing: Spacing.sm) {
          ForEach(0 ..< colors[row].count, id: \.self) { col in
            ColorSwatch(
              color: colors[row][col],
              isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, colors[row][col])
            ) {
              selectedColor = colors[row][col]
            }
          }
        }
      }

      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: GridConfig.gap), count: GridConfig.colorColumns),
        spacing: GridConfig.gap
      ) {
        ForEach(paletteStore.customColors, id: \.self) { color in
          AnnotateColorSwatchButton(
            color: color,
            isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
            size: Size.colorSwatchSmall,
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
          swatchSize: Size.colorSwatchSmall
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

struct AnnotateColorSwatchButton: View {
  let color: Color
  let isSelected: Bool
  let size: CGFloat?
  var onDelete: (() -> Void)? = nil
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      swatch
    }
    .buttonStyle(.plain)
    .overlay(alignment: .topTrailing) {
      deleteButton
    }
    .frame(width: size, height: size)
  }

  @ViewBuilder private var swatch: some View {
    if let size {
      AnnotateColorSwatchCircle(
        color: color,
        isSelected: isSelected,
        size: size
      )
    } else {
      AnnotateFlexibleColorSwatchCircle(
        color: color,
        isSelected: isSelected
      )
    }
  }

  @ViewBuilder private var deleteButton: some View {
    if let onDelete {
      Button(action: onDelete) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: deleteIconSize, weight: .semibold))
          .symbolRenderingMode(.palette)
          .foregroundStyle(Color.white, Color.secondary.opacity(0.9))
          .background(
            Circle()
              .fill(SidebarColors.itemDefault)
              .frame(width: deleteBackgroundSize, height: deleteBackgroundSize)
          )
      }
      .buttonStyle(.plain)
      .offset(x: 4, y: -4)
      .help(L10n.Common.deleteAction)
      .accessibilityLabel(L10n.Common.deleteAction)
    }
  }

  private var deleteIconSize: CGFloat {
    guard let size else { return 10 }
    return max(10, size * 0.48)
  }

  private var deleteBackgroundSize: CGFloat {
    guard let size else { return 9 }
    return max(9, size * 0.42)
  }
}

struct AnnotateColorSwatchCircle: View {
  let color: Color
  let isSelected: Bool
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(AnnotateColorPaletteStore.isClear(color) ? Color.clear : color)
        .frame(width: size, height: size)
        .overlay(
          Circle()
            .strokeBorder(
              isSelected ? SidebarColors.borderSelected : Color.secondary.opacity(0.35),
              lineWidth: isSelected ? Size.strokeSelected : Size.strokeDefault
            )
        )

      if AnnotateColorPaletteStore.isClear(color) {
        Image(systemName: "slash.circle")
          .font(.system(size: max(8, size * 0.46), weight: .semibold))
          .foregroundColor(.secondary)
      }
    }
  }
}

struct AnnotateCustomColorPickerControl: View {
  @Binding var selectedColor: Color
  @Binding var draftColor: Color
  let swatchSize: CGFloat?

  @ObservedObject private var paletteStore = AnnotateColorPaletteStore.shared
  @State private var originalSelectedColor: Color?
  @State private var showsPicker = false

  var body: some View {
    Button {
      if showsPicker {
        cancelCustomColorDraft()
      } else {
        beginCustomColorDraft()
      }
    } label: {
      pickerLabel
    }
    .buttonStyle(.plain)
    .frame(width: swatchSize, height: swatchSize)
    .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
      AnnotateCustomColorPickerPanel(
        selectedColor: $selectedColor,
        draftColor: $draftColor,
        onCancel: cancelCustomColorDraft,
        onApply: applyCustomColorDraft
      )
      .padding(10)
      .frame(width: 196, alignment: .leading)
      .onDisappear {
        cancelCustomColorDraftIfNeeded()
      }
    }
    .help(L10n.Common.custom)
    .accessibilityLabel(L10n.Common.custom)
    .onAppear {
      syncDraftColor(with: selectedColor)
    }
    .onChange(of: selectedColor) { color in
      syncDraftColor(with: color)
    }
  }

  @ViewBuilder private var pickerLabel: some View {
    if showsPicker {
      if let swatchSize {
        AnnotateColorSwatchCircle(
          color: draftColor,
          isSelected: true,
          size: swatchSize
        )
      } else {
        AnnotateFlexibleColorSwatchCircle(
          color: draftColor,
          isSelected: true
        )
      }
    } else if let swatchSize {
      AnnotateAddColorSwatch(size: swatchSize)
    } else {
      AnnotateFlexibleAddColorSwatch()
    }
  }

  private func syncDraftColor(with color: Color) {
    guard !AnnotateColorPaletteStore.isClear(color) else { return }
    draftColor = color
  }

  private func beginCustomColorDraft() {
    originalSelectedColor = selectedColor
    syncDraftColor(with: selectedColor)
    selectedColor = draftColor
    showsPicker = true
  }

  private func applyCustomColorDraft() {
    guard !AnnotateColorPaletteStore.isClear(draftColor) else { return }
    paletteStore.addColor(draftColor)
    selectedColor = draftColor
    originalSelectedColor = nil
    showsPicker = false
  }

  private func cancelCustomColorDraft() {
    guard let originalSelectedColor else {
      showsPicker = false
      return
    }

    selectedColor = originalSelectedColor
    draftColor = originalSelectedColor
    self.originalSelectedColor = nil
    showsPicker = false
  }

  private func cancelCustomColorDraftIfNeeded() {
    guard originalSelectedColor != nil else { return }
    cancelCustomColorDraft()
  }
}

struct AnnotateAddColorSwatch: View {
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(SidebarColors.itemDefault.opacity(0.55))
        .frame(width: size, height: size)
        .overlay(
          Circle()
            .stroke(
              Color.secondary.opacity(0.45),
              style: StrokeStyle(lineWidth: Size.strokeDefault, dash: [3, 2])
            )
        )

      Image(systemName: "plus")
        .font(.system(size: max(9, size * 0.48), weight: .semibold))
        .foregroundColor(.secondary)
    }
    .contentShape(Circle())
  }
}

struct AnnotateFlexibleColorSwatchCircle: View {
  let color: Color
  let isSelected: Bool

  var body: some View {
    ZStack {
      Circle()
        .fill(AnnotateColorPaletteStore.isClear(color) ? Color.clear : color)
        .colorSwatchStyle(isSelected: isSelected)

      if AnnotateColorPaletteStore.isClear(color) {
        Image(systemName: "slash.circle")
          .font(.system(size: 8, weight: .semibold))
          .foregroundColor(.secondary)
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .contentShape(Circle())
  }
}

struct AnnotateFlexibleAddColorSwatch: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(SidebarColors.itemDefault.opacity(0.55))
        .overlay(
          Circle()
            .stroke(
              Color.secondary.opacity(0.45),
              style: StrokeStyle(lineWidth: Size.strokeDefault, dash: [3, 2])
            )
        )

      Image(systemName: "plus")
        .font(.system(size: 9, weight: .semibold))
        .foregroundColor(.secondary)
    }
    .aspectRatio(1, contentMode: .fit)
    .contentShape(Circle())
  }
}

struct AnnotateCustomColorPickerPanel: View {
  @Binding var selectedColor: Color
  @Binding var draftColor: Color
  let onCancel: () -> Void
  let onApply: () -> Void

  @State private var hsba = HSBAColor(color: .red)

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      AnnotateColorSpectrumField(hsba: $hsba) {
        applyDraftColor()
      }
      .frame(height: 118)

      AnnotateHueSlider(hue: $hsba.hue) {
        applyDraftColor()
      }
      .frame(height: 14)

      AnnotateAlphaSlider(hsba: $hsba) {
        applyDraftColor()
      }
      .frame(height: 14)

      HStack(spacing: 8) {
        Button(L10n.Common.cancel) {
          onCancel()
        }
        .controlSize(.small)
        .keyboardShortcut(.cancelAction)

        Spacer(minLength: 0)

        Button(L10n.Common.apply) {
          onApply()
        }
        .controlSize(.small)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(AnnotateColorPaletteStore.isClear(draftColor))
      }
      .padding(.top, 2)
    }
    .onAppear {
      syncHSBA(with: draftColor)
    }
  }

  private func syncHSBA(with color: Color) {
    guard !AnnotateColorPaletteStore.isClear(color) else { return }
    draftColor = color
    hsba = HSBAColor(color: color)
  }

  private func applyDraftColor() {
    let color = hsba.color
    draftColor = color
    selectedColor = color
  }
}

private struct AnnotateColorSpectrumField: View {
  @Binding var hsba: HSBAColor
  let onChange: () -> Void

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Rectangle()
          .fill(Color(hue: hsba.hue, saturation: 1, brightness: 1))

        Rectangle()
          .fill(
            LinearGradient(
              colors: [.white, .white.opacity(0)],
              startPoint: .leading,
              endPoint: .trailing
            )
          )

        Rectangle()
          .fill(
            LinearGradient(
              colors: [.black.opacity(0), .black],
              startPoint: .top,
              endPoint: .bottom
            )
          )

        Circle()
          .strokeBorder(Color.white, lineWidth: 2)
          .background(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1))
          .frame(width: 12, height: 12)
          .position(
            x: CGFloat(hsba.saturation) * proxy.size.width,
            y: CGFloat(1 - hsba.brightness) * proxy.size.height
          )
      }
      .clipShape(Radius.rect(Radius.tile))
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            updateHSBA(location: value.location, size: proxy.size)
          }
      )
    }
  }

  private func updateHSBA(location: CGPoint, size: CGSize) {
    let width = max(size.width, 1)
    let height = max(size.height, 1)
    var nextValue = hsba
    nextValue.saturation = clamped(Double(location.x / width))
    nextValue.brightness = clamped(1 - Double(location.y / height))
    hsba = nextValue
    onChange()
  }
}

private struct AnnotateHueSlider: View {
  @Binding var hue: Double
  let onChange: () -> Void

  private var hueColors: [Color] {
    (0 ... 6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(LinearGradient(colors: hueColors, startPoint: .leading, endPoint: .trailing))

        Circle()
          .fill(Color.white)
          .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
          .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
          .frame(width: 14, height: 14)
          .offset(x: CGFloat(hue) * max(proxy.size.width - 14, 1))
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            hue = clamped(Double(value.location.x / max(proxy.size.width, 1)))
            onChange()
          }
      )
    }
  }
}

private struct AnnotateAlphaSlider: View {
  @Binding var hsba: HSBAColor
  let onChange: () -> Void

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(
            LinearGradient(
              colors: [
                Color(hue: hsba.hue, saturation: hsba.saturation, brightness: hsba.brightness, opacity: 0),
                Color(hue: hsba.hue, saturation: hsba.saturation, brightness: hsba.brightness, opacity: 1),
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .overlay(Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 1))

        Circle()
          .fill(Color.white)
          .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
          .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
          .frame(width: 14, height: 14)
          .offset(x: CGFloat(hsba.alpha) * max(proxy.size.width - 14, 1))
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            var nextValue = hsba
            nextValue.alpha = clamped(Double(value.location.x / max(proxy.size.width, 1)))
            hsba = nextValue
            onChange()
          }
      )
    }
  }
}

private struct HSBAColor: Equatable {
  var hue: Double
  var saturation: Double
  var brightness: Double
  var alpha: Double

  init(hue: Double, saturation: Double, brightness: Double, alpha: Double) {
    self.hue = clamped(hue)
    self.saturation = clamped(saturation)
    self.brightness = clamped(brightness)
    self.alpha = clamped(alpha)
  }

  init(color: Color) {
    guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
      self.init(hue: 0, saturation: 1, brightness: 1, alpha: 1)
      return
    }

    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 0
    srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

    self.init(
      hue: Double(hue),
      saturation: Double(saturation),
      brightness: Double(brightness),
      alpha: Double(alpha)
    )
  }

  var color: Color {
    Color(hue: hue, saturation: saturation, brightness: brightness, opacity: alpha)
  }
}

private func clamped(_ value: Double) -> Double {
  min(max(value, 0), 1)
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
    [.bottomLeft, .bottom, .bottomRight],
  ]

  var body: some View {
    VStack(spacing: 2) {
      ForEach(0 ..< 3, id: \.self) { row in
        HStack(spacing: 2) {
          ForEach(0 ..< 3, id: \.self) { col in
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
    .cornerRadius(Radius.tile)
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
        .cornerRadius(Radius.ornament)
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
