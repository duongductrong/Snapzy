//
//  VideoEditorCaptionsPanel.swift
//  Snapzy
//
//  Left sidebar panel for captions: generate/regenerate (with language), style & font
//  library (system, installed macOS fonts, opt-in SHA-256 verified SIL OFL 1.1 downloads,
//  and local TTF/OTF imports), burn-in, SRT/WebVTT export and the editable caption list.
//

import AppKit
import Speech
import SwiftUI
import UniformTypeIdentifiers

struct VideoEditorCaptionsPanel: View {
  @ObservedObject var state: VideoEditorState
  @ObservedObject private var fontManager = VideoEditorFontManager.shared
  @State private var dragStart: VideoEditorCaptions?
  @State private var isShowingFontLibrary = false
  @State private var fontSearchQuery = ""
  @State private var licensePreviewFamily: VideoEditorCatalogFontFamily?

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
    .sheet(item: $licensePreviewFamily) { family in
      oflLicenseSheet(for: family)
    }
  }

  // MARK: - Sections

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

  @ViewBuilder
  private var styleSection: some View {
    toggle(L10n.VideoEditor.captionsShow, \.isEnabled)
    Group {
      fontPickerSection

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
      toggle(L10n.VideoEditor.captionsItalic, \.isItalic)
      ColorPicker(L10n.VideoEditor.captionsTextColor, selection: colorBinding, supportsOpacity: false)
        .font(Typography.labelSmall)
      toggle(L10n.VideoEditor.captionsHideFastSpeed, \.hideDuringFastSpeed)
    }
    .disabled(!state.captions.settings.isEnabled)
  }

  @ViewBuilder
  private var fontPickerSection: some View {
    let s = state.captions.settings
    let fontAvailable = fontManager.isFontAvailable(s.customFontId)
    let activeFontName = fontManager.displayName(for: s.customFontId)

    VStack(alignment: .leading, spacing: Spacing.xs) {
      label(L10n.VideoEditor.fontLibraryButton)

      Button {
        isShowingFontLibrary.toggle()
      } label: {
        HStack(spacing: 6) {
          Text(activeFontName)
            .font(Font(VideoEditorFontResolver.cachedPreviewFont(
              familyId: s.customFontId,
              size: 12,
              weight: 600,
              italic: false
            )))
            .foregroundColor(.primary)
            .lineLimit(1)

          Spacer(minLength: 4)

          HStack(spacing: 3) {
            Image(systemName: "textformat")
              .font(.system(size: 10, weight: .semibold))
            Text(L10n.VideoEditor.fontLibraryButton)
              .font(.system(size: 10, weight: .semibold))
              .lineLimit(1)
          }
          .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
          Radius.rect(Radius.ornament)
            .fill(Color.primary.opacity(0.055))
            .overlay(
              Radius.rect(Radius.ornament)
                .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.6)
            )
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(L10n.VideoEditor.fontLibraryButton)
      .accessibilityIdentifier("video-editor.open-font-library")
      .popover(isPresented: $isShowingFontLibrary, arrowEdge: .trailing) {
        fontLibraryPopover
      }

      if !fontAvailable {
        let missingCatalogFamily = VideoEditorFontManager.curatedCatalog.first { $0.id == s.customFontId }
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(.orange)
          Text(L10n.VideoEditor.fontMissingNotice)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundColor(SidebarColors.labelSecondary)
            .lineLimit(1)
          Spacer(minLength: 4)
          if let missingCatalogFamily {
            if fontManager.downloadingIds.contains(missingCatalogFamily.id) {
              ProgressView()
                .controlSize(.mini)
            } else {
              Button {
                Task {
                  try? await fontManager.downloadCatalogFont(missingCatalogFamily)
                  if fontManager.downloadedCatalogIds.contains(missingCatalogFamily.id) {
                    applyFont(missingCatalogFamily.id)
                  }
                }
              } label: {
                Text(L10n.VideoEditor.fontDownloadOFLButton)
                  .font(.system(size: 9.5, weight: .semibold))
                  .lineLimit(1)
                  .foregroundColor(.accentColor)
              }
              .buttonStyle(.plain)
            }
          }
          Button {
            applyFont(VideoEditorFontResolver.defaultFamilyId)
          } label: {
            Text(L10n.VideoEditor.fontUseSystemSubstitute)
              .font(.system(size: 9.5, weight: .semibold))
              .lineLimit(1)
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.10), in: Radius.rect(Radius.ornament))
      }
    }
  }

  private var fontLibraryPopover: some View {
    let currentFontId = state.captions.settings.customFontId
    let trimmedQuery = fontSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    let filteredInstalled: [VideoEditorInstalledFontFamily] = if trimmedQuery.isEmpty {
      fontManager.installedFamilies
    } else {
      fontManager.installedFamilies.filter {
        $0.familyName.localizedCaseInsensitiveContains(trimmedQuery)
      }
    }
    let filteredCatalog: [VideoEditorCatalogFontFamily] = if trimmedQuery.isEmpty {
      VideoEditorFontManager.curatedCatalog
    } else {
      VideoEditorFontManager.curatedCatalog.filter {
        $0.displayName.localizedCaseInsensitiveContains(trimmedQuery)
          || $0.categoryLabel.localizedCaseInsensitiveContains(trimmedQuery)
      }
    }
    let filteredImported: [VideoEditorImportedFontRecord] = if trimmedQuery.isEmpty {
      fontManager.importedFonts
    } else {
      fontManager.importedFonts.filter {
        $0.displayName.localizedCaseInsensitiveContains(trimmedQuery)
      }
    }

    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(L10n.VideoEditor.fontLibraryButton)
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Button {
          importCustomFontViaPicker()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "plus.circle.fill")
              .font(.system(size: 10.5, weight: .semibold))
            Text(L10n.VideoEditor.fontImportLocalFile)
              .font(.system(size: 10.5, weight: .semibold))
              .lineLimit(1)
          }
          .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("video-editor.import-local-font-button")
      }

      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(.secondary)
        TextField(L10n.VideoEditor.fontSearchPlaceholder, text: $fontSearchQuery)
          .textFieldStyle(.plain)
          .font(.system(size: 11))
        if !fontSearchQuery.isEmpty {
          Button {
            fontSearchQuery = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 10))
              .foregroundColor(.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 8)
      .frame(height: 26)
      .background(
        Radius.controlRect(forHeight: 26)
          .fill(Color.primary.opacity(0.05))
          .overlay(Radius.controlRect(forHeight: 26).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
      )

      Divider()

      ScrollView(.vertical, showsIndicators: true) {
        LazyVStack(alignment: .leading, spacing: 3.5) {
          // 1. macOS System Font (SF Pro) first
          if trimmedQuery.isEmpty || L10n.VideoEditor.systemFontDisplayName
            .localizedCaseInsensitiveContains(trimmedQuery) {
            fontRow(
              id: VideoEditorFontResolver.defaultFamilyId,
              name: L10n.VideoEditor.systemFontDisplayName,
              subtitle: "macOS System",
              useResolvedPreview: false,
              isSelected: currentFontId == VideoEditorFontResolver.defaultFamilyId || currentFontId.isEmpty
            ) {
              applyFont(VideoEditorFontResolver.defaultFamilyId)
              isShowingFontLibrary = false
            }
          }

          // 2. Installed Device Font Families (`NSFontManager.shared.availableFontFamilies`)
          if !filteredInstalled.isEmpty {
            Text(L10n.VideoEditor.installedFontsSection)
              .font(.system(size: 9.5, weight: .semibold))
              .foregroundColor(SidebarColors.labelTertiary)
              .padding(.horizontal, 4)
              .padding(.top, 4)

            ForEach(filteredInstalled) { fam in
              fontRow(
                id: fam.id,
                name: fam.familyName,
                subtitle: fam.familyName,
                useResolvedPreview: true,
                isSelected: currentFontId == fam.id
              ) {
                applyFont(fam.id)
                isShowingFontLibrary = false
              }
            }
          }

          // 3. Opt-In Downloadable SIL Open Font License (OFL 1.1) Catalog
          if !filteredCatalog.isEmpty {
            VStack(alignment: .leading, spacing: 1.5) {
              Text(L10n.VideoEditor.oflFontsSection)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(SidebarColors.labelTertiary)
              Text(L10n.VideoEditor.fontSourceAttribution)
                .font(.system(size: 8.5))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 5)

            ForEach(filteredCatalog) { item in
              catalogFontRow(item, currentFontId: currentFontId)
            }
          }

          // 4. User-Imported Local `.ttf` / `.otf` / `.ttc` Font Files
          if !filteredImported.isEmpty {
            Text(L10n.VideoEditor.importedFontsSection)
              .font(.system(size: 9.5, weight: .semibold))
              .foregroundColor(SidebarColors.labelTertiary)
              .padding(.horizontal, 4)
              .padding(.top, 4)

            ForEach(filteredImported) { custom in
              fontRow(
                id: custom.id,
                name: custom.displayName,
                subtitle: "TTF / OTF",
                useResolvedPreview: true,
                isSelected: currentFontId == custom.id
              ) {
                applyFont(custom.id)
                isShowingFontLibrary = false
              }
            }
          }
        }
      }
      .frame(maxHeight: 280)

      if let err = fontManager.lastErrorMessage {
        Text(err)
          .font(.system(size: 10))
          .foregroundColor(.red)
          .lineLimit(2)
      }
    }
    .padding(11)
    .frame(width: 284)
  }

  private func fontRow(
    id: String,
    name: String,
    subtitle: String,
    useResolvedPreview: Bool,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        VStack(alignment: .leading, spacing: 1) {
          Text(name)
            .font(
              useResolvedPreview
                ? Font(VideoEditorFontResolver.cachedPreviewFont(
                  familyId: id,
                  size: 12,
                  weight: 600,
                  italic: false
                ))
                : .system(size: 12, weight: .semibold)
            )
            .foregroundColor(.primary)
            .lineLimit(1)

          if subtitle != name {
            Text(subtitle)
              .font(.system(size: 9.5))
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 12))
            .foregroundColor(.accentColor)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(
        Radius.controlRect(forHeight: 24)
          .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("video-editor.font-item.\(id)")
  }

  private func catalogFontRow(
    _ item: VideoEditorCatalogFontFamily,
    currentFontId: String
  ) -> some View {
    let isDownloaded = fontManager.downloadedCatalogIds.contains(item.id)
    let isDownloading = fontManager.downloadingIds.contains(item.id)
    let isSelected = currentFontId == item.id

    return HStack(spacing: 6) {
      Button {
        guard isDownloaded else { return }
        applyFont(item.id)
        isShowingFontLibrary = false
      } label: {
        VStack(alignment: .leading, spacing: 1) {
          Text(item.displayName)
            .font(
              isDownloaded
                ? Font(VideoEditorFontResolver.cachedPreviewFont(
                  familyId: item.id,
                  size: 12,
                  weight: 600,
                  italic: false
                ))
                : .system(size: 12, weight: .medium)
            )
            .foregroundColor(isDownloaded ? .primary : SidebarColors.labelSecondary)
            .lineLimit(1)

          Text("\(item.categoryLabel) · SIL OFL 1.1")
            .font(.system(size: 9.5))
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!isDownloaded)

      if isDownloading {
        ProgressView()
          .controlSize(.small)
      } else if isDownloaded {
        Button {
          licensePreviewFamily = item
        } label: {
          Image(systemName: "doc.text")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(.secondary)
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(L10n.VideoEditor.fontLicenseButton)
        .accessibilityLabel(L10n.VideoEditor.fontLicenseButton)

        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 12))
            .foregroundColor(.accentColor)
        }
      } else {
        Button {
          Task {
            try? await fontManager.downloadCatalogFont(item)
            if fontManager.downloadedCatalogIds.contains(item.id) {
              applyFont(item.id)
            }
          }
        } label: {
          HStack(spacing: 3) {
            Image(systemName: "arrow.down.circle")
              .font(.system(size: 10, weight: .semibold))
            Text(L10n.VideoEditor.fontDownloadOFLButton)
              .font(.system(size: 9.5, weight: .semibold))
              .lineLimit(1)
          }
          .foregroundColor(.accentColor)
          .padding(.horizontal, 7)
          .padding(.vertical, 3.5)
          .background(Color.accentColor.opacity(0.11), in: Radius.rect(Radius.ornament))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("video-editor.download-ofl-font.\(item.id)")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(
      Radius.controlRect(forHeight: 24)
        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
    )
    .accessibilityIdentifier("video-editor.catalog-font-item.\(item.id)")
  }

  private func oflLicenseSheet(for family: VideoEditorCatalogFontFamily) -> some View {
    let text = fontManager.licenseText(for: family.id) ?? L10n.VideoEditor.fontSourceAttribution
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(family.displayName) — \(L10n.VideoEditor.fontLicenseButton)")
            .font(.system(size: 13, weight: .semibold))
          Text(L10n.VideoEditor.fontSourceAttribution)
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
        }
        Spacer()
        Button(L10n.Common.done) {
          licensePreviewFamily = nil
        }
        .keyboardShortcut(.cancelAction)
      }

      Divider()

      ScrollView {
        Text(text)
          .font(.system(size: 11, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
      }
      .background(Color.primary.opacity(0.04), in: Radius.rect(Radius.ornament))
    }
    .padding(16)
    .frame(width: 520, height: 420)
  }

  private func applyFont(_ familyId: String) {
    var settings = state.captions.settings
    settings.customFontId = familyId
    state.setCaptionSettings(settings)
  }

  private func importCustomFontViaPicker() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [
      .font,
      UTType(filenameExtension: "ttf") ?? .font,
      UTType(filenameExtension: "otf") ?? .font,
      UTType(filenameExtension: "ttc") ?? .font,
    ]
    guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
    if let importedId = fontManager.importFontFiles(from: panel.urls) {
      applyFont(importedId)
      isShowingFontLibrary = false
    }
  }

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
        if keyPath == \VideoEditorCaptionSettings.isBold {
          settings.fontWeight = settings.isBold ? max(700, settings.fontWeight) : min(500, settings.fontWeight)
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
