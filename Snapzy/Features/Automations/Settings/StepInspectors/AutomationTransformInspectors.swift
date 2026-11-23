//
//  AutomationTransformInspectors.swift
//  Snapzy
//
//  Settings for transform steps: canvas preset, resize, convert, OCR,
//  translate, GIF.
//

import SwiftUI

struct CanvasPresetInspector: View {
  @Binding var config: AutomationCanvasPresetConfig
  private let presets = AnnotateCanvasPresetStore.shared.loadPresets()

  var body: some View {
    Section {
      Picker(L10n.Automations.canvasPresetLabel, selection: $config.presetID) {
        Text(L10n.Automations.canvasPresetDefault).tag(UUID?.none)
        if !presets.isEmpty { Divider() }
        ForEach(presets) { preset in
          Text(preset.name).tag(Optional(preset.id))
        }
      }
    }
  }
}

struct ResizeInspector: View {
  @Binding var config: AutomationResizeConfig

  var body: some View {
    Section {
      Picker(L10n.Automations.resizeModeLabel, selection: $config.mode) {
        Text(L10n.Automations.resizeModeMax).tag(AutomationResizeConfig.Mode.maxDimension)
        Text(L10n.Automations.resizeModePercent).tag(AutomationResizeConfig.Mode.scalePercent)
      }
      .pickerStyle(.segmented)

      switch config.mode {
      case .maxDimension:
        TextField(L10n.Automations.resizeMaxLabel, value: $config.maxDimension, format: .number)
          .help(L10n.Automations.resizeNoUpscale)
      case .scalePercent:
        Stepper(value: $config.scalePercent, in: AutomationResizeConfig.percentRange, step: 5) {
          Text("\(L10n.Automations.resizePercentLabel): \(config.clampedScalePercent)%")
        }
      }
    } footer: {
      Text(L10n.Automations.resizeNoUpscale).font(.caption).foregroundStyle(.secondary)
    }
  }
}

struct ConvertInspector: View {
  @Binding var config: AutomationConvertConfig
  @ObservedObject private var presetStore = QuickAccessOptimizePresetStore.shared

  var body: some View {
    Section {
      Picker(L10n.Automations.convertPresetLabel, selection: $config.optimizePresetID) {
        Text(L10n.Automations.convertCustom).tag(UUID?.none)
        if !presetStore.presets.isEmpty { Divider() }
        ForEach(presetStore.presets) { preset in
          Text(preset.name).tag(Optional(preset.id))
        }
      }

      if config.optimizePresetID == nil {
        Picker(L10n.Automations.convertFormatLabel, selection: $config.format) {
          ForEach(QuickAccessOptimizeFormat.allCases) { format in
            Text(format.displayName(originalExtension: nil))
              .tag(format)
          }
        }
        if !config.format.isEncoderAvailable {
          Label(L10n.Automations.warningPNGFallback, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        if config.format.isLossy || config.format == .original {
          Slider(
            value: Binding(get: { Double(config.quality) }, set: { config.quality = Int($0) }),
            in: Double(QuickAccessOptimizeSettings.qualityRange.lowerBound)...Double(QuickAccessOptimizeSettings.qualityRange.upperBound),
            step: 5
          ) {
            Text("\(L10n.Automations.convertQualityLabel): \(config.quality)")
          }
        }
        Picker(L10n.Automations.convertMaxSizeLabel, selection: $config.maxFileSizeKB) {
          Text(L10n.Automations.convertNoLimit).tag(Int?.none)
          ForEach(QuickAccessOptimizeSettings.maxFileSizeOptions, id: \.self) { bytes in
            Text(QuickAccessImageOptimizer.formatByteCount(bytes)).tag(Optional(bytes / 1000))
          }
        }
      }
    }
  }
}

struct OCRInspector: View {
  @Binding var config: AutomationOCRConfig

  var body: some View {
    Section {
      Toggle(L10n.Automations.ocrIncludeQR, isOn: $config.includeQR)
    }
  }
}

struct TranslateInspector: View {
  @Binding var config: AutomationTranslateConfig

  var body: some View {
    Section {
      Picker(L10n.Automations.translateTargetLabel, selection: $config.targetLanguage) {
        Text(L10n.Automations.translateDefaultTarget).tag(String?.none)
        Divider()
        ForEach(TranslationLanguage.all) { language in
          Text(language.displayName).tag(Optional(language.identifier))
        }
      }
    } footer: {
      Text(L10n.Automations.translateEngineNote)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct GIFInspector: View {
  @Binding var config: AutomationGIFConfig

  var body: some View {
    Section {
      Picker(L10n.Automations.gifFPSLabel, selection: $config.fps) {
        ForEach(AutomationGIFConfig.fpsOptions, id: \.self) { fps in
          Text("\(fps) fps").tag(fps)
        }
      }
      Picker(L10n.Automations.gifWidthLabel, selection: $config.maxWidth) {
        ForEach(AutomationGIFConfig.widthOptions, id: \.self) { width in
          Text("\(width) px").tag(width)
        }
      }
    }
  }
}
