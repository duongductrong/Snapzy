//
//  CutOutToolbarView.swift
//  Snapzy
//
//  Bottom control surface for the cut out tool with strip orientation and
//  remove/insert mode toggles. Mirrors CropToolbarView.
//

import SwiftUI

/// Bottom control surface displayed while cut out mode owns the shared bottom
/// action slot.
struct CutOutToolbarView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    HStack(spacing: 8) {
      orientationToggle
      ToolbarDivider()
      modeToggle
    }
    .liquidGlassGroup(spacing: Spacing.xs)
  }

  private var orientationToggle: some View {
    HStack(spacing: 4) {
      CropToolbarIconButton(
        icon: "rectangle.split.1x2",
        isActive: state.cutOutOrientation == .horizontal,
        tooltip: L10n.AnnotateUI.cutOutHorizontal
      ) {
        state.cutOutOrientation = .horizontal
      }

      CropToolbarIconButton(
        icon: "rectangle.split.2x1",
        isActive: state.cutOutOrientation == .vertical,
        tooltip: L10n.AnnotateUI.cutOutVertical
      ) {
        state.cutOutOrientation = .vertical
      }
    }
  }

  private var modeToggle: some View {
    HStack(spacing: 4) {
      CropToolbarIconButton(
        icon: "minus.square",
        isActive: state.cutOutMode == .remove,
        tooltip: L10n.AnnotateUI.cutOutRemove
      ) {
        state.cutOutMode = .remove
      }

      CropToolbarIconButton(
        icon: "plus.square",
        isActive: state.cutOutMode == .insert,
        tooltip: L10n.AnnotateUI.cutOutInsert
      ) {
        state.cutOutMode = .insert
      }
    }
  }
}
