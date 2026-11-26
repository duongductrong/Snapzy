//
//  VideoEditorCaptionsPanel.swift
//  Snapzy
//
//  Left sidebar panel for captions: on-device speech recognition (with language picker),
//  manual cue creation, SRT/WebVTT import & export, full style controls (including
//  position, text size, background opacity, bold, text color, word timing, and fast-speed
//  hiding), Text Studio (`Aa`) conversion/sync, and the editable caption list.
//

import AppKit
import Speech
import SwiftUI
import UniformTypeIdentifiers

struct VideoEditorCaptionsPanel: View {
  @ObservedObject var state: VideoEditorState
  @ObservedObject private var fontManager = VideoEditorFontManager.shared
  @State private var dragStart: VideoEditorCaptions?

  /// Languages SFSpeech knows, sorted by name in the current language.
  private static let languages: [(id: String, name: String)] = SFSpeechRecognizer.supportedLocales()
    .map { ($0.identifier, Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: Spacing.md) {
        VideoSidebarSectionHeader(title: L10n.VideoEditor.captionsSection)

        if state.canEditCaptions {
          authoringActionsRow

          if state.canGenerateCaptions {
            generateSection
          }

          textStudioBridgeCard

          if state.selectedCaptionIds.count > 1 {
            bulkSelectionBar
          }

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

  private var authoringActionsRow: some View {
    HStack(spacing: 6) {
      Button {
        _ = state.addManualCaptionAtPlayhead()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "plus")
            .font(.system(size: 9.5, weight: .bold))
          Text(L10n.VideoEditor.captionsAddManual)
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color.accentColor, in: Radius.controlRect(forHeight: 24))
      }
      .buttonStyle(.plain)
      .disabled(state.isExporting)
      .accessibilityLabel(L10n.VideoEditor.captionsAddManual)
      .accessibilityIdentifier("video-editor.add-manual-caption-button")

      Button {
        importSubtitlesViaPicker()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "square.and.arrow.down")
            .font(.system(size: 9.5, weight: .semibold))
          Text(L10n.VideoEditor.captionsImportFile)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.08), in: Radius.controlRect(forHeight: 24))
      }
      .buttonStyle(.plain)
      .disabled(state.isExporting)
      .accessibilityLabel(L10n.VideoEditor.captionsImportFile)
    }
  }

  @ViewBuilder
  private var generateSection: some View {
    if state.captions.isEmpty {
      note(L10n.VideoEditor.captionsHint)
    }
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
    if let notice = state.captionNotice {
      note(notice)
    }
  }

  private var bulkSelectionBar: some View {
    HStack(spacing: 8) {
      Text(L10n.VideoEditor.bulkSelectedCount(state.selectedCaptionIds.count))
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(SidebarColors.labelPrimary)
        .lineLimit(1)
      Spacer(minLength: 4)
      Button(role: .destructive) {
        _ = state.deleteSelectedCaptions()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "trash")
            .font(.system(size: 10, weight: .semibold))
          Text(L10n.VideoEditor.deleteSelectedAll)
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
        }
        .foregroundColor(.red)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.14), in: Radius.rect(Radius.ornament))
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(Color.accentColor.opacity(0.10), in: Radius.rect(Radius.card))
    .overlay(Radius.rect(Radius.card).strokeBorder(Color.accentColor.opacity(0.32), lineWidth: 0.75))
  }

  // MARK: - Text Studio (`Aa`) Bridge Card

  private var textStudioBridgeCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 5) {
        Image(systemName: "textformat")
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(.accentColor)
        Text(activeFontBadgeTitle)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(1)
        Spacer()
        Button {
          state.leftSidebarPanel = .text
          state.isLeftSidebarVisible = true
        } label: {
          Text("Aa")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Radius.rect(Radius.ornament))
        }
        .buttonStyle(.plain)
        .help(L10n.VideoEditor.captionsOpenTextStudio)
      }

      if !state.captions.isEmpty {
        Button {
          _ = state.convertAllCaptionsToTextOverlays()
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "arrow.up.forward.square")
              .font(.system(size: 9.5, weight: .semibold))
            Text(L10n.VideoEditor.captionsConvertAllToText)
              .font(.system(size: 10, weight: .semibold))
              .lineLimit(1)
          }
          .foregroundColor(.accentColor)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 5)
          .background(Color.accentColor.opacity(0.11), in: Radius.rect(Radius.ornament))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("video-editor.convert-all-captions-to-text")
      }

      if !state.textOverlays.isEmpty {
        Button {
          state.syncSelectedTextStyleToCaptions()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "arrow.down.doc")
              .font(.system(size: 9, weight: .semibold))
            Text(L10n.VideoEditor.captionsSyncStyleFromText)
              .font(.system(size: 9.5, weight: .medium))
              .lineLimit(1)
          }
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 4.5)
          .background(Color.primary.opacity(0.07), in: Radius.rect(Radius.ornament))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("video-editor.sync-captions-from-text")
      }
    }
    .padding(8)
    .background(
      Radius.rect(Radius.card)
        .fill(Color.primary.opacity(0.035))
        .overlay(Radius.rect(Radius.card).strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.5))
    )
  }

  private var activeFontBadgeTitle: String {
    let baseName = fontManager.displayName(for: state.captions.settings.customFontId)
    let weight = state.captions.settings.resolvedWeight
    if state.captions.settings.resolvedItalic {
      return "\(baseName) \(weight) \(L10n.VideoEditor.italicBadgeSuffix)"
    }
    return "\(baseName) \(weight)"
  }

  @ViewBuilder
  private var styleSection: some View {
    toggle(L10n.VideoEditor.captionsShow, \.isEnabled)
      .accessibilityIdentifier("video-editor.captions-enabled-toggle")

    Group {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        label(L10n.VideoEditor.captionsPosition)
        Picker("", selection: binding(\.position)) {
          Text(L10n.VideoEditor.captionsPositionBottom).tag(VideoEditorCaptionSettings.Position.bottom)
          Text(L10n.VideoEditor.center).tag(VideoEditorCaptionSettings.Position.center)
          Text(L10n.VideoEditor.captionsPositionTop).tag(VideoEditorCaptionSettings.Position.top)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }

      VStack(alignment: .leading, spacing: Spacing.xs) {
        label(L10n.VideoEditor.captionsWordMode)
        Picker("", selection: binding(\.wordMode)) {
          Text(L10n.VideoEditor.captionsWordFullLine).tag(VideoEditorCaptionSettings.WordMode.fullLine)
          Text(L10n.VideoEditor.captionsWordActiveHighlight).tag(VideoEditorCaptionSettings.WordMode.activeHighlight)
          Text(L10n.VideoEditor.captionsWordProgressiveReveal)
            .tag(VideoEditorCaptionSettings.WordMode.progressiveReveal)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
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

  private var exportSection: some View {
    HStack(spacing: Spacing.xs) {
      Button(L10n.VideoEditor.captionsExportSRT) { exportSubtitles(vtt: false) }
      Button(L10n.VideoEditor.captionsExportVTT) { exportSubtitles(vtt: true) }
    }
    .controlSize(.small)
  }

  // MARK: - Import & Export

  private func importSubtitlesViaPicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [
      UTType(filenameExtension: "srt") ?? .plainText,
      UTType(filenameExtension: "vtt") ?? .plainText,
      .plainText,
    ]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    _ = state.importSubtitles(from: url)
  }

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
          red: ns.redComponent,
          green: ns.greenComponent,
          blue: ns.blueComponent,
          alpha: 1
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
        if keyPath == \VideoEditorCaptionSettings.isBold {
          if settings.isBold, settings.fontWeight < 700 {
            settings.fontWeight = 700
          } else if !settings.isBold, settings.fontWeight >= 700 {
            settings.fontWeight = 500
          }
          settings.syncLegacyFontFamilyEnum()
        }
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
      Slider(
        value: Binding(
          get: { state.captions.settings[keyPath: keyPath] },
          set: { newValue in
            if dragStart == nil {
              dragStart = state.captions
            }
            var settings = state.captions.settings
            settings[keyPath: keyPath] = newValue
            state.setCaptionSettings(settings, recordUndo: false)
          }
        ),
        in: range
      ) { editing in
        if editing {
          if dragStart == nil {
            dragStart = state.captions
          }
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
