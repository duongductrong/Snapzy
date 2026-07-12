//
//  AnnotateToolbarView.swift
//  Snapzy
//
//  Top toolbar with annotation tools and actions
//

import SwiftUI

private enum AnnotateToolbarActionRegistration: Equatable {
  case annotateDefault
  case crop
}

/// Top toolbar containing all annotation tools
struct AnnotateToolbarView: View {
  @ObservedObject var state: AnnotateState
  @AppStorage(PreferencesKeys.backgroundCutoutAutoCropEnabled) private var backgroundCutoutAutoCropEnabled = true

  var body: some View {
    HStack(spacing: WindowSpacingConfiguration.default.toolbarItemSpacing) {
      // Add spacer for traffic lights
      Spacer().frame(width: 0)

      // Left group: Capture tools
      captureToolsGroup

      ToolbarDivider()

      // Center group: Annotation tools
      annotationToolsGroup

      ToolbarDivider()

      // Undo/Redo
      undoRedoGroup

      ToolbarDivider()

      if state.isCombineMode {
        ToolbarButton(icon: "photo.badge.plus", isSelected: false) {
          guard let window = NSApp.keyWindow else { return }
          NotificationCenter.default.post(name: .annotateAddImage, object: window)
        }
        .help(L10n.Combine.pickerTitle)

        ToolbarDivider()
      }

      Spacer()

      registeredActionButtons
    }
    .windowTrafficLightsInset()
    .windowToolbarPadding()
    .animation(.easeInOut(duration: 0.16), value: activeActionRegistration)
    .alert(
      L10n.AnnotateUI.backgroundCutoutTitle,
      isPresented: Binding(
        get: { state.cutoutErrorMessage != nil },
        set: { if !$0 { state.cutoutErrorMessage = nil } }
      )
    ) {
      Button(L10n.Common.ok, role: .cancel) {}
    } message: {
      Text(state.cutoutErrorMessage ?? L10n.AnnotateUI.unableToRemoveBackground)
    }
  }

  // MARK: - Tool Groups

  private var captureToolsGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(
        icon: "crop",
        isSelected: state.selectedTool == .crop
      ) {
        state.beginCropInteraction()
      }
      .help(L10n.AnnotateUI.crop)

      ToolbarButton(
        icon: "rectangle.on.rectangle",
        isSelected: state.showSidebar,
        highlightColor: .blue
      ) {
        state.toggleSidebarVisibility()
      }
      .help(L10n.AnnotateUI.toggleSidebar)

      ToolbarDivider()

      rotateButtonsGroup
    }
  }

  private var rotateButtonsGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(icon: "rotate.left", isSelected: false) {
        state.rotateImage(clockwise: false)
      }
      .help(L10n.AnnotateUI.rotateLeft)
      .disabled(!state.canRotateImage)
      .opacity(state.canRotateImage ? 1 : 0.4)

      ToolbarButton(icon: "rotate.right", isSelected: false) {
        state.rotateImage(clockwise: true)
      }
      .help(L10n.AnnotateUI.rotateRight)
      .disabled(!state.canRotateImage)
      .opacity(state.canRotateImage ? 1 : 0.4)
    }
  }

  private var annotationToolsGroup: some View {
    HStack(spacing: 4) {
      annotationToolButton(for: .selection)

      ForEach(drawingTools, id: \.self) { tool in
        annotationToolButton(for: tool)
      }

      backgroundCutoutButton
        .padding(.leading, 2)
    }
  }

  private var drawingTools: [AnnotationToolType] {
    AnnotationToolType.drawableTools
  }

  private var backgroundCutoutButton: some View {
    ToolbarButton(
      icon: state.isCutoutProcessing ? "hourglass" : "wand.and.stars",
      isSelected: state.isCutoutApplied,
      highlightColor: .blue
    ) {
      state.toggleBackgroundCutout()
    }
    .disabled(!state.canUseBackgroundCutout || !state.hasImage || state.isCutoutProcessing)
    .opacity((!state.canUseBackgroundCutout || !state.hasImage) ? 0.4 : 1)
    .help(
      state.canUseBackgroundCutout
        ? (state.isCutoutApplied
          ? L10n.AnnotateUI.backgroundRemovedClickToRestore
          : (backgroundCutoutAutoCropEnabled
            ? L10n.AnnotateUI.removeBackgroundAutoCropsWhenSafe
            : L10n.AnnotateUI.removeBackgroundAutoCropDisabledInSettings))
        : L10n.AnnotateUI.requiresMacOS14OrLater
    )
  }

  @ViewBuilder
  private func annotationToolButton(for tool: AnnotationToolType) -> some View {
    ToolbarButton(
      icon: tool.icon,
      isSelected: state.selectedTool == tool
    ) {
      state.activateTool(tool)
    }
    .help(tool.displayName)
    .disabled(state.editorMode == .mockup && tool != .selection)
    .opacity(state.editorMode == .mockup && tool != .selection ? 0.4 : 1)
  }

  private var undoRedoGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(icon: "arrow.uturn.backward", isSelected: false) {
        state.undo()
      }
      .help(L10n.Common.undo)
      .disabled(!state.canUndo)
      .opacity(state.canUndo ? 1 : 0.4)

      ToolbarButton(icon: "arrow.uturn.forward", isSelected: false) {
        state.redo()
      }
      .help(L10n.Common.redo)
      .disabled(!state.canRedo)
      .opacity(state.canRedo ? 1 : 0.4)
    }
  }

  private var activeActionRegistration: AnnotateToolbarActionRegistration {
    if state.selectedTool == .crop && state.isCropActive {
      return .crop
    }

    return .annotateDefault
  }

  @ViewBuilder
  private var registeredActionButtons: some View {
    switch activeActionRegistration {
    case .annotateDefault:
      annotateActionButtons
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    case .crop:
      cropActionButtons
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }
  }

  private var annotateActionButtons: some View {
    HStack(spacing: 8) {
      Button(L10n.Common.saveAs) {
        saveAs()
      }
      .buttonStyle(.bordered)

      Button(L10n.Common.done) {
        done()
      }
      .buttonStyle(.borderedProminent)
      .tint(.blue)
    }
  }

  private var cropActionButtons: some View {
    HStack(spacing: 8) {
      Button("\(L10n.Common.restore) \(L10n.Common.original)") {
        state.revertCropToOriginalBounds()
      }
      .buttonStyle(.bordered)
      .help("\(L10n.Common.restore) \(L10n.Common.original)")

      Button(L10n.Common.cancel) {
        state.cancelCrop()
      }
      .buttonStyle(.bordered)

      Button(L10n.Common.apply) {
        state.confirmCropInteraction()
      }
      .buttonStyle(.borderedProminent)
      .tint(.blue)
    }
  }

  // MARK: - Actions

  private func saveAs() {
    if state.isCombineMode {
      guard let window = NSApp.keyWindow else { return }
      NotificationCenter.default.post(name: .annotateSave, object: window)
    } else {
      AnnotateExporter.saveAs(state: state, closeWindow: true)
    }
  }

  private func done() {
    // Post save notification — controller handles silent save + cache + QA refresh + close
    guard let window = NSApp.keyWindow else { return }
    NotificationCenter.default.post(name: .annotateSave, object: window)
  }
}
