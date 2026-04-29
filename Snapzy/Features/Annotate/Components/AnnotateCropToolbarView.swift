//
//  CropToolbarView.swift
//  Snapzy
//
//  Bottom control surface for crop tool with aspect ratio presets and grid toggle
//

import SwiftUI

/// Bottom control surface displayed while crop mode owns the shared bottom action slot.
struct CropToolbarView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    HStack(spacing: 10) {
      // Aspect ratio picker
      aspectRatioPicker

      Divider()
        .frame(height: 20)

      // Grid toggle
      gridToggle
    }
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
        .foregroundStyle(state.showCropGrid ? Color.accentColor : Color.primary)
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(state.showCropGrid ? Color.accentColor.opacity(0.2) : Color.clear)
        )
    }
    .buttonStyle(.plain)
    .help(L10n.AnnotateUI.toggleRuleOfThirdsGrid)
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
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
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
      return Color.accentColor.opacity(0.2)
    } else if isHovering {
      return Color.primary.opacity(0.1)
    }
    return Color.clear
  }
}
