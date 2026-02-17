//
//  ToolbarOptionsMenu.swift
//  Snapzy
//
//  Options text button with popover for recording toolbar settings
//  Styled to match Apple's native macOS recording toolbar ("Options▾")
//

import SwiftUI

struct ToolbarOptionsMenu: View {
  @ObservedObject var state: RecordingToolbarState

  @State private var isHovered = false
  @State private var showPopover = false

  var body: some View {
    Button {
      showPopover.toggle()
    } label: {
      HStack(spacing: 2) {
        Text("Options")
          .font(.system(size: 13, weight: .regular))
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .semibold))
      }
      .foregroundColor(.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
          .fill(Color.primary.opacity(isHovered || showPopover ? 0.1 : 0))
      )
      .contentShape(RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius))
      .animation(ToolbarConstants.hoverAnimation, value: isHovered)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .popover(isPresented: $showPopover, arrowEdge: .bottom) {
      ToolbarOptionsPopoverContent(state: state)
    }
    .accessibilityLabel("Recording options")
    .accessibilityHint("Opens settings for format, quality, and audio")
  }
}

// MARK: - Popover Content

private struct ToolbarOptionsPopoverContent: View {
  @ObservedObject var state: RecordingToolbarState

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Header
      HStack {
        Image(systemName: "gearshape")
          .foregroundColor(.secondary)
        Text("Recording Settings")
          .font(.system(size: 12, weight: .semibold))
        Spacer()
      }

      Divider()

      // Format Section
      SettingsSection(title: "Format", icon: "film") {
        HStack(spacing: 6) {
          ForEach(VideoFormat.allCases, id: \.self) { format in
            OptionPill(
              title: format.displayName,
              isSelected: state.selectedFormat == format
            ) {
              state.selectedFormat = format
            }
          }
        }
      }

      // Quality Section
      SettingsSection(title: "Quality", icon: "sparkles") {
        HStack(spacing: 6) {
          ForEach(VideoQuality.allCases, id: \.self) { quality in
            OptionPill(
              title: quality.displayName,
              isSelected: state.selectedQuality == quality
            ) {
              state.selectedQuality = quality
            }
          }
        }
      }

      Divider()

      // Audio Section
      SettingsSection(title: "Audio", icon: "speaker.wave.2") {
        Toggle(isOn: $state.captureAudio) {
          Text("System Audio")
            .font(.system(size: 11))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
      }
    }
    .padding(12)
    .frame(width: 240)
  }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
  let title: String
  let icon: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 10))
          .foregroundColor(.secondary)
        Text(title)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)
      }
      content()
    }
  }
}

// MARK: - Option Pill

private struct OptionPill: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        .foregroundColor(isSelected ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.1 : 0.05))
        )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}

#Preview {
  ToolbarOptionsMenu(state: RecordingToolbarState())
    .padding()
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
}

#Preview("Popover Content") {
  ToolbarOptionsPopoverContent(state: RecordingToolbarState())
    .background(Color(NSColor.windowBackgroundColor))
}
