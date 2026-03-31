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

      // Right group: Stroke size and actions
      strokeSizeSlider

      Spacer().frame(width: 16)

      actionButtons
    }
    .windowTrafficLightsInset()
    .windowToolbarPadding()
    .alert(
      "Background Cutout",
      isPresented: Binding(
        get: { state.cutoutErrorMessage != nil },
        set: { if !$0 { state.cutoutErrorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(state.cutoutErrorMessage ?? "Unable to remove background.")
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
      .help("Crop")

      ToolbarButton(
        icon: state.isCutoutProcessing ? "hourglass" : "person.crop.rectangle",
        selectedIcon: "person.crop.rectangle.fill",
        isSelected: state.isCutoutApplied
      ) {
        state.toggleBackgroundCutout()
      }
      .disabled(!state.canUseBackgroundCutout || !state.hasImage || state.isCutoutProcessing)
      .opacity((!state.canUseBackgroundCutout || !state.hasImage) ? 0.4 : 1)
      .help(
        state.canUseBackgroundCutout
          ? (state.isCutoutApplied ? "Background Removed (Click to restore)" : "Remove Background")
          : "Requires macOS 14+"
      )

      ToolbarButton(
        icon: "rectangle.on.rectangle",
        isSelected: state.showSidebar,
        highlightColor: .blue
      ) {
        withAnimation(.easeInOut(duration: 0.2)) {
          state.showSidebar.toggle()
        }
      }
      .help("Toggle sidebar")
    }
  }

  private var annotationToolsGroup: some View {
    HStack(spacing: 4) {
      ForEach(drawingTools, id: \.self) { tool in
        ToolbarButton(
          icon: tool.icon,
          isSelected: state.selectedTool == tool
        ) {
          state.selectedTool = tool
        }
        .help(tool.displayName)
        .disabled(state.editorMode == .mockup && tool != .selection)
        .opacity(state.editorMode == .mockup && tool != .selection ? 0.4 : 1)
      }
    }
  }

  private var drawingTools: [AnnotationToolType] {
    [.selection, .rectangle, .filledRectangle, .oval, .arrow, .line, .text, .highlighter, .blur, .counter, .pencil]
  }

  private var undoRedoGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(icon: "arrow.uturn.backward", isSelected: false) {
        state.undo()
      }
      .help("Undo")
      .disabled(!state.canUndo)
      .opacity(state.canUndo ? 1 : 0.4)

      ToolbarButton(icon: "arrow.uturn.forward", isSelected: false) {
        state.redo()
      }
      .help("Redo")
      .disabled(!state.canRedo)
      .opacity(state.canRedo ? 1 : 0.4)
    }
  }

  private var strokeSizeSlider: some View {
    HStack(spacing: 8) {
      Image(systemName: "line.diagonal")
        .font(.system(size: 10))
        .foregroundColor(.gray)

      Slider(value: $state.strokeWidth, in: 1...20, step: 1)
        .frame(width: 80)

      Image(systemName: "line.diagonal")
        .font(.system(size: 16))
        .foregroundColor(.gray)
    }
  }

  private var actionButtons: some View {
    HStack(spacing: 8) {
      Button("Save as...") {
        saveAs()
      }
      .buttonStyle(.bordered)

      Button("Done") {
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
