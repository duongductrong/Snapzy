//
//  AnnotateToolbarView.swift
//  ClaudeShot
//
//  Top toolbar with annotation tools and actions
//

import SwiftUI

/// Top toolbar containing all annotation tools
struct AnnotateToolbarView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    HStack(spacing: 8) {
      // Add spacer for traffic lights (macOS standard width ~78px)
      Spacer().frame(width: 78)

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
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - Tool Groups

  private var captureToolsGroup: some View {
    HStack(spacing: 4) {
      ToolbarButton(
        icon: "crop",
        isSelected: state.selectedTool == .crop
      ) {
        state.selectedTool = .crop
        // Initialize crop immediately when tool is selected
        if state.cropRect == nil && state.hasImage {
          state.initializeCrop()
        }
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
    // If we have a source URL, show confirmation to replace or save copy
    if let sourceURL = state.sourceURL {
      showSaveConfirmation(for: sourceURL)
    } else {
      // No source URL (dropped image without file path) - show save panel
      AnnotateExporter.saveAs(state: state, closeWindow: true)
    }
  }

  private func showSaveConfirmation(for sourceURL: URL) {
    let alert = NSAlert()
    alert.messageText = "Save Changes"
    alert.informativeText = "How would you like to save your changes to \"\(sourceURL.lastPathComponent)\"?"
    alert.alertStyle = .informational

    alert.addButton(withTitle: "Replace Original")
    alert.addButton(withTitle: "Save as Copy")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()

    switch response {
    case .alertFirstButtonReturn:
      // Replace original
      AnnotateExporter.saveToOriginal(state: state)
      state.markAsSaved()
      NSApp.keyWindow?.close()

    case .alertSecondButtonReturn:
      // Save as copy - generate copy filename in same directory
      let copyURL = AnnotateExporter.generateCopyURL(from: sourceURL)
      AnnotateExporter.save(state: state, to: copyURL)
      state.markAsSaved()
      NSApp.keyWindow?.close()

    default:
      // Cancel - do nothing
      break
    }
  }
}

// MARK: - Supporting Views

struct ToolbarButton: View {
  let icon: String
  let isSelected: Bool
  var highlightColor: Color = .primary

  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(isSelected ? highlightColor : .primary)
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
      return Color.primary.opacity(0.1)
    }
    return Color.clear
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
