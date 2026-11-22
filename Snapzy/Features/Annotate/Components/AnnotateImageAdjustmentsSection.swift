//
//  AnnotateImageAdjustmentsSection.swift
//  Snapzy
//
//  Sidebar "Adjust" section: tone sliders, filter preset thumbnails and Reset.
//  Takes plain values so the Equatable sidebar only re-renders when they change.
//

import AppKit
import SwiftUI

struct AnnotateImageAdjustmentsSection: View {
  let state: AnnotateState
  let adjustments: ImageAdjustments
  let thumbnails: [ImageFilterPreset: NSImage]

  /// Three columns keep each tile wide enough for a readable thumbnail and a full label in
  /// the 240pt sidebar.
  private let presetColumns = Array(
    repeating: GridItem(.flexible(minimum: 0), spacing: GridConfig.gap, alignment: .top),
    count: 3
  )

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      HStack {
        SidebarSectionHeader(title: L10n.AnnotateAdjust.section)
        Spacer()
        Button(L10n.AnnotateAdjust.reset) {
          state.resetImageAdjustments()
        }
        .buttonStyle(.plain)
        .font(Typography.labelSmall)
        .foregroundColor(adjustments.isIdentity ? SidebarColors.labelTertiary : Color.accentColor)
        .disabled(adjustments.isIdentity)
        .help(L10n.AnnotateAdjust.resetHelp)
      }

      sliderRow(L10n.AnnotateAdjust.brightness, \.brightness, range: ImageAdjustments.toneRange)
      sliderRow(L10n.AnnotateAdjust.contrast, \.contrast, range: ImageAdjustments.toneRange)
      sliderRow(L10n.AnnotateAdjust.saturation, \.saturation, range: ImageAdjustments.toneRange)
      sliderRow(L10n.AnnotateAdjust.sharpness, \.sharpness, range: ImageAdjustments.sharpnessRange)

      Text(L10n.AnnotateAdjust.filters)
        .font(Typography.labelSmall)
        .foregroundColor(SidebarColors.labelSecondary)
        .padding(.top, Spacing.xs)

      LazyVGrid(columns: presetColumns, alignment: .leading, spacing: Spacing.sm) {
        ForEach(ImageFilterPreset.allCases) { preset in
          ImageFilterPresetTile(
            preset: preset,
            thumbnail: thumbnails[preset],
            isSelected: adjustments.preset == preset
          ) {
            state.selectImageFilterPreset(preset)
          }
        }
      }
    }
    .onAppear {
      state.prepareImageFilterPresetThumbnailsIfNeeded()
    }
    .onDisappear {
      // A slider torn down mid-drag never reports its release; commit the step now.
      state.endImageAdjustmentGesture()
    }
  }

  /// One slider drag = one undo step: live values go through the gesture API, the final
  /// value commits on release. Typed values commit immediately.
  private func sliderRow(
    _ label: String,
    _ keyPath: WritableKeyPath<ImageAdjustments, Double>,
    range: ClosedRange<Double>
  ) -> some View {
    CompactSliderRow(
      label: label,
      value: Binding(
        get: { CGFloat(adjustments[keyPath: keyPath]) },
        set: { newValue in
          var updated = state.liveImageAdjustments
          updated[keyPath: keyPath] = Double(newValue).rounded()
          state.setImageAdjustments(updated)
        }
      ),
      range: CGFloat(range.lowerBound) ... CGFloat(range.upperBound),
      onDragging: { isDragging, value in
        if isDragging {
          var updated = state.liveImageAdjustments
          updated[keyPath: keyPath] = Double(value).rounded()
          state.updateImageAdjustmentGesture(updated)
        } else {
          state.endImageAdjustmentGesture()
        }
      }
    )
  }
}

private struct ImageFilterPresetTile: View {
  let preset: ImageFilterPreset
  let thumbnail: NSImage?
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  private static let thumbnailAspectRatio: CGFloat = 4.0 / 3.0

  var body: some View {
    Button(action: action) {
      VStack(spacing: Spacing.xs) {
        // A fixed-ratio clear box sizes the tile from the column width; the thumbnail only
        // fills it as an overlay, so a wide capture can never push past its cell.
        Color.clear
          .aspectRatio(Self.thumbnailAspectRatio, contentMode: .fit)
          .frame(maxWidth: .infinity)
          .background(SidebarColors.itemDefault)
          .overlay {
            if let thumbnail {
              Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.medium)
                .scaledToFill()
            }
          }
          .clipShape(Radius.rect(Radius.tile))
          .overlay {
            Radius.rect(Radius.tile)
              .fill(isHovering && !isSelected ? SidebarColors.itemHover.opacity(0.35) : Color.clear)
          }
          .overlay {
            Radius.rect(Radius.tile)
              .strokeBorder(borderColor, lineWidth: Size.strokeSelected)
          }

        Text(preset.displayName)
          .font(Typography.labelSmall)
          .foregroundColor(isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help(preset.displayName)
    .accessibilityLabel(preset.displayName)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var borderColor: Color {
    if isSelected { return SidebarColors.borderSelected }
    if isHovering { return SidebarColors.borderHover }
    return .clear
  }
}
