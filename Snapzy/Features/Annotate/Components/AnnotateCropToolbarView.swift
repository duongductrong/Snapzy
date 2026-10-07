//
//  CropToolbarView.swift
//  Snapzy
//
//  Bottom control surface for crop tool with aspect ratio presets and grid toggle
//

import SwiftUI

/// Shared snapping glyph: crop toolbar, highlighter quick properties, and
/// annotate preferences all use it so "snapping" reads the same everywhere.
enum CropToolbarSymbols {
  /// `magnet` is SF Symbols 5 (macOS 14+); fall back on macOS 13.
  static let snapToEdges =
    NSImage(systemSymbolName: "magnet", accessibilityDescription: nil) != nil ? "magnet" : "square.dashed"
}

/// Bottom control surface displayed while crop mode owns the shared bottom action slot.
struct CropToolbarView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    HStack(spacing: 8) {
      // Aspect ratio picker
      aspectRatioPicker

      ToolbarDivider()

      // Grid toggle
      gridToggle

      // Snap-to-edges toggle
      snapToggle

      // Auto-crop to content (same as the `A` shortcut)
      autoCropButton
    }
    .liquidGlassGroup(spacing: Spacing.xs)
  }

  // MARK: - Aspect Ratio Picker

  private var aspectRatioPicker: some View {
    HStack(spacing: 4) {
      ForEach(CropAspectRatio.allCases) { ratio in
        CropRatioButton(
          ratio: ratio,
          isSelected: state.cropAspectRatio == ratio,
          isPortrait: state.isCropPortraitOrientation
        ) {
          state.applyCropAspectRatio(ratio)
        }
      }

      if state.cropAspectRatio != .free, state.cropAspectRatio != .square {
        ToolbarDivider()

        orientationToggle
      }
    }
  }

  // MARK: - Orientation Toggle

  private var orientationToggle: some View {
    CropToolbarIconButton(
      icon: state.isCropPortraitOrientation ? "rectangle.portrait" : "rectangle",
      isActive: false,
      tooltip: L10n.AnnotateUI.toggleCropOrientation
    ) {
      state.toggleCropOrientation()
    }
  }

  // MARK: - Grid Toggle

  private var gridToggle: some View {
    CropToolbarIconButton(
      icon: state.showCropGrid ? "grid" : "grid.circle",
      isActive: state.showCropGrid,
      tooltip: L10n.AnnotateUI.toggleRuleOfThirdsGrid
    ) {
      state.showCropGrid.toggle()
    }
  }

  // MARK: - Snap Toggle

  private var snapToggle: some View {
    CropToolbarIconButton(
      icon: CropToolbarSymbols.snapToEdges,
      isActive: state.isCropEdgeSnappingEnabled,
      tooltip: "\(L10n.AnnotateUI.cropSnapToEdges) — \(L10n.AnnotateUI.cropSnapToEdgesHint)"
    ) {
      state.isCropEdgeSnappingEnabled.toggle()
    }
  }

  // MARK: - Auto-Crop Button

  private var autoCropButton: some View {
    CropToolbarIconButton(
      icon: "arrow.up.left.and.arrow.down.right",
      isActive: false,
      tooltip: L10n.AnnotateUI.autoCropToContent
    ) {
      Task { @MainActor in
        await state.autoCropToContent()
      }
    }
  }
}

// MARK: - Crop Toolbar Icon Button

struct CropToolbarIconButton: View {
  /// Matches `ControlMetrics.toolbarButton`: the crop toolbar takes over the same bottom-bar slot
  /// as `BottomBarButton`, so the two have to share a height *and* a corner radius.
  static let height = ControlMetrics.toolbarButton

  let icon: String
  var isActive: Bool = false
  let tooltip: String
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(foregroundColor)
        .frame(width: Self.height, height: Self.height)
        .liquidGlassControl(
          isActive: isActive,
          in: Radius.controlRect(forHeight: Self.height)
        )
    }
    .buttonStyle(.plain)
    .help(tooltip)
  }

  private var foregroundColor: Color {
    guard isEnabled else { return Color.primary.opacity(0.4) }
    return isActive ? LiquidGlassTokens.inkOnAccent : Color.primary
  }
}

// MARK: - Aspect Ratio Button

struct CropRatioButton: View {
  static let height = ControlMetrics.toolbarButton

  let ratio: CropAspectRatio
  let isSelected: Bool
  let isPortrait: Bool
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      Text(displayName)
        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
        .foregroundColor(foregroundColor)
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .liquidGlassControl(
          isActive: isSelected,
          in: Capsule(style: .continuous)
        )
    }
    .buttonStyle(.plain)
  }

  private var displayName: String {
    isSelected ? ratio.effectiveDisplayName(isPortrait: isPortrait) : ratio.displayName
  }

  private var foregroundColor: Color {
    guard isEnabled else { return Color.primary.opacity(0.4) }
    return isSelected ? LiquidGlassTokens.inkOnAccent : Color.primary
  }
}
