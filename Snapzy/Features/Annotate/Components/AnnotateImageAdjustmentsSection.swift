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

  private let presetColumns = Array(
    repeating: GridItem(.flexible(), spacing: Spacing.xs),
    count: 4
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

      LazyVGrid(columns: presetColumns, spacing: Spacing.sm) {
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
          var updated = state.imageAdjustments
          updated[keyPath: keyPath] = Double(newValue).rounded()
          state.setImageAdjustments(updated)
        }
      ),
      range: CGFloat(range.lowerBound) ... CGFloat(range.upperBound),
      onDragging: { isDragging, value in
        if isDragging {
          var updated = state.imageAdjustments
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

  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        ZStack {
          Radius.rect(Radius.tile)
            .fill(SidebarColors.itemDefault)
          if let thumbnail {
            Image(nsImage: thumbnail)
              .resizable()
              .interpolation(.medium)
              .aspectRatio(contentMode: .fill)
          }
        }
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .clipShape(Radius.rect(Radius.tile))
        .sidebarItemStyle(isSelected: isSelected)

        Text(preset.displayName)
          .font(Typography.labelSmall)
          .foregroundColor(isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(preset.displayName)
    .accessibilityLabel(preset.displayName)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
