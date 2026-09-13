//
//  VideoEditorExportSettingsPills.swift
//  Snapzy
//
//  Export settings for the video editor bottom bar: a pill row (Quality / Dimensions / Audio
//  for video, Dimensions / GIF Info for GIF) that expands a glass drawer above the bar with
//  the full configuration. Replaces the inline settings panels under the timeline.
//

import SwiftUI

// MARK: - Tabs

enum VideoEditorExportSettingsTab: Hashable {
  case quality
  case dimensions
  case audio
  case gifInfo

  var title: String {
    switch self {
    case .quality: L10n.Common.quality
    case .dimensions: L10n.Common.dimensions
    case .audio: L10n.Common.audio
    case .gifInfo: L10n.VideoEditor.gifInfo
    }
  }

  var icon: String {
    switch self {
    case .quality: "sparkles.tv"
    case .dimensions: "aspectratio"
    case .audio: "speaker.wave.2"
    case .gifInfo: "info.circle"
    }
  }

  func summary(state: VideoEditorState) -> String {
    switch self {
    case .quality:
      state.exportSettings.quality.localizedLabel
    case .dimensions:
      dimensionsSummary(state: state)
    case .audio:
      audioSummary(state: state)
    case .gifInfo:
      gifInfoSummary(state: state)
    }
  }

  /// Whether the drawer header shows the value summary next to the title. The dimensions
  /// tab hides it — its resolved size already reads out in the Size row below, and showing
  /// `1920 × 1080 (16:9)` in both places just repeats the numbers.
  var showsHeaderSummary: Bool {
    switch self {
    case .dimensions: false
    case .quality, .audio, .gifInfo: true
    }
  }

  /// Whether this tab's drawer header shows the size readout next to the close control.
  /// Audio and GIF Info have no size summary.
  var showsSizeSummary: Bool {
    switch self {
    case .quality, .dimensions: true
    case .audio, .gifInfo: false
    }
  }

  /// Sections shown in the drawer for this tab.
  @ViewBuilder
  func content(state: VideoEditorState) -> some View {
    switch self {
    case .quality:
      QualitySection(state: state)
    case .dimensions:
      DimensionsEditor(state: state)
    case .audio:
      AudioEditor(state: state)
    case .gifInfo:
      GIFInfoSection(state: state)
    }
  }
}

func dimensionsSummary(state: VideoEditorState) -> String {
  let size = state.exportSettings.exportSize(from: state.naturalSize)
  guard size.width > 0, size.height > 0 else { return "—" }

  if let aspectRatio = state.exportSettings.aspectRatioString(from: state.naturalSize) {
    return "\(Int(size.width)) × \(Int(size.height)) (\(aspectRatio))"
  }

  return "\(Int(size.width)) × \(Int(size.height))"
}

func audioSummary(state: VideoEditorState) -> String {
  switch state.exportSettings.audioMode {
  case .keep:
    return AudioExportMode.keep.localizedLabel
  case .mute:
    return AudioExportMode.mute.localizedLabel
  case .custom:
    let roles = state.audioTrackRoles.isEmpty ? [.mixed] : state.audioTrackRoles
    guard roles.count > 1 else {
      return "\(Int(state.exportSettings.audioVolume(for: roles[0]) * 100))%"
    }

    return roles
      .prefix(2)
      .map { role in
        "\(role.compactLabel) \(Int(state.exportSettings.audioVolume(for: role) * 100))%"
      }
      .joined(separator: " · ")
  }
}

func gifInfoSummary(state: VideoEditorState) -> String {
  var parts: [String] = []

  if state.gifFrameCount > 0 {
    parts.append(L10n.VideoEditor.framesCount(state.gifFrameCount))
  }

  if state.gifDuration > 0 {
    parts.append(String(format: "%.1fs", state.gifDuration))
  }

  if parts.isEmpty, state.naturalSize.width > 0, state.naturalSize.height > 0 {
    parts.append("\(Int(state.naturalSize.width)) × \(Int(state.naturalSize.height))")
  }

  return parts.isEmpty ? "—" : parts.joined(separator: " • ")
}

/// The tabs each editor mode exposes.
func videoEditorSettingsTabs(isGIF: Bool) -> [VideoEditorExportSettingsTab] {
  isGIF
    ? [.dimensions, .gifInfo]
    : [.quality, .dimensions, .audio]
}

// MARK: - Pill Row

/// Bottom-bar pill row. One glass pill per settings tab; the expanded pill stays lit.
struct VideoEditorExportSettingsBar: View {
  @ObservedObject var state: VideoEditorState
  @Binding var expandedTab: VideoEditorExportSettingsTab?

  var body: some View {
    HStack(spacing: 8) {
      ForEach(videoEditorSettingsTabs(isGIF: state.isGIF), id: \.self) { tab in
        VideoEditorSettingsPillButton(
          icon: tab.icon,
          title: tab.title,
          isActive: expandedTab == tab
        ) {
          withAnimation(LiquidGlassTokens.settleSpring) {
            expandedTab = expandedTab == tab ? nil : tab
          }
        }
      }
    }
  }
}

// MARK: - Drawer

/// The glass drawer that expands above the bottom bar when a settings pill is tapped.
/// The surface stays inside the bar's glass group so it merges with the pill row.
struct VideoEditorExportSettingsDrawer: View {
  @ObservedObject var state: VideoEditorState
  let tab: VideoEditorExportSettingsTab
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header

      Divider()

      tab.content(state: state)
    }
    .padding(14)
    .liquidGlassChrome(
      shape: Radius.rect(Radius.card),
      isVisible: true
    )
    .transition(
      .opacity
        .combined(with: .move(edge: .bottom))
    )
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: tab.icon)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.accentColor)

      Text(tab.title)
        .font(.system(size: 12, weight: .semibold))

      if tab.showsHeaderSummary {
        Text(tab.summary(state: state))
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .monospacedDigit()
          .lineLimit(1)
      }

      Spacer(minLength: 12)

      // Estimated size sits next to the close control — the readout the inline quality
      // row and the old dimensions footer used to show, now in one place.
      if tab.showsSizeSummary {
        HStack(spacing: 10) {
          if state.isGIF {
            sizeValue(label: L10n.Common.currentSize, value: state.fileSizeString, color: .primary)
          }
          if !state.isGIF || showsEstimatedSize {
            sizeValue(
              label: L10n.Common.estimatedSize,
              value: estimatedFileSizeText(state: state),
              color: state.isGIF ? .green : .primary
            )
          }
        }
      }

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 9, weight: .bold))
          .foregroundColor(.secondary)
          .frame(width: 20, height: 20)
          .liquidGlassControl(isActive: false, in: Circle())
      }
      .buttonStyle(.plain)
      .help(L10n.Common.close)
    }
  }

  private var showsEstimatedSize: Bool {
    state.exportSettings.dimensionPreset != .original && state.estimatedFileSize > 0
  }
}

/// Format helper shared by the header size readout.
private func estimatedFileSizeText(state: VideoEditorState) -> String {
  guard state.estimatedFileSize > 0 else { return "—" }
  return "~" + ByteCountFormatter.string(fromByteCount: state.estimatedFileSize, countStyle: .file)
}

private func sizeValue(label: String, value: String, color: Color) -> some View {
  HStack(spacing: 6) {
    Text(label)
      .font(.system(size: 10, weight: .medium))
      .foregroundColor(.secondary)

    Text(value)
      .font(.system(size: 11, weight: .semibold))
      .monospacedDigit()
      .foregroundColor(color)
  }
}

// MARK: - Shared Section Chrome

/// Labelled section header used inside the settings drawer.
private struct ExportSettingsSection<Content: View>: View {
  let title: String
  let icon: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 10, weight: .medium))
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

// MARK: - Option Pill

/// Selection pill inside the settings drawer. Accent-tinted glass when selected — the same
/// treatment as the recording toolbar's option pills.
private struct ExportOptionPill: View {
  let title: String
  let icon: String?
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        if let icon {
          Image(systemName: icon)
            .font(.system(size: 10, weight: .medium))
        }

        Text(title)
          .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
          .lineLimit(1)
      }
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

// MARK: - Quality Section

private struct QualitySection: View {
  @ObservedObject var state: VideoEditorState

  var body: some View {
    HStack(spacing: 6) {
      ForEach(ExportQuality.allCases) { quality in
        ExportOptionPill(
          title: quality.localizedLabel,
          icon: nil,
          isSelected: state.exportSettings.quality == quality
        ) {
          var settings = state.exportSettings
          settings.quality = quality
          state.updateExportSettings(settings)
        }
      }
    }
  }
}

// MARK: - GIF Info Section

private struct GIFInfoSection: View {
  @ObservedObject var state: VideoEditorState

  var body: some View {
    HStack(spacing: 8) {
      if state.naturalSize.width > 0 {
        metadataBadge(
          systemName: "photo",
          text: "\(Int(state.naturalSize.width)) × \(Int(state.naturalSize.height))"
        )
      }

      if state.gifFrameCount > 0 {
        metadataBadge(
          systemName: "square.stack.3d.down.right",
          text: L10n.VideoEditor.framesCount(state.gifFrameCount)
        )
      }

      if state.gifDuration > 0 {
        metadataBadge(
          systemName: "clock",
          text: String(format: "%.1fs", state.gifDuration)
        )
      }
    }
  }

  private func metadataBadge(systemName: String, text: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: systemName)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)

      Text(text)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.primary)
        .lineLimit(1)
        .monospacedDigit()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .liquidGlassControl(
      isActive: false,
      in: Capsule(style: .continuous),
      showsRestingSurface: true
    )
  }
}

// MARK: - Dimensions Editor

/// Scale presets for the dropdown: Original + percent presets + Custom. The aspect-ratio
/// presets are excluded — the Aspect row owns shape, so no preset appears in both places.
private extension ExportDimensionPreset {
  static var scalePresets: [ExportDimensionPreset] {
    allCases.filter { $0.isAspectRatioPreset == false }
  }

  /// Compact preset name for the dropdown pill: `Original` / `16:9` / `90%` / `Custom`, with
  /// no resolved dimensions — those belong to the menu rows and the trailing output readout.
  var shortLabel: String {
    switch self {
    case .original: L10n.Common.original
    case .custom: L10n.Common.custom
    default: rawValue
    }
  }
}

/// Dimensions editor, shared by the video and GIF drawers. A two-row form grid with a
/// single job per row: `Scale` — how much the source is scaled (Original, percents, Custom
/// with W/H fields) via a glass dropdown, plus the resolved output size and its reduction
/// as plain trailing text; `Aspect` — the shape, as aspect-ratio pills. When an aspect
/// preset is active, the Scale pill shows the ratio name so the active state stays visible.
private struct DimensionsEditor: View {
  @ObservedObject var state: VideoEditorState

  @State private var isPresetMenuPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      sizeRow
      aspectRow
    }
  }

  // MARK: Size Row

  private var sizeRow: some View {
    HStack(alignment: .center, spacing: 8) {
      rowLabel(L10n.Common.scale)

      presetDropdown

      Spacer(minLength: 8)

      if state.exportSettings.dimensionPreset == .custom {
        customDimensionFields
      } else {
        resolvedSizeText
      }
    }
  }

  private func rowLabel(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 11))
      .foregroundColor(.secondary)
      .lineLimit(1)
      .frame(minWidth: 52, alignment: .leading)
  }

  /// Glass pill select for the scale preset. The pill carries only the preset name — the
  /// resolved dimensions appear per row in the menu and as the trailing output readout,
  /// so the same W × H numbers never repeat inside the pill. An active aspect preset is
  /// named in the pill (it is not a menu choice), keeping the state visible.
  private var presetDropdown: some View {
    Button {
      isPresetMenuPresented.toggle()
    } label: {
      HStack(spacing: 6) {
        Text(state.exportSettings.dimensionPreset.shortLabel)
          .font(.system(size: 11, weight: .medium))
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)

        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .bold))
          .foregroundColor(.secondary)
          .rotationEffect(.degrees(isPresetMenuPresented ? 180 : 0))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .liquidGlassControl(
        isActive: isPresetMenuPresented,
        in: Capsule(style: .continuous),
        showsRestingSurface: true
      )
      .animation(LiquidGlassTokens.hoverSpring, value: isPresetMenuPresented)
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresetMenuPresented, arrowEdge: .bottom) {
      presetMenu
    }
    .help(L10n.Common.scale)
  }

  private var presetMenu: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(ExportDimensionPreset.scalePresets, id: \.self) { preset in
        presetMenuRow(preset)
      }
    }
    .padding(6)
    .frame(width: 240, alignment: .leading)
  }

  private func presetMenuRow(_ preset: ExportDimensionPreset) -> some View {
    let isSelected = state.exportSettings.dimensionPreset == preset

    return Button {
      applyPreset(preset)
      isPresetMenuPresented = false
    } label: {
      HStack(spacing: 8) {
        Text(preset.displayLabel(for: state.naturalSize))
          .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
          .foregroundColor(isSelected ? LiquidGlassTokens.inkOnAccent : .primary)
          .lineLimit(1)

        Spacer(minLength: 8)

        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(LiquidGlassTokens.inkOnAccent)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .liquidGlassControl(
        isActive: isSelected,
        in: Capsule(style: .continuous)
      )
      .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func applyPreset(_ preset: ExportDimensionPreset) {
    var settings = state.exportSettings
    settings.dimensionPreset = preset
    if preset == .custom {
      settings.customWidth = Int(state.naturalSize.width)
      settings.customHeight = Int(state.naturalSize.height)
    }
    state.updateExportSettings(settings)
  }

  /// Resolved output size as plain text — the reduction percent joins when scaled down.
  private var resolvedSizeText: some View {
    let size = state.exportSettings.exportSize(from: state.naturalSize)
    let originalPixels = state.naturalSize.width * state.naturalSize.height
    let newPixels = size.width * size.height
    let reduction = originalPixels > 0 ? Int((1.0 - newPixels / originalPixels) * 100) : 0

    return HStack(spacing: 6) {
      Text("\(Int(size.width)) × \(Int(size.height))")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.primary)

      if reduction > 0 {
        Text("−\(reduction)%")
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(.green.opacity(0.9))
      }
    }
    .monospacedDigit()
  }

  // MARK: Aspect Row

  private var aspectRow: some View {
    HStack(spacing: 8) {
      rowLabel(L10n.Common.aspectRatio)

      HStack(spacing: 6) {
        ForEach(ExportDimensionPreset.aspectRatioPresets) { preset in
          ExportOptionPill(
            title: preset.rawValue,
            icon: nil,
            isSelected: state.exportSettings.dimensionPreset == preset
          ) {
            applyPreset(preset)
          }
        }
      }
    }
  }

  // MARK: Custom Fields

  private var customDimensionFields: some View {
    HStack(spacing: 6) {
      TextField("", value: widthBinding, format: plainIntegerFormat, prompt: Text(verbatim: "W"))
        .textFieldStyle(.roundedBorder)
        .frame(width: 64)
        .controlSize(.small)
        .accessibilityLabel(L10n.Common.width)

      Button {
        var settings = state.exportSettings
        settings.aspectRatioLocked.toggle()
        state.updateExportSettings(settings)
      } label: {
        Image(systemName: state.exportSettings.aspectRatioLocked ? "lock" : "lock.open")
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(state.exportSettings.aspectRatioLocked ? .accentColor : .secondary)
          .frame(width: 24, height: 24)
          .liquidGlassControl(
            isActive: state.exportSettings.aspectRatioLocked,
            in: Radius.controlRect(forHeight: 24)
          )
      }
      .buttonStyle(.plain)

      TextField("", value: heightBinding, format: plainIntegerFormat, prompt: Text(verbatim: "H"))
        .textFieldStyle(.roundedBorder)
        .frame(width: 64)
        .controlSize(.small)
        .accessibilityLabel(L10n.Common.height)
    }
  }

  /// Plain integer entry — no locale grouping separators, so 3600 never renders as "3.600".
  private var plainIntegerFormat: IntegerFormatStyle<Int> {
    IntegerFormatStyle<Int>().grouping(.never)
  }

  private var widthBinding: Binding<Int> {
    Binding(
      get: { state.exportSettings.customWidth },
      set: { newValue in
        var settings = state.exportSettings
        let oldWidth = settings.customWidth
        settings.customWidth = max(16, newValue)
        if settings.aspectRatioLocked, oldWidth > 0 {
          let ratio = CGFloat(settings.customHeight) / CGFloat(oldWidth)
          settings.customHeight = Int(CGFloat(settings.customWidth) * ratio)
        }
        state.updateExportSettings(settings)
      }
    )
  }

  private var heightBinding: Binding<Int> {
    Binding(
      get: { state.exportSettings.customHeight },
      set: { newValue in
        var settings = state.exportSettings
        let oldHeight = settings.customHeight
        settings.customHeight = max(16, newValue)
        if settings.aspectRatioLocked, oldHeight > 0 {
          let ratio = CGFloat(settings.customWidth) / CGFloat(oldHeight)
          settings.customWidth = Int(CGFloat(settings.customHeight) * ratio)
        }
        state.updateExportSettings(settings)
      }
    )
  }
}

// MARK: - Audio Editor

/// Audio mode pills + per-role volume sliders, shown in the video audio drawer section.
private struct AudioEditor: View {
  @ObservedObject var state: VideoEditorState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        ForEach(AudioExportMode.allCases) { mode in
          ExportOptionPill(
            title: mode.localizedLabel,
            icon: mode.icon,
            isSelected: state.exportSettings.audioMode == mode
          ) {
            var settings = state.exportSettings
            settings.audioMode = mode
            if mode == .mute {
              settings.muteAllAudioVolumes()
            } else if mode == .keep {
              settings.resetMutedAudioVolumesToDefault()
            }
            state.updateExportSettings(settings)
          }
        }
      }

      if state.exportSettings.audioMode == .custom {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(customAudioVolumeRoles) { role in
            volumeSlider(for: role)
          }
        }
      }
    }
  }

  private var customAudioVolumeRoles: [VideoEditorAudioTrackRole] {
    state.audioTrackRoles.isEmpty ? [.mixed] : state.audioTrackRoles
  }

  private func volumeSlider(for role: VideoEditorAudioTrackRole) -> some View {
    HStack(spacing: 8) {
      Label(role.localizedLabel, systemImage: role.icon)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .frame(width: 120, alignment: .leading)

      Slider(value: volumeBinding(for: role).stepped(by: 0.05, in: 0 ... 2), in: 0 ... 2)
        .controlSize(.small)

      Text("\(Int(state.exportSettings.audioVolume(for: role) * 100))%")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.primary)
        .monospacedDigit()
        .frame(width: 40, alignment: .trailing)
    }
  }

  private func volumeBinding(for role: VideoEditorAudioTrackRole) -> Binding<Float> {
    Binding(
      get: { state.exportSettings.audioVolume(for: role) },
      set: { newValue in
        var settings = state.exportSettings
        settings.setAudioVolume(newValue, for: role)
        state.updateExportSettings(settings)
      }
    )
  }
}

// MARK: - Previews

#Preview("Video Settings Bar + Drawer") {
  VideoEditorExportSettingsDemo(isGIF: false)
}

#Preview("GIF Settings Bar + Drawer") {
  VideoEditorExportSettingsDemo(isGIF: true)
}

private struct VideoEditorExportSettingsDemo: View {
  let isGIF: Bool
  @State private var expandedTab: VideoEditorExportSettingsTab?

  var body: some View {
    VStack(spacing: 10) {
      if let openTab = expandedTab {
        VideoEditorExportSettingsDrawer(
          state: state,
          tab: openTab,
          onClose: { withAnimation(LiquidGlassTokens.settleSpring) { expandedTab = nil } }
        )
        .padding(.horizontal, 12)
      }

      VideoEditorExportSettingsBar(state: state, expandedTab: $expandedTab)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
    .padding(.top, 20)
    .background(.ultraThinMaterial)
    .clipShape(Radius.rect(Radius.card))
  }

  private var state: VideoEditorState {
    VideoEditorState(url: URL(fileURLWithPath: isGIF ? "/tmp/test.gif" : "/tmp/test.mp4"))
  }
}
