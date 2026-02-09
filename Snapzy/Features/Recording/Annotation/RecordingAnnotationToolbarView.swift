//
//  RecordingAnnotationToolbarView.swift
//  Snapzy
//
//  Floating toolbar for annotation tools during recording
//  Supports horizontal and vertical layouts with tool selection,
//  color presets, stroke width, clear-mode config, and drag handle
//

import SwiftUI

// MARK: - Layout Direction

enum AnnotationToolbarDirection {
  case horizontal
  case vertical
}

// MARK: - Toolbar View

struct RecordingAnnotationToolbarView: View {
  @ObservedObject var state: RecordingAnnotationState
  let direction: AnnotationToolbarDirection

  private let colorPresets: [Color] = [.red, .blue, .green, .yellow, .white]
  private let widthPresets: [CGFloat] = [2, 4, 8]

  var body: some View {
    contentLayout
      .padding(.horizontal, direction == .horizontal ? 10 : 6)
      .padding(.vertical, direction == .horizontal ? 6 : 10)
  }

  // MARK: - Layout

  @ViewBuilder
  private var contentLayout: some View {
    if direction == .horizontal {
      HStack(spacing: ToolbarConstants.itemSpacing) { toolbarContent }
    } else {
      VStack(spacing: ToolbarConstants.itemSpacing) { toolbarContent }
    }
  }

  @ViewBuilder
  private var toolbarContent: some View {
    dragHandle
    divider
    toolButtons
    divider
    colorPickers
    divider
    widthPickers
    divider
    clearButton
    clearModeButton
  }

  // MARK: - Tool Buttons

  @ViewBuilder
  private var toolButtons: some View {
    let tools = RecordingAnnotationState.availableTools
    ForEach(tools, id: \.self) { tool in
      AnnotationToolbarIconButton(
        systemName: tool.icon,
        isSelected: state.selectedTool == tool,
        action: { state.selectedTool = tool }
      )
      .help("\(tool.displayName) (\(String(tool.defaultShortcut).uppercased()))")
    }
  }

  // MARK: - Color Presets

  @ViewBuilder
  private var colorPickers: some View {
    ForEach(colorPresets, id: \.self) { color in
      Button {
        state.strokeColor = color
      } label: {
        Circle()
          .fill(color)
          .frame(width: 14, height: 14)
          .overlay(
            Circle()
              .strokeBorder(
                state.strokeColor == color ? Color.primary : Color.clear,
                lineWidth: 2
              )
          )
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Width Presets

  @ViewBuilder
  private var widthPickers: some View {
    ForEach(widthPresets, id: \.self) { width in
      Button {
        state.strokeWidth = width
      } label: {
        RoundedRectangle(cornerRadius: 1)
          .fill(state.strokeWidth == width ? Color.primary : Color.primary.opacity(0.4))
          .frame(
            width: direction == .horizontal ? width * 3 : 16,
            height: direction == .horizontal ? 16 : width * 3
          )
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Clear & Clear Mode

  private var clearButton: some View {
    AnnotationToolbarIconButton(
      systemName: "trash",
      isSelected: false,
      action: { state.clearAll() }
    )
  }

  @ViewBuilder
  private var clearModeButton: some View {
    Menu {
      clearModeMenuContent
    } label: {
      Image(systemName: "timer")
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.primary.opacity(0.85))
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(Color.clear)
        )
    }
    .menuStyle(.borderlessButton)
    .frame(width: 28, height: 28)
  }

  @ViewBuilder
  private var clearModeMenuContent: some View {
    let currentTool = state.selectedTool
    let currentMode = state.clearMode(for: currentTool)

    Text("Auto-clear: \(currentTool.displayName)")
      .font(.caption)

    Divider()

    ForEach(RecordingAnnotationState.clearModePresets, id: \.self) { mode in
      Button {
        state.toolClearModes[currentTool] = mode
      } label: {
        HStack {
          Text(mode.displayName)
          if currentMode == mode {
            Image(systemName: "checkmark")
          }
        }
      }
    }
  }

  // MARK: - Drag Handle (visual only — drag handled by NSWindow)
  private var dragHandle: some View {
    Image(systemName: "line.3.horizontal")
      .font(.system(size: 10, weight: .bold))
      .foregroundColor(.primary.opacity(0.3))
      .frame(width: 20, height: 20)
  }

  // MARK: - Divider

  @ViewBuilder
  private var divider: some View {
    if direction == .horizontal {
      Rectangle()
        .fill(Color.primary.opacity(0.15))
        .frame(width: 1, height: 20)
        .padding(.horizontal, 2)
    } else {
      Rectangle()
        .fill(Color.primary.opacity(0.15))
        .frame(width: 20, height: 1)
        .padding(.vertical, 2)
    }
  }
}
