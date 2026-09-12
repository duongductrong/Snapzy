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
        Text(L10n.RecordingToolbar.options)
          .font(.system(size: 13, weight: .regular))
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .semibold))
      }
      .foregroundColor(.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .liquidGlassChrome(
        shape: ToolbarConstants.textButtonShape,
        isVisible: isHovered || showPopover,
        isActive: showPopover
      )
      .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
      .animation(LiquidGlassTokens.hoverSpring, value: showPopover)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) { isHovered = hovering }
    }
    .popover(isPresented: $showPopover, arrowEdge: .bottom) {
      ToolbarOptionsPopoverContent(state: state)
    }
    .accessibilityLabel(L10n.RecordingToolbar.recordingOptionsAccessibility)
    .accessibilityHint(L10n.RecordingToolbar.recordingOptionsHint)
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
        Text(L10n.RecordingToolbar.settingsTitle)
          .font(.system(size: 12, weight: .semibold))
        Spacer()
      }

      Divider()

      // Format Section
      SettingsSection(title: L10n.RecordingToolbar.formatSection, icon: "film") {
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
      SettingsSection(title: L10n.RecordingToolbar.qualitySection, icon: "sparkles") {
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

      // Overlays Section
      SettingsSection(title: L10n.RecordingToolbar.overlaysSection, icon: "square.stack.3d.up") {
        RightAlignedToggleRow(
          title: L10n.RecordingToolbar.showCursor,
          isOn: Binding(
            get: { state.showCursor },
            set: { newValue in
              state.showCursor = newValue
              UserDefaults.standard.set(newValue, forKey: PreferencesKeys.recordingShowCursor)
            }
          )
        )

        RightAlignedToggleRow(
          title: L10n.RecordingToolbar.highlightClicks,
          isOn: Binding(
            get: { state.highlightClicks },
            set: { newValue in
              state.highlightClicks = newValue
              UserDefaults.standard.set(newValue, forKey: PreferencesKeys.recordingHighlightClicks)
            }
          )
        )

        RightAlignedToggleRow(
          title: L10n.RecordingToolbar.showKeystrokes,
          isOn: Binding(
            get: { state.showKeystrokes },
            set: { newValue in
              state.showKeystrokes = newValue
              UserDefaults.standard.set(newValue, forKey: PreferencesKeys.recordingShowKeystrokes)
            }
          )
        )

        RightAlignedToggleRow(
          title: L10n.RecordingToolbar.dimNonSelectedArea,
          isOn: Binding(
            get: { state.dimNonSelectedArea },
            set: { newValue in
              state.dimNonSelectedArea = newValue
              UserDefaults.standard.set(newValue, forKey: PreferencesKeys.recordingDimNonSelectedArea)
            }
          )
        )
      }
    }
    .padding(12)
    .frame(width: 280)
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
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct RightAlignedToggleRow: View {
  let title: String
  let isOn: Binding<Bool>

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.system(size: 11))
      Spacer()
      Toggle("", isOn: isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
    .frame(maxWidth: .infinity)
  }
}

// MARK: - Option Pill

private struct OptionPill: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        // The surface carries the accent tint when selected, so the label is resolved against
        // that tint rather than against the app appearance — and never tinted itself, which
        // would put accent-coloured text on accent glass.
        .foregroundColor(isSelected ? LiquidGlassTokens.inkOnAccent : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .liquidGlassControl(
          isActive: isSelected,
          in: Capsule(style: .continuous)
        )
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  ToolbarOptionsMenu(state: RecordingToolbarState())
    .padding()
    .background(.ultraThinMaterial)
    .clipShape(Radius.rect(Radius.card))
}

#Preview("Popover Content") {
  ToolbarOptionsPopoverContent(state: RecordingToolbarState())
    .background(Color(NSColor.windowBackgroundColor))
}
