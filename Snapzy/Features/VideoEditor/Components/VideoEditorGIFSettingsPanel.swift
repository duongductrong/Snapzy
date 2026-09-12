//
//  VideoEditorGIFSettingsPanel.swift
//  Snapzy
//
//  Export settings panel for GIF files in video editor
//  Keeps the dimensions workflow visually aligned with the video export inspector
//

import SwiftUI

private enum VideoEditorGIFInspectorTab: CaseIterable, Identifiable {
  case dimensions
  case info

  var id: Self { self }

  var title: String {
    switch self {
    case .dimensions:
      return L10n.Common.dimensions
    case .info:
      return L10n.VideoEditor.gifInfo
    }
  }

  var icon: String {
    switch self {
    case .dimensions:
      return "aspectratio"
    case .info:
      return "info.circle"
    }
  }

  func summary(state: VideoEditorState) -> String {
    switch self {
    case .dimensions:
      let size = state.exportSettings.exportSize(from: state.naturalSize)
      guard size.width > 0, size.height > 0 else { return "—" }

      if let aspectRatio = state.exportSettings.aspectRatioString(from: state.naturalSize) {
        return "\(Int(size.width)) × \(Int(size.height)) (\(aspectRatio))"
      }

      return "\(Int(size.width)) × \(Int(size.height))"
    case .info:
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
  }
}

/// Export settings panel for GIF mode
struct VideoEditorGIFSettingsPanel: View {
  @ObservedObject var state: VideoEditorState

  @State private var expandedTab: VideoEditorGIFInspectorTab?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let expandedTab {
        expandedInspector(for: expandedTab)
      }

      HStack(alignment: .center, spacing: 8) {
        ForEach(VideoEditorGIFInspectorTab.allCases) { tab in
          inspectorTabButton(tab)
        }

        Spacer(minLength: 10)

        fileSizeSection
      }
    }
    .padding(10)
    .background(
      Radius.rect(Radius.card)
        .fill(Color.white.opacity(0.04))
    )
    .overlay(
      Radius.rect(Radius.card)
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
    )
    .animation(.spring(response: 0.24, dampingFraction: 0.9), value: expandedTab)
  }

  private func inspectorTabButton(_ tab: VideoEditorGIFInspectorTab) -> some View {
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
      .padding(.vertical, 8)
      .background(
        Capsule(style: .continuous)
          .fill(isExpanded ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.05))
      )
      .overlay(
        Capsule(style: .continuous)
          .stroke(isExpanded ? Color.accentColor.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func expandedInspector(for tab: VideoEditorGIFInspectorTab) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Label(tab.title, systemImage: tab.icon)
          .font(.system(size: 12, weight: .semibold))

        Spacer()

        Text(tab.summary(state: state))
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)
          .monospacedDigit()
      }

      switch tab {
      case .dimensions:
        dimensionsInspectorContent
      case .info:
        gifInfoSection
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Radius.rect(Radius.tile)
        .fill(Color.white.opacity(0.03))
    )
    .overlay(
      Radius.rect(Radius.tile)
        .stroke(Color.white.opacity(0.06), lineWidth: 1)
    )
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  private var dimensionsInspectorContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        Picker("", selection: dimensionPresetBinding) {
          ForEach(ExportDimensionPreset.allCases) { preset in
            Text(preset.displayLabel(for: state.naturalSize))
              .tag(preset)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 220)
        .controlSize(.small)

        if state.exportSettings.dimensionPreset == .custom {
          customDimensionFields
        } else {
          resolutionBadge(dimensionDisplayText)
        }
      }

      aspectRatioPresetRow

      if state.exportSettings.dimensionPreset != .custom,
         state.exportSettings.dimensionPreset != .original
      {
        fileSizeReductionHint
      }
    }
  }

  private var aspectRatioPresetRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: "aspectratio")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.accentColor)
            .frame(width: 20, height: 20)
            .background(
              Radius.rect(Radius.tile)
                .fill(Color.accentColor.opacity(0.14))
            )

          Text(L10n.Common.aspectRatio)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
        }

        Spacer(minLength: 8)

        if let exportAspectRatioText {
          Text(exportAspectRatioText)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
              Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
            )
        }
      }

      HStack(spacing: 6) {
        ForEach(ExportDimensionPreset.aspectRatioPresets) { preset in
          aspectRatioPresetButton(preset)
        }
      }
    }
  }

  private func aspectRatioPresetButton(_ preset: ExportDimensionPreset) -> some View {
    let isSelected = state.exportSettings.dimensionPreset == preset

    return Button {
      var settings = state.exportSettings
      settings.dimensionPreset = preset
      state.updateExportSettings(settings)
    } label: {
      Text(preset.rawValue)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(isSelected ? .accentColor : .primary)
        .frame(minWidth: 44)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
          Capsule(style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.06))
        )
        .overlay(
          Capsule(style: .continuous)
            .stroke(isSelected ? Color.accentColor.opacity(0.32) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
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

  private var gifInfoSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        if state.naturalSize.width > 0 {
          metadataBadge(systemName: "photo", text: "\(Int(state.naturalSize.width)) × \(Int(state.naturalSize.height))")
        }

        if state.gifFrameCount > 0 {
          metadataBadge(systemName: "square.stack.3d.down.right", text: L10n.VideoEditor.framesCount(state.gifFrameCount))
        }

        if state.gifDuration > 0 {
          metadataBadge(systemName: "clock", text: String(format: "%.1fs", state.gifDuration))
        }
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
    .background(
      Capsule(style: .continuous)
        .fill(Color.white.opacity(0.05))
    )
    .overlay(
      Capsule(style: .continuous)
        .stroke(Color.white.opacity(0.08), lineWidth: 1)
    )
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
          .clipShape(Radius.controlRect(forHeight: 28))
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

  private var fileSizeSection: some View {
    VStack(alignment: .trailing, spacing: 3) {
      Text(L10n.Common.currentSize)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.secondary)

      Text(state.fileSizeString)
        .font(.system(size: 14, weight: .semibold))
        .monospacedDigit()

      if state.exportSettings.dimensionPreset != .original,
         state.estimatedFileSize > 0 {
        Text(L10n.Common.estimatedSize)
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(.secondary)
          .padding(.top, 4)

        Text("~" + ByteCountFormatter.string(fromByteCount: state.estimatedFileSize, countStyle: .file))
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.green)
          .monospacedDigit()
      }
    }
  }

  private var dimensionSummaryText: String {
    let size = state.exportSettings.exportSize(from: state.naturalSize)
    guard size.width > 0, size.height > 0 else { return "—" }

    if let aspectRatio = state.exportSettings.aspectRatioString(from: state.naturalSize) {
      return "\(Int(size.width)) × \(Int(size.height)) (\(aspectRatio))"
    }

    return "\(Int(size.width)) × \(Int(size.height))"
  }

  private var dimensionDisplayText: String {
    dimensionSummaryText
  }

  private var exportAspectRatioText: String? {
    state.exportSettings.aspectRatioString(from: state.naturalSize)
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
        settings.customWidth = max(16, newValue)
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
        settings.customHeight = max(16, newValue)
        if settings.aspectRatioLocked && oldHeight > 0 {
          let ratio = CGFloat(settings.customWidth) / CGFloat(oldHeight)
          settings.customWidth = Int(CGFloat(settings.customHeight) * ratio)
        }
        state.updateExportSettings(settings)
      }
    )
  }
}
