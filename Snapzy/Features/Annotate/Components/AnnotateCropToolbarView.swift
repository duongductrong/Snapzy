//
//  CropToolbarView.swift
//  Snapzy
//
//  Floating toolbar for crop tool with aspect ratio presets and controls
//

import SwiftUI

/// Floating toolbar displayed during crop mode
struct CropToolbarView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    HStack(spacing: 12) {
      // Aspect ratio picker
      aspectRatioPicker

      Divider()
        .frame(height: 20)

      // Grid toggle
      gridToggle

      Divider()
        .frame(height: 20)

      // Action buttons
      actionButtons
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(.ultraThinMaterial)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    )
  }

  // MARK: - Aspect Ratio Picker

  private var aspectRatioPicker: some View {
    HStack(spacing: 4) {
      ForEach(CropAspectRatio.allCases) { ratio in
        CropRatioButton(
          ratio: ratio,
          isSelected: state.cropAspectRatio == ratio
        ) {
          state.applyCropAspectRatio(ratio)
        }
      }
    }
  }

  // MARK: - Grid Toggle

  private var gridToggle: some View {
    Button {
      state.showCropGrid.toggle()
    } label: {
      Image(systemName: state.showCropGrid ? "grid" : "grid.circle")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(state.showCropGrid ? .blue : .primary)
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(state.showCropGrid ? Color.blue.opacity(0.2) : Color.clear)
        )
    }
    .buttonStyle(.plain)
    .help(L10n.AnnotateUI.toggleRuleOfThirdsGrid)
  }

  // MARK: - Action Buttons

  private var actionButtons: some View {
    HStack(spacing: 8) {
      Button(L10n.Common.cancel) {
        state.cancelCrop()
      }
      .buttonStyle(.bordered)
      .controlSize(.small)

      Button(L10n.Common.apply) {
        state.applyCrop()
        state.selectedTool = .selection
      }
      .buttonStyle(.borderedProminent)
      .tint(.blue)
      .controlSize(.small)
    }
  }
}

// MARK: - Aspect Ratio Button

struct CropRatioButton: View {
  let ratio: CropAspectRatio
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Text(ratio.displayName)
        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        .foregroundColor(isSelected ? .blue : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(backgroundColor)
        )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }

  private var backgroundColor: Color {
    if isSelected {
      return Color.blue.opacity(0.2)
    } else if isHovering {
      return Color.primary.opacity(0.1)
    }
    return Color.clear
  }
}
