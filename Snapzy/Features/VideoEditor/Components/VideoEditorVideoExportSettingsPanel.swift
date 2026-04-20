//
//  VideoEditorVideoExportSettingsPanel.swift
//  Snapzy
//
//  Collapsible export settings inspector for video editor
//

import SwiftUI

private enum VideoEditorExportInspectorTab: CaseIterable, Identifiable {
  case quality
  case dimensions
  case audio

  var id: Self { self }

  var title: String {
    switch self {
    case .quality:
      return L10n.Common.quality
    case .dimensions:
      return L10n.Common.dimensions
    case .audio:
      return L10n.Common.audio
    }
  }

  var icon: String {
    switch self {
    case .quality:
      return "sparkles.tv"
    case .dimensions:
      return "aspectratio"
    case .audio:
      return "speaker.wave.2"
    }
  }

  func summary(state: VideoEditorState) -> String {
    switch self {
    case .quality:
      return state.exportSettings.quality.localizedLabel
    case .dimensions:
      let size = state.exportSettings.exportSize(from: state.naturalSize)
      guard size.width > 0, size.height > 0 else { return "—" }
      return "\(Int(size.width)) × \(Int(size.height))"
    case .audio:
      switch state.exportSettings.audioMode {
      case .keep:
        return AudioExportMode.keep.localizedLabel
      case .mute:
        return AudioExportMode.mute.localizedLabel
      case .custom:
        return "\(Int(state.exportSettings.audioVolume * 100))%"
      }
    }
  }
}

/// Export settings panel displayed below timeline
struct VideoExportSettingsPanel: View {
  @ObservedObject var state: VideoEditorState

  @State private var expandedTab: VideoEditorExportInspectorTab?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let expandedTab {
        expandedInspector(for: expandedTab)
      }

      HStack(alignment: .center, spacing: 10) {
        ForEach(VideoEditorExportInspectorTab.allCases) { tab in
          inspectorTabButton(tab)
        }

        Spacer(minLength: 12)

        fileSizeSection
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.white.opacity(0.04))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
    )
    .animation(.spring(response: 0.24, dampingFraction: 0.9), value: expandedTab)
  }

  private func inspectorTabButton(_ tab: VideoEditorExportInspectorTab) -> some View {
    let isExpanded = expandedTab == tab

    return Button {
      withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
        expandedTab = isExpanded ? nil : tab
      }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: tab.icon)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(isExpanded ? .accentColor : .secondary)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 2) {
          Text(tab.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.primary)
            .lineLimit(1)

          Text(tab.summary(state: state))
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .monospacedDigit()
            .lineLimit(1)
        }

        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
          .font(.system(size: 9, weight: .bold))
          .foregroundColor(.secondary.opacity(0.8))
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(isExpanded ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(isExpanded ? Color.accentColor.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private func expandedInspector(for tab: VideoEditorExportInspectorTab) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Label(tab.title, systemImage: tab.icon)
          .font(.system(size: 12, weight: .semibold))

        Spacer()

        Text(tab.summary(state: state))
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)
          .monospacedDigit()
      }

      Group {
        switch tab {
        case .quality:
          qualityInspectorContent
        case .dimensions:
          dimensionsInspectorContent
        case .audio:
          audioInspectorContent
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(0.03))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.white.opacity(0.06), lineWidth: 1)
    )
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  // MARK: - Quality

  private var qualityInspectorContent: some View {
    HStack(spacing: 8) {
      ForEach(ExportQuality.allCases) { quality in
        qualityButton(quality)
      }
    }
  }

  private func qualityButton(_ quality: ExportQuality) -> some View {
    Button {
      var settings = state.exportSettings
      settings.quality = quality
      state.updateExportSettings(settings)
    } label: {
      Text(quality.localizedLabel)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
              state.exportSettings.quality == quality
                ? Color.accentColor.opacity(0.22)
                : Color.white.opacity(0.08)
            )
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
              state.exportSettings.quality == quality ? Color.accentColor.opacity(0.36) : Color.clear,
              lineWidth: 1
            )
        )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Dimensions

  private var dimensionsInspectorContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 10) {
        Picker("", selection: dimensionPresetBinding) {
          ForEach(ExportDimensionPreset.allCases) { preset in
            Text(preset.displayLabel(for: state.naturalSize))
              .tag(preset)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 200)
        .controlSize(.small)

        if state.exportSettings.dimensionPreset == .custom {
          customDimensionFields
        } else {
          resolutionBadge(dimensionDisplayText)
        }
      }

      if state.exportSettings.dimensionPreset != .custom,
         state.exportSettings.dimensionPreset != .original
      {
        fileSizeReductionHint
      }
    }
  }

  private func resolutionBadge(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11, weight: .medium))
      .foregroundColor(.secondary)
      .monospacedDigit()
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        Capsule(style: .continuous)
          .fill(Color.white.opacity(0.06))
      )
  }

  private var fileSizeReductionHint: some View {
    let size = state.exportSettings.exportSize(from: state.naturalSize)
    let originalPixels = state.naturalSize.width * state.naturalSize.height
    let newPixels = size.width * size.height
    let reduction = originalPixels > 0 ? Int((1.0 - newPixels / originalPixels) * 100) : 0

    return Group {
      if reduction > 0 {
        Text(L10n.VideoEditor.smallerFileSizeHint(reduction))
          .font(.system(size: 10))
          .foregroundColor(.green.opacity(0.85))
      }
    }
  }

  private var customDimensionFields: some View {
    HStack(spacing: 6) {
      TextField("", value: widthBinding, format: .number, prompt: Text(verbatim: "W"))
        .textFieldStyle(.roundedBorder)
        .frame(width: 72)
        .controlSize(.small)
        .accessibilityLabel(L10n.Common.width)

      Button {
        var settings = state.exportSettings
        settings.aspectRatioLocked.toggle()
        state.updateExportSettings(settings)
      } label: {
        Image(systemName: state.exportSettings.aspectRatioLocked ? "lock" : "lock.open")
          .font(.system(size: 10))
          .foregroundColor(state.exportSettings.aspectRatioLocked ? .accentColor : .secondary)
          .frame(width: 28, height: 28)
          .background(Color.white.opacity(0.06))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      .buttonStyle(.plain)

      TextField("", value: heightBinding, format: .number, prompt: Text(verbatim: "H"))
        .textFieldStyle(.roundedBorder)
        .frame(width: 72)
        .controlSize(.small)
        .accessibilityLabel(L10n.Common.height)

      resolutionBadge(dimensionDisplayText)
    }
  }

  // MARK: - Audio

  private var audioInspectorContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        ForEach(AudioExportMode.allCases) { mode in
          audioModeButton(mode)
        }
      }

      if state.exportSettings.audioMode == .custom {
        volumeSlider
      }
    }
  }

  private func audioModeButton(_ mode: AudioExportMode) -> some View {
    Button {
      var settings = state.exportSettings
      settings.audioMode = mode
      if mode == .mute {
        settings.audioVolume = 0
      } else if mode == .keep && settings.audioVolume == 0 {
        settings.audioVolume = 1.0
      }
      state.updateExportSettings(settings)
    } label: {
      HStack(spacing: 6) {
        Image(systemName: mode.icon)
          .font(.system(size: 11, weight: .medium))

        Text(mode.localizedLabel)
          .font(.system(size: 11, weight: .medium))
          .lineLimit(1)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            state.exportSettings.audioMode == mode
              ? Color.accentColor.opacity(0.22)
              : Color.white.opacity(0.08)
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(
            state.exportSettings.audioMode == mode ? Color.accentColor.opacity(0.36) : Color.clear,
            lineWidth: 1
          )
      )
    }
    .buttonStyle(.plain)
  }

  private var volumeSlider: some View {
    HStack(spacing: 8) {
      Text("0%")
        .font(.system(size: 9))
        .foregroundColor(.secondary)

      Slider(value: volumeBinding, in: 0...2, step: 0.05)
        .frame(width: 140)
        .controlSize(.small)

      Text("\(Int(state.exportSettings.audioVolume * 100))%")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)
        .monospacedDigit()
        .frame(width: 40, alignment: .trailing)
    }
  }

  // MARK: - File Size

  private var fileSizeSection: some View {
    VStack(alignment: .trailing, spacing: 3) {
      Text(L10n.Common.estimatedSize)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)

      Text(formattedFileSize)
        .font(.system(size: 14, weight: .semibold))
        .monospacedDigit()
    }
  }

  // MARK: - Helpers

  private var formattedFileSize: String {
    if state.estimatedFileSize > 0 {
      return "~" + ByteCountFormatter.string(fromByteCount: state.estimatedFileSize, countStyle: .file)
    }
    return "—"
  }

  private var dimensionDisplayText: String {
    let size = state.exportSettings.exportSize(from: state.naturalSize)
    return "\(Int(size.width)) × \(Int(size.height))"
  }

  // MARK: - Bindings

  private var dimensionPresetBinding: Binding<ExportDimensionPreset> {
    Binding(
      get: { state.exportSettings.dimensionPreset },
      set: { newValue in
        var settings = state.exportSettings
        settings.dimensionPreset = newValue
        if newValue == .custom {
          settings.customWidth = Int(state.naturalSize.width)
          settings.customHeight = Int(state.naturalSize.height)
        }
        state.updateExportSettings(settings)
      }
    )
  }

  private var widthBinding: Binding<Int> {
    Binding(
      get: { state.exportSettings.customWidth },
      set: { newValue in
        var settings = state.exportSettings
        let oldWidth = settings.customWidth
        settings.customWidth = max(100, newValue)
        if settings.aspectRatioLocked && oldWidth > 0 {
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
        settings.customHeight = max(100, newValue)
        if settings.aspectRatioLocked && oldHeight > 0 {
          let ratio = CGFloat(settings.customWidth) / CGFloat(oldHeight)
          settings.customWidth = Int(CGFloat(settings.customHeight) * ratio)
        }
        state.updateExportSettings(settings)
      }
    )
  }

  private var volumeBinding: Binding<Float> {
    Binding(
      get: { state.exportSettings.audioVolume },
      set: { newValue in
        var settings = state.exportSettings
        settings.audioVolume = newValue
        state.updateExportSettings(settings)
      }
    )
  }
}
