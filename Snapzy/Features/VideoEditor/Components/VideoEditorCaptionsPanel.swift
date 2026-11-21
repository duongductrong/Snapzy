//
//  VideoEditorCaptionsPanel.swift
//  Snapzy
//
//  Left sidebar panel for captions: generate/regenerate (with language), style, burn-in,
//  SRT/WebVTT export and the editable caption list. Every edit is undoable.
//

import Speech
import SwiftUI
import UniformTypeIdentifiers

struct VideoEditorCaptionsPanel: View {
  @ObservedObject var state: VideoEditorState
  @State private var dragStart: VideoEditorCaptions?

  /// Languages SFSpeech knows, sorted by name in the current language.
  private static let languages: [(id: String, name: String)] = SFSpeechRecognizer.supportedLocales()
    .map { ($0.identifier, Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        VideoSidebarSectionHeader(title: L10n.VideoEditor.captionsSection)
        if state.canGenerateCaptions {
          generateSection
          if !state.captions.isEmpty {
            Divider()
            styleSection
            Divider()
            exportSection
            Divider()
            VideoEditorCaptionSegmentList(state: state)
          }
        } else {
          note(L10n.VideoEditor.captionsUnavailableNotice)
        }
        Spacer(minLength: Spacing.lg)
      }
      .padding(Spacing.md)
    }
    .frame(maxHeight: .infinity)
  }

  // MARK: - Sections

  @ViewBuilder
  private var generateSection: some View {
    if state.captions.isEmpty { note(L10n.VideoEditor.captionsHint) }
    VStack(alignment: .leading, spacing: Spacing.xs) {
      label(L10n.VideoEditor.captionsLanguage)
      Picker("", selection: languageBinding) {
        Text(L10n.VideoEditor.captionsLanguageAutomatic(languageName(VideoEditorState.defaultCaptionLocale())))
          .tag("")
        Divider()
        ForEach(Self.languages, id: \.id) { Text($0.name).tag($0.id) }
      }
      .labelsHidden()
      .controlSize(.small)
    }
    Button(state.captions.isEmpty ? L10n.VideoEditor.captionsGenerate : L10n.VideoEditor.captionsRegenerate) {
      state.generateCaptions()
    }
    .controlSize(.small)
    .disabled(state.isGeneratingCaptions || state.isExporting)
    if let notice = state.captionNotice { note(notice) }
  }

  @ViewBuilder
  private var styleSection: some View {
    toggle(L10n.VideoEditor.captionsShow, \.isEnabled)
    Group {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        label(L10n.VideoEditor.captionsPosition)
        Picker("", selection: binding(\.position)) {
          Text(L10n.VideoEditor.captionsPositionBottom).tag(VideoEditorCaptionSettings.Position.bottom)
          Text(L10n.VideoEditor.captionsPositionTop).tag(VideoEditorCaptionSettings.Position.top)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }
      slider(L10n.VideoEditor.captionsTextSize, \.fontSize, range: VideoEditorCaptionSettings.fontSizeRange)
      slider(L10n.VideoEditor.captionsBackground, \.backgroundOpacity, range: 0 ... 1)
      toggle(L10n.VideoEditor.captionsBold, \.isBold)
      ColorPicker(L10n.VideoEditor.captionsTextColor, selection: colorBinding, supportsOpacity: false)
        .font(Typography.labelSmall)
      toggle(L10n.VideoEditor.captionsHideFastSpeed, \.hideDuringFastSpeed)
    }
    .disabled(!state.captions.settings.isEnabled)
  }

  @ViewBuilder
  private var exportSection: some View {
    HStack(spacing: Spacing.xs) {
      Button(L10n.VideoEditor.captionsExportSRT) { exportSubtitles(vtt: false) }
      Button(L10n.VideoEditor.captionsExportVTT) { exportSubtitles(vtt: true) }
    }
    .controlSize(.small)
  }

  // MARK: - Export

  private func exportSubtitles(vtt: Bool) {
    let ext = vtt ? "vtt" : "srt"
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .plainText]
    panel.nameFieldStringValue = state.sourceURL.deletingPathExtension().lastPathComponent + "." + ext
    panel.canCreateDirectories = true
    let text = state.subtitleText(vtt: vtt)
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      do {
        try text.write(to: url, atomically: true, encoding: .utf8)
      } catch {
        DiagnosticLogger.shared.logError(.export, error, "Caption export failed")
        state.captionNotice = L10n.VideoEditor.captionsExportFailed
      }
    }
  }

  // MARK: - Controls

  private var languageBinding: Binding<String> {
    Binding(
      get: { state.captions.settings.languageIdentifier ?? "" },
      set: { value in
        var settings = state.captions.settings
        settings.languageIdentifier = value.isEmpty ? nil : value
        state.setCaptionSettings(settings)
        VideoEditorState.rememberCaptionLanguage(settings.languageIdentifier)
      }
    )
  }

  private var colorBinding: Binding<Color> {
    Binding(
      get: {
        let c = state.captions.settings.textColor
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
      },
      set: { color in
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
        var settings = state.captions.settings
        settings.textColor = VideoEditorRGBAColor(
          red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: 1
        )
        state.setCaptionSettings(settings)
      }
    )
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<VideoEditorCaptionSettings, Value>) -> Binding<Value> {
    Binding(
      get: { state.captions.settings[keyPath: keyPath] },
      set: { newValue in
        var settings = state.captions.settings
        settings[keyPath: keyPath] = newValue
        state.setCaptionSettings(settings, recordUndo: dragStart == nil)
      }
    )
  }

  private func toggle(_ title: String, _ keyPath: WritableKeyPath<VideoEditorCaptionSettings, Bool>) -> some View {
    Toggle(title, isOn: binding(keyPath))
      .font(Typography.labelSmall)
      .toggleStyle(.switch)
      .controlSize(.small)
  }

  private func slider(
    _ title: String,
    _ keyPath: WritableKeyPath<VideoEditorCaptionSettings, CGFloat>,
    range: ClosedRange<CGFloat>
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      label(title)
      Slider(value: binding(keyPath), in: range) { editing in
        if editing {
          dragStart = state.captions
        } else if let start = dragStart {
          dragStart = nil
          state.commitCaptions(from: start)
        }
      }
      .controlSize(.small)
    }
  }

  private func label(_ text: String) -> some View {
    Text(text)
      .font(Typography.labelSmall)
      .foregroundColor(SidebarColors.labelSecondary)
  }

  private func note(_ text: String) -> some View {
    label(text).fixedSize(horizontal: false, vertical: true)
  }

  private func languageName(_ locale: Locale) -> String {
    Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
  }
}
