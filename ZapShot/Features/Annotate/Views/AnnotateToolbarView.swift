//
//  AnnotateToolbarView.swift
//  ZapShot
//
//  Top toolbar with annotation tools and actions
//

import SwiftUI

/// Top toolbar containing all annotation tools
struct AnnotateToolbarView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    HStack(spacing: 8) {
      // Left group: Capture tools
      captureToolsGroup

      ToolbarDivider()

      // Center group: Annotation tools
      annotationToolsGroup

      ToolbarDivider()

      // Undo/Redo
      undoRedoGroup

      ToolbarDivider()

      // Placeholder for video recording
      ToolbarButton(icon: "video", isSelected: false) {}
        .disabled(true)
        .opacity(0.5)

      Spacer()

      // Right group: Stroke size and actions
      strokeSizeSlider

      Spacer().frame(width: 16)

      actionButtons
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color(white: 0.15))
  }

  // MARK: - Tool Groups

  private var captureToolsGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(
        icon: "crop",
        isSelected: state.selectedTool == .crop
      ) {
        state.selectedTool = .crop
      }

      ToolbarButton(
        icon: "rectangle.on.rectangle",
        isSelected: state.showSidebar,
        highlightColor: .blue
      ) {
        withAnimation(.easeInOut(duration: 0.2)) {
          state.showSidebar.toggle()
        }
      }

      ToolbarButton(icon: "photo", isSelected: false) {}
        .disabled(true)
        .opacity(0.5)
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
      }
    }
  }

  private var drawingTools: [AnnotationToolType] {
    [.selection, .rectangle, .oval, .arrow, .line, .text, .highlighter, .blur, .counter, .pencil]
  }

  private var undoRedoGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(icon: "arrow.uturn.backward", isSelected: false) {
        state.undo()
      }
      .disabled(!state.canUndo)
      .opacity(state.canUndo ? 1 : 0.4)

      ToolbarButton(icon: "arrow.uturn.forward", isSelected: false) {
        state.redo()
      }
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
    // Save to original file and close
    AnnotateExporter.saveToOriginal(state: state)
    NSApp.keyWindow?.close()
  }
}

// MARK: - Supporting Views

struct ToolbarButton: View {
  let icon: String
  let isSelected: Bool
  var highlightColor: Color = .white

  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(isSelected ? highlightColor : .white)
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
        )
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
  }

  private var backgroundColor: Color {
    if isSelected {
      return highlightColor.opacity(0.3)
    } else if isHovering {
      return Color.white.opacity(0.1)
    }
    return Color.clear
  }
}

struct ToolbarDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.white.opacity(0.2))
      .frame(width: 1, height: 20)
      .padding(.horizontal, 4)
  }
}
