//
//  AnnotateToolbarView.swift
//  Snapzy
//
//  Top toolbar with annotation tools and actions
//

import SwiftUI

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

      Spacer()

      actionButtons
    }
    .windowTrafficLightsInset()
    .windowToolbarPadding()
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
        withAnimation(.easeInOut(duration: 0.2)) {
          state.showSidebar.toggle()
        }
      }
      .help(L10n.AnnotateUI.toggleSidebar)
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
    [.rectangle, .filledRectangle, .oval, .arrow, .line, .text, .highlighter, .blur, .counter, .pencil]
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

  private var actionButtons: some View {
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

  // MARK: - Actions

  private func saveAs() {
    AnnotateExporter.saveAs(state: state, closeWindow: true)
  }

  private func done() {
    // Post save notification — controller handles silent save + cache + QA refresh + close
    guard let window = NSApp.keyWindow else { return }
    NotificationCenter.default.post(name: .annotateSave, object: window)
  }
}

// MARK: - Supporting Views

struct ToolbarButton: View {
  let icon: String
  var selectedIcon: String? = nil
  let isSelected: Bool
  var highlightColor: Color = .primary
  var selectedForegroundColor: Color? = nil
  var selectedBadgeIcon: String? = nil

  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: displayedIcon)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(foregroundColor)
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
        )
        .overlay(alignment: .topTrailing) {
          if let selectedBadgeIcon, isSelected {
            Image(systemName: selectedBadgeIcon)
              .font(.system(size: 7, weight: .bold))
              .foregroundColor(highlightColor)
              .frame(width: 12, height: 12)
              .background(Circle().fill(Color.white))
              .offset(x: 3, y: -3)
          }
        }
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }

  private var backgroundColor: Color {
    if isSelected {
      return highlightColor.opacity(0.3)
    } else if isHovering {
      return Color.primary.opacity(0.1)
    }
    return Color.clear
  }

  private var displayedIcon: String {
    if isSelected {
      return selectedIcon ?? icon
    }
    return icon
  }

  private var foregroundColor: Color {
    if isSelected {
      return selectedForegroundColor ?? highlightColor
    }
    return .primary
  }
}

struct ToolbarDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color(nsColor: .separatorColor))
      .frame(width: 1, height: 20)
      .padding(.horizontal, 4)
  }
}
