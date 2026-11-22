//
//  QuickAccessOptimizeCustomView.swift
//  Snapzy
//
//  The "Custom…" Optimize editor: size, format, quality and a file-size cap with a
//  live size preview, plus saving the settings as a preset. The settings rows are
//  shared with the presets editor in Preferences.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Shared settings rows

/// Size, format, quality and file-size cap. Pass `source` to show pixel sizes and
/// to name the "Original" format after the file's own.
struct QuickAccessOptimizeSettingsForm: View {
  @Binding var settings: QuickAccessOptimizeSettings
  var source: QuickAccessOptimizeSourceInfo?
  var originalExtension: String?
  var labelWidth: CGFloat = 70

  private var outputIsLossy: Bool {
    switch settings.format {
    case .original: originalExtension.map(QuickAccessOptimizeFormat.isLossy(fileExtension:)) ?? true
    default: settings.format.isLossy
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      row(L10n.QuickAccess.optimizeSizeLabel) {
        HStack(spacing: 8) {
          Slider(
            value: intBinding(\.scalePercent, step: 5),
            in: Double(QuickAccessOptimizeSettings.scaleRange.lowerBound)...Double(QuickAccessOptimizeSettings.scaleRange.upperBound)
          )
          Text(sizeLabel)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 52, alignment: .trailing)
        }
      }

      row(L10n.QuickAccess.optimizeFormatLabel) {
        Picker("", selection: $settings.format) {
          ForEach(QuickAccessOptimizeFormat.allCases) { format in
            let name = format == .original
              ? L10n.QuickAccess.optimizeFormatOriginal
              : format.displayName(originalExtension: nil)
            if format.isEncoderAvailable {
              Text(name).tag(format)
            } else {
              Text(L10n.PreferencesCapture.imageFormatUnavailableOption(name))
                .tag(format)
                .disabled(true)
            }
          }
        }
        .labelsHidden()
        // Six formats no longer fit a segmented control in the 360pt popover.
        .pickerStyle(.menu)
        .help(settings.format.displayName(originalExtension: originalExtension))
      }

      row(L10n.QuickAccess.optimizeQualityLabel) {
        HStack(spacing: 8) {
          Slider(
            value: intBinding(\.qualityPercent, step: 5),
            in: Double(QuickAccessOptimizeSettings.qualityRange.lowerBound)...Double(QuickAccessOptimizeSettings.qualityRange.upperBound)
          )
          Text(outputIsLossy ? "\(settings.qualityPercent)" : L10n.QuickAccess.optimizeQualityLossless)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 52, alignment: .trailing)
        }
        .disabled(!outputIsLossy)
      }

      row(L10n.QuickAccess.optimizeMaxSizeLabel) {
        Picker("", selection: $settings.maxFileSize) {
          Text(L10n.Common.off).tag(Int?.none)
          ForEach(QuickAccessOptimizeSettings.maxFileSizeOptions, id: \.self) { bytes in
            Text(QuickAccessImageOptimizer.formatByteCount(bytes)).tag(Int?.some(bytes))
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
      }
    }
  }

  /// "50% · 1440×900", or just "50%" without a source.
  private var sizeLabel: String {
    guard let source else { return "\(settings.scalePercent)%" }
    let fraction = CGFloat(settings.scalePercent) / 100
    let width = Int((CGFloat(source.pixelWidth) * fraction).rounded())
    let height = Int((CGFloat(source.pixelHeight) * fraction).rounded())
    return "\(settings.scalePercent)% · \(width)×\(height)"
  }

  private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    HStack(alignment: .center, spacing: 10) {
      Text(title)
        .font(.system(size: 12))
        .frame(width: labelWidth, alignment: .leading)
      content()
    }
  }

  private func intBinding(_ keyPath: WritableKeyPath<QuickAccessOptimizeSettings, Int>, step: Int) -> Binding<Double> {
    Binding(
      get: { Double(settings[keyPath: keyPath]) },
      set: { settings[keyPath: keyPath] = Int(($0 / Double(step)).rounded()) * step }
    )
  }
}

// MARK: - Editor model

@MainActor
final class QuickAccessOptimizeCustomModel: ObservableObject {
  let itemID: UUID
  let source: QuickAccessOptimizeCustomSource

  @Published var settings: QuickAccessOptimizeSettings {
    didSet { if settings != oldValue { scheduleRender() } }
  }
  @Published private(set) var rendering: QuickAccessOptimizeRendering?
  @Published private(set) var renderedSettings: QuickAccessOptimizeSettings?
  @Published private(set) var isRendering = false
  @Published private(set) var renderFailed = false
  @Published var isNamingPreset = false
  @Published var presetName = ""
  @Published private(set) var savedPresetName: String?
  /// Drives the bubble in/out animation; the panel stays up until it has played.
  @Published var isShown = false

  var onApply: ((QuickAccessOptimizeSettings, QuickAccessOptimizeRendering?) -> Void)?
  var onCancel: (() -> Void)?

  private var image: CGImage?
  private var renderTask: Task<Void, Never>?

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  init(itemID: UUID, source: QuickAccessOptimizeCustomSource, settings: QuickAccessOptimizeSettings) {
    self.itemID = itemID
    self.source = source
    self.settings = settings.clamped
  }

  func start() {
    isRendering = true
    renderTask = Task { [weak self, source] in
      let image = await QuickAccessOptimizeStore.loadImage(of: source)
      guard let self, !Task.isCancelled else { return }
      self.image = image
      if image == nil {
        self.isRendering = false
        self.renderFailed = true
      } else {
        self.scheduleRender(debounce: false)
      }
    }
  }

  func stop() {
    renderTask?.cancel()
    renderTask = nil
  }

  /// The preview matches what Apply would write.
  var renderingIsCurrent: Bool {
    renderedSettings == settings.clamped && rendering != nil
  }

  func apply() {
    QuickAccessOptimizePresetStore.shared.setLastCustomSettings(settings)
    onApply?(settings.clamped, renderingIsCurrent ? rendering : nil)
  }

  func cancel() {
    onCancel?()
  }

  func beginNamingPreset() {
    presetName = ""
    isNamingPreset = true
  }

  func savePreset() {
    let preset = QuickAccessOptimizePresetStore.shared.addPreset(name: presetName, settings: settings)
    savedPresetName = preset.name
    isNamingPreset = false
  }

  private func scheduleRender(debounce: Bool = true) {
    guard let image else { return }
    renderTask?.cancel()
    isRendering = true
    renderFailed = false
    let settings = settings.clamped
    let source = source
    renderTask = Task { [weak self] in
      if debounce {
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }
      }
      let result = await Task.detached(priority: .userInitiated) {
        QuickAccessImageOptimizer.render(
          settings,
          from: image,
          source: source.info,
          originalExtension: source.originalExtension,
          isCancelled: { Task.isCancelled }
        )
      }.value
      guard let self, !Task.isCancelled else { return }
      self.rendering = result
      self.renderedSettings = settings
      self.renderFailed = result == nil
      self.isRendering = false
    }
  }
}

// MARK: - Editor view

struct QuickAccessOptimizeCustomView: View {
  @ObservedObject var model: QuickAccessOptimizeCustomModel

  static let shadowPadding: CGFloat = 16
  static let width: CGFloat = 360

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.liquidGlassRenderMode) private var renderMode
  @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true
  @FocusState private var isNameFieldFocused: Bool

  private var usesNativeGlass: Bool {
    LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: usesNativeGlass ? 22 : 12, style: .continuous)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(L10n.QuickAccess.optimizeCustomTitle)
        .font(.system(size: 13, weight: .semibold))

      QuickAccessOptimizeSettingsForm(
        settings: $model.settings,
        source: model.source.info,
        originalExtension: model.source.originalExtension
      )

      Divider().opacity(0.5)

      preview

      footer
    }
    .padding(16)
    .frame(width: Self.width)
    .background(
      shape.fill(Color.black.opacity(usesNativeGlass ? 0.5 : 0.18))
        .shadow(color: .black.opacity(usesNativeGlass ? 0.35 : 1), radius: 14, y: 6)
    )
    .liquidGlassSurface(shape: shape, substrate: 0.3, layer: .backdrop, nativeVariant: .clear)
    .overlay {
      if !usesNativeGlass {
        shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
      }
    }
    .environment(\.colorScheme, .dark)
    .scaleEffect(model.isShown || reduceMotion ? 1 : 0.6, anchor: .center)
    .opacity(model.isShown ? 1 : 0)
    .padding(Self.shadowPadding)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.QuickAccess.optimizeCustomTitle)
  }

  // MARK: Preview

  @ViewBuilder
  private var preview: some View {
    HStack(spacing: 6) {
      if let rendering = model.rendering {
        if let original = model.source.originalByteCount {
          Text(QuickAccessImageOptimizer.formatByteCount(original))
            .foregroundStyle(.secondary)
          Image(systemName: "arrow.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        Text(QuickAccessImageOptimizer.formatByteCount(rendering.data.count))
          .fontWeight(.semibold)
        if let savings = QuickAccessOptimizeMenuFormatting.savingsLabel(
          byteCount: rendering.data.count,
          originalByteCount: model.source.originalByteCount
        ) {
          Text(savings)
            .foregroundColor(Color(red: 0.45, green: 0.9, blue: 0.6))
        }
        Spacer(minLength: 4)
        Text(rendering.dimensionsLabel)
          .foregroundStyle(.secondary)
      } else if model.renderFailed {
        Text(L10n.QuickAccess.optimizeFailed)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      } else {
        Text(L10n.QuickAccess.optimizeEstimating)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }

      if model.isRendering {
        ProgressView()
          .controlSize(.small)
          .scaleEffect(0.6)
          .frame(width: 14, height: 14)
      }
    }
    .font(.system(size: 12).monospacedDigit())
    .opacity(model.isRendering && model.rendering != nil ? 0.6 : 1)
    .animation(.easeOut(duration: 0.12), value: model.isRendering)

    if let rendering = model.rendering, !rendering.meetsFileSizeLimit, let limit = model.renderedSettings?.maxFileSize {
      Label(
        L10n.QuickAccess.optimizeLimitNotMet(QuickAccessImageOptimizer.formatByteCount(limit)),
        systemImage: "exclamationmark.triangle.fill"
      )
      .font(.system(size: 11))
      .foregroundColor(.yellow.opacity(0.9))
    }
  }

  // MARK: Footer

  @ViewBuilder
  private var footer: some View {
    if model.isNamingPreset {
      HStack(spacing: 8) {
        TextField(L10n.QuickAccess.optimizePresetNamePlaceholder, text: $model.presetName)
          .textFieldStyle(.roundedBorder)
          .focused($isNameFieldFocused)
          .onSubmit { model.savePreset() }
          .onAppear { isNameFieldFocused = true }
        Button(L10n.Common.cancel) { model.isNamingPreset = false }
        Button(L10n.Common.save) { model.savePreset() }
          .keyboardShortcut(.defaultAction)
      }
      .controlSize(.small)
    } else {
      HStack(spacing: 8) {
        if let saved = model.savedPresetName {
          Label(L10n.QuickAccess.optimizePresetSaved(saved), systemImage: "checkmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else {
          Button(L10n.QuickAccess.optimizeSaveAsPreset) { model.beginNamingPreset() }
        }
        Spacer(minLength: 8)
        Button(L10n.Common.cancel) { model.cancel() }
          .keyboardShortcut(.cancelAction)
        Button(L10n.Common.apply) { model.apply() }
          .keyboardShortcut(.defaultAction)
          .disabled(model.renderFailed)
      }
      .controlSize(.small)
    }
  }
}
