//
//  VideoExportSettingsPanel.swift
//  ClaudeShot
//
//  Export settings panel for video editor
//

import SwiftUI

/// Export settings panel displayed below timeline
struct VideoExportSettingsPanel: View {
  @ObservedObject var state: VideoEditorState

  var body: some View {
    HStack(alignment: .top, spacing: 24) {
      // Quality section
      qualitySection

      Divider()
        .frame(height: 80)

      // Dimensions section
      dimensionsSection

      Divider()
        .frame(height: 80)

      // Audio section
      audioSection

      Spacer()

      // File size estimate
      fileSizeSection
    }
    .padding(12)
  }

  // MARK: - Quality Section

  private var qualitySection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Quality")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      HStack(spacing: 4) {
        ForEach(ExportQuality.allCases) { quality in
          qualityButton(quality)
        }
      }
    }
  }

  private func qualityButton(_ quality: ExportQuality) -> some View {
    Button {
      var settings = state.exportSettings
      settings.quality = quality
      state.updateExportSettings(settings)
    } label: {
      Text(quality.rawValue)
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
          state.exportSettings.quality == quality
            ? Color.accentColor.opacity(0.3)
            : Color.white.opacity(0.1)
        )
        .cornerRadius(4)
        .overlay(
          RoundedRectangle(cornerRadius: 4)
            .stroke(
              state.exportSettings.quality == quality ? Color.accentColor : Color.clear,
              lineWidth: 1
            )
        )
    }
    .buttonStyle(.plain)
  }

  // MARK: - Dimensions Section

  private var dimensionsSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Dimensions")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      // Preset picker with dimension labels
      Picker("", selection: dimensionPresetBinding) {
        ForEach(ExportDimensionPreset.allCases) { preset in
          Text(preset.displayLabel(for: state.naturalSize))
            .tag(preset)
        }
      }
      .pickerStyle(.menu)
      .frame(minWidth: 160)
      .controlSize(.small)

      // Custom dimension fields or file size reduction hint
      if state.exportSettings.dimensionPreset == .custom {
        customDimensionFields
      } else if state.exportSettings.dimensionPreset != .original {
        // Show file size impact hint
        fileSizeReductionHint
      }
    }
  }

  private var fileSizeReductionHint: some View {
    let size = state.exportSettings.exportSize(from: state.naturalSize)
    let originalPixels = state.naturalSize.width * state.naturalSize.height
    let newPixels = size.width * size.height
    let reduction = originalPixels > 0 ? Int((1.0 - newPixels / originalPixels) * 100) : 0

    return Group {
      if reduction > 0 {
        Text("~\(reduction)% smaller file size")
          .font(.system(size: 9))
          .foregroundColor(.green.opacity(0.8))
      }
    }
  }

  private var customDimensionFields: some View {
    HStack(spacing: 4) {
      TextField("W", value: widthBinding, format: .number)
        .textFieldStyle(.roundedBorder)
        .frame(width: 60)
        .controlSize(.small)

      Button {
        var settings = state.exportSettings
        settings.aspectRatioLocked.toggle()
        state.updateExportSettings(settings)
      } label: {
        Image(systemName: state.exportSettings.aspectRatioLocked ? "lock" : "lock.open")
          .font(.system(size: 9))
          .foregroundColor(state.exportSettings.aspectRatioLocked ? .accentColor : .secondary)
      }
      .buttonStyle(.plain)

      TextField("H", value: heightBinding, format: .number)
        .textFieldStyle(.roundedBorder)
        .frame(width: 60)
        .controlSize(.small)
    }
  }

  // MARK: - Audio Section

  private var audioSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Audio")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)

      // Audio mode picker
      HStack(spacing: 2) {
        ForEach(AudioExportMode.allCases) { mode in
          audioModeButton(mode)
        }
      }

      // Volume slider for custom mode
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
      Image(systemName: mode.icon)
        .font(.system(size: 10))
        .frame(width: 28, height: 24)
        .background(
          state.exportSettings.audioMode == mode
            ? Color.accentColor.opacity(0.3)
            : Color.white.opacity(0.1)
        )
        .cornerRadius(4)
    }
    .buttonStyle(.plain)
    .help(mode.rawValue)
  }

  private var volumeSlider: some View {
    HStack(spacing: 4) {
      Text("0%")
        .font(.system(size: 8))
        .foregroundColor(.secondary)

      Slider(value: volumeBinding, in: 0...2, step: 0.05)
        .frame(width: 80)
        .controlSize(.small)

      Text("\(Int(state.exportSettings.audioVolume * 100))%")
        .font(.system(size: 9))
        .foregroundColor(.secondary)
        .monospacedDigit()
        .frame(width: 32, alignment: .trailing)
    }
  }

  // MARK: - File Size Section

  private var fileSizeSection: some View {
    VStack(alignment: .trailing, spacing: 4) {
      Text("Estimated Size")
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
