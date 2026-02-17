//
//  ToolbarOutputModeToggle.swift
//  Snapzy
//
//  Small chevron-down dropdown button for switching recording output
//  Designed as part of a button group with the Record button
//

import SwiftUI

/// Small dropdown arrow button that opens output mode selection (Video / GIF)
struct ToolbarOutputModeDropdown: View {
  @ObservedObject var state: RecordingToolbarState

  @State private var isHovered = false
  @State private var showPopover = false

  var body: some View {
    Button {
      showPopover.toggle()
    } label: {
      Image(systemName: "chevron.down")
        .font(.system(size: 9, weight: .bold))
        .foregroundColor(.primary.opacity(0.7))
        .frame(width: 20, height: 30)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(ToolbarConstants.hoverAnimation) {
        isHovered = hovering
      }
    }
    .background(
      RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
        .fill(Color.primary.opacity(isHovered || showPopover ? 0.1 : 0))
    )
    .popover(isPresented: $showPopover, arrowEdge: .bottom) {
      OutputModePopoverContent(state: state)
    }
    .accessibilityLabel("Output mode: \(state.outputMode.displayName)")
    .accessibilityHint("Opens output format selection")
  }
}

/// Record button with inline badge showing current output mode (Video/GIF)
struct RecordButtonWithBadge: View {
  @ObservedObject var state: RecordingToolbarState
  let onRecord: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: onRecord) {
      HStack(spacing: 6) {
        Text("Record")
          .font(.system(size: 13, weight: .regular))

        // Output mode badge
        Text(state.outputMode.displayName)
          .font(.system(size: 8, weight: .semibold))
          .foregroundColor(badgeTextColor)
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(badgeBackgroundColor)
          )
      }
      .foregroundColor(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .contentShape(RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(ToolbarConstants.hoverAnimation) {
        isHovered = hovering
      }
    }
    .background(
      RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
    )
    .accessibilityLabel("Start recording as \(state.outputMode.displayName)")
    .accessibilityHint("Begins screen recording with current settings")
  }

  private var badgeTextColor: Color {
    state.outputMode == .gif ? .white : .white
  }

  private var badgeBackgroundColor: Color {
    state.outputMode == .gif ? .orange : .accentColor
  }
}

// MARK: - Popover Content

private struct OutputModePopoverContent: View {
  @ObservedObject var state: RecordingToolbarState

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(RecordingOutputMode.allCases, id: \.self) { mode in
        OutputModeRow(
          mode: mode,
          isSelected: state.outputMode == mode
        ) {
          state.outputMode = mode
          // Persist selection
          UserDefaults.standard.set(mode.rawValue, forKey: PreferencesKeys.recordingOutputMode)
        }
      }
    }
    .padding(8)
    .frame(width: 160)
  }
}

// MARK: - Output Mode Row

private struct OutputModeRow: View {
  let mode: RecordingOutputMode
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: mode.iconName)
          .font(.system(size: 12))
          .foregroundColor(isSelected ? .accentColor : .secondary)
          .frame(width: 16)

        Text(mode.displayName)
          .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
          .foregroundColor(.primary)

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.accentColor)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
      )
      .contentShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}

#Preview {
  HStack(spacing: 1) {
    RecordButtonWithBadge(state: RecordingToolbarState(), onRecord: {})
    ToolbarOutputModeDropdown(state: RecordingToolbarState())
  }
  .padding(10)
  .background(.ultraThinMaterial)
  .clipShape(RoundedRectangle(cornerRadius: 14))
}
