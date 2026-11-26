//
//  VideoEditorTextStyleTabView.swift
//  Snapzy
//
//  Tab 2 (`Style`) of the Text Studio inspector panel: Typography (System SF Pro
//  default, installed macOS font families via `NSFontManager.shared.availableFontFamilies`,
//  and local `.ttf`/`.otf`/`.ttc` imports), Color & Surface, and Layout controls.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoEditorTextStyleTabView: View {
  @ObservedObject var state: VideoEditorState
  let overlay: VideoEditorTextOverlay?
  let onCommitTextFocus: () -> Void

  @ObservedObject private var fontManager = VideoEditorFontManager.shared
  @State private var isShowingFontLibrary = false
  @State private var fontSearchQuery = ""
  @State private var sliderBefore: [VideoEditorTextOverlay]?

  var body: some View {
    if let overlay {
      VStack(alignment: .leading, spacing: 10) {
        typographyCard(for: overlay)
        colorAndSurfaceCard(for: overlay)
        layoutCard(for: overlay)
      }
      .onDisappear {
        commitSliderIfNeeded()
      }
    } else {
      VideoEditorTextInspectorUI.noSelectionPromptCard(state: state)
    }
  }

  // MARK: - Typography Card & Font Picker

  private func typographyCard(for overlay: VideoEditorTextOverlay) -> some View {
    let s = overlay.style
    let fontAvailable = fontManager.isFontAvailable(s.customFontId)
    let activeFontName = fontManager.displayName(for: s.customFontId)

    return VideoEditorTextInspectorUI.card {
      VideoEditorTextInspectorUI.cardHeader(L10n.VideoEditor.textSectionTypography)

      Button {
        onCommitTextFocus()
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
        fontLibraryPopover(for: overlay)
      }

      if !fontAvailable {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(.orange)
          Text(L10n.VideoEditor.fontMissingNotice)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundColor(SidebarColors.labelSecondary)
            .lineLimit(1)
          Spacer(minLength: 4)
          Button {
            mutateStyle(id: overlay.id) { $0.customFontId = VideoEditorFontResolver.defaultFamilyId }
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

      HStack(spacing: 6) {
        Picker(
          "",
          selection: Binding(
            get: { nearestWeightTier(for: s.fontWeight) },
            set: { tier in
              mutateStyle(id: overlay.id) { $0.setWeightTier(tier) }
            }
          )
        ) {
          Text(L10n.VideoEditor.fontWeightRegular).tag(VideoEditorCaptionSettings.WeightTier.regular)
          Text(L10n.VideoEditor.fontWeightMedium).tag(VideoEditorCaptionSettings.WeightTier.medium)
          Text(L10n.VideoEditor.fontWeightSemiBold).tag(VideoEditorCaptionSettings.WeightTier.semiBold)
          Text(L10n.VideoEditor.fontWeightBold).tag(VideoEditorCaptionSettings.WeightTier.bold)
          Text(L10n.VideoEditor.fontWeightExtraBold).tag(VideoEditorCaptionSettings.WeightTier.extraBold)
          Text(L10n.VideoEditor.fontWeightBlack).tag(VideoEditorCaptionSettings.WeightTier.black)
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(maxWidth: .infinity)

        Button {
          mutateStyle(id: overlay.id) { $0.toggleBold() }
        } label: {
          Image(systemName: "bold")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundColor(s.isBold ? .white : .primary)
            .frame(width: 26, height: 23)
            .background(
              Radius.rect(Radius.ornament)
                .fill(s.isBold ? Color.accentColor : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(L10n.VideoEditor.toggleBoldHint)
        .accessibilityIdentifier("video-editor.text-bold-toggle")

        Button {
          mutateStyle(id: overlay.id) { $0.toggleItalic() }
        } label: {
          Image(systemName: "italic")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundColor(s.resolvedItalic ? .white : .primary)
            .frame(width: 26, height: 23)
            .background(
              Radius.rect(Radius.ornament)
                .fill(s.resolvedItalic ? Color.accentColor : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(L10n.VideoEditor.captionsItalic)
        .accessibilityIdentifier("video-editor.text-italic-toggle")

        HStack(spacing: 2) {
          casePill(.standard, label: "Aa", overlay: overlay)
          casePill(.uppercase, label: "AA", overlay: overlay)
          casePill(.lowercase, label: "aa", overlay: overlay)
        }
        .padding(2)
        .background(Color.primary.opacity(0.05), in: Radius.rect(Radius.ornament))
      }
    }
  }

  private func fontLibraryPopover(for overlay: VideoEditorTextOverlay) -> some View {
    let trimmedQuery = fontSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    let filteredInstalled: [VideoEditorInstalledFontFamily] = if trimmedQuery.isEmpty {
      fontManager.installedFamilies
    } else {
      fontManager.installedFamilies.filter {
        $0.familyName.localizedCaseInsensitiveContains(trimmedQuery)
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
          importCustomFontViaPicker(applyTo: overlay.id)
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
              isSelected: overlay.style.customFontId == VideoEditorFontResolver.defaultFamilyId
                || overlay.style.customFontId.isEmpty
            ) {
              mutateStyle(id: overlay.id) { $0.customFontId = VideoEditorFontResolver.defaultFamilyId }
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
                isSelected: overlay.style.customFontId == fam.id
              ) {
                mutateStyle(id: overlay.id) { $0.customFontId = fam.id }
                isShowingFontLibrary = false
              }
            }
          }

          // 3. User-Imported Local `.ttf` / `.otf` / `.ttc` Font Files
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
                isSelected: overlay.style.customFontId == custom.id
              ) {
                mutateStyle(id: overlay.id) { $0.customFontId = custom.id }
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
                ? Font.custom(subtitle, size: 12)
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

  private func importCustomFontViaPicker(applyTo overlayId: UUID) {
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
    let selectedURLs = panel.urls
    Task { @MainActor in
      if let importedId = await fontManager.importFontFilesAsync(from: selectedURLs) {
        mutateStyle(id: overlayId) { $0.customFontId = importedId }
        isShowingFontLibrary = false
      }
    }
  }

  // MARK: - Color & Surface Card

  private func colorAndSurfaceCard(for overlay: VideoEditorTextOverlay) -> some View {
    let s = overlay.style

    return VideoEditorTextInspectorUI.card {
      VideoEditorTextInspectorUI.cardHeader(L10n.VideoEditor.textSectionColorSurface)

      HStack(spacing: 5) {
        VideoEditorTextInspectorUI.labeledColorWell(
          title: L10n.VideoEditor.textColorInk,
          selection: rgbaBinding(for: overlay.id, \.textColor)
        )

        if s.useGradientText {
          Image(systemName: "arrow.right")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundColor(SidebarColors.labelTertiary)

          VideoEditorTextInspectorUI.labeledColorWell(
            title: L10n.VideoEditor.textColorGradientEnd,
            selection: rgbaBinding(for: overlay.id, \.textGradientEndColor)
          )
        }

        Spacer(minLength: 2)

        Toggle(L10n.VideoEditor.captionsGradientText, isOn: styleBinding(for: overlay.id, \.useGradientText))
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(SidebarColors.labelSecondary)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .toggleStyle(.switch)
          .controlSize(.mini)
      }

      Divider().opacity(0.5)

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          VideoEditorTextInspectorUI.rowLabel(L10n.VideoEditor.captionsTreatmentLabel)
          Spacer()
          VideoEditorTextInspectorUI.labeledColorWell(
            title: L10n.VideoEditor.textColorAccentShort,
            selection: rgbaBinding(for: overlay.id, \.accentColor)
          )
        }

        HStack(spacing: 3) {
          treatmentPill(.solid, title: L10n.VideoEditor.captionsTreatmentSolid, overlay: overlay)
          treatmentPill(.splitAccent, title: L10n.VideoEditor.captionsTreatmentSplit, overlay: overlay)
          treatmentPill(.hollowHero, title: L10n.VideoEditor.captionsTreatmentHollow, overlay: overlay)
        }
        .padding(2)
        .background(Color.primary.opacity(0.05), in: Radius.controlRect(forHeight: 26))
      }

      Divider().opacity(0.5)

      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          VideoEditorTextInspectorUI.rowLabel(L10n.VideoEditor.textSurfaceLabel)
          Spacer(minLength: 4)
          Picker("", selection: styleBinding(for: overlay.id, \.surfaceStyle)) {
            ForEach(VideoEditorCaptionSettings.SurfaceStyle.allCases, id: \.self) { surface in
              Text(VideoEditorTextInspectorUI.surfaceDisplayName(surface)).tag(surface)
            }
          }
          .labelsHidden()
          .controlSize(.small)
          .frame(maxWidth: 164)
        }

        if s.surfaceStyle.drawsBackdropBox {
          HStack(spacing: 8) {
            VideoEditorTextInspectorUI.labeledColorWell(
              title: L10n.VideoEditor.textColorSurfaceShort,
              selection: rgbaBinding(for: overlay.id, \.backgroundColor)
            )

            VStack(alignment: .leading, spacing: 2) {
              HStack {
                Text(L10n.VideoEditor.textBackdropOpacity)
                  .font(.system(size: 10, weight: .medium))
                  .foregroundColor(SidebarColors.labelSecondary)
                Spacer()
                Text("\(Int((s.backgroundOpacity * 100).rounded()))%")
                  .font(.system(size: 10, weight: .semibold).monospacedDigit())
                  .foregroundColor(SidebarColors.labelSecondary)
              }
              Slider(value: continuousStyleBinding(for: overlay.id, \.backgroundOpacity), in: 0 ... 1) { editing in
                handleSliderEditing(editing)
              }
              .controlSize(.small)
            }
          }
        }
      }

      Divider().opacity(0.5)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          VideoEditorTextInspectorUI.rowLabel(L10n.VideoEditor.captionsGlow)
          Spacer()
          Text("\(Int((s.glowIntensity * 100).rounded()))%")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundColor(SidebarColors.labelSecondary)
          ColorPicker("", selection: rgbaBinding(for: overlay.id, \.glowColor), supportsOpacity: false)
            .labelsHidden()
            .help(L10n.VideoEditor.captionsGlow)
        }

        Slider(value: continuousStyleBinding(for: overlay.id, \.glowIntensity), in: 0 ... 1) { editing in
          handleSliderEditing(editing)
        }
        .controlSize(.small)
      }
    }
  }

  // MARK: - Layout Card

  private func layoutCard(for overlay: VideoEditorTextOverlay) -> some View {
    let s = overlay.style

    return VideoEditorTextInspectorUI.card {
      VideoEditorTextInspectorUI.cardHeader(L10n.VideoEditor.textSectionLayout)

      labeledSlider(
        title: L10n.Common.size,
        displayValue: "\(Int((s.fontSize * 720).rounded())) pt",
        value: continuousStyleBinding(for: overlay.id, \.fontSize),
        range: VideoEditorCaptionSettings.fontSizeRange,
        accessibilityId: "video-editor.text-font-size-slider"
      )

      labeledSlider(
        title: L10n.VideoEditor.textMaxWidthWrap,
        displayValue: "\(Int((s.maxWidthFraction * 100).rounded()))%",
        value: continuousStyleBinding(for: overlay.id, \.maxWidthFraction),
        range: VideoEditorCaptionSettings.maxWidthFractionRange,
        accessibilityId: "video-editor.text-wrap-width-slider"
      )

      VStack(alignment: .leading, spacing: 4) {
        VideoEditorTextInspectorUI.rowLabel(L10n.VideoEditor.captionsTracking)
        HStack(spacing: 3) {
          trackingPill(.tight, title: L10n.VideoEditor.captionsTrackingTight, overlay: overlay)
          trackingPill(.normal, title: L10n.VideoEditor.captionsTrackingNormal, overlay: overlay)
          trackingPill(.wide, title: L10n.VideoEditor.captionsTrackingWide, overlay: overlay)
          trackingPill(.cinema, title: L10n.VideoEditor.captionsTrackingCinema, overlay: overlay)
        }
        .padding(2)
        .background(Color.primary.opacity(0.05), in: Radius.controlRect(forHeight: 25))
      }

      VStack(alignment: .leading, spacing: 4) {
        VideoEditorTextInspectorUI.rowLabel(L10n.VideoEditor.captionsPosition)
        HStack(spacing: 4) {
          positionPill(L10n.VideoEditor.positionTop, y: 0.16, overlay: overlay)
          positionPill(L10n.VideoEditor.center, y: 0.50, overlay: overlay)
          positionPill(L10n.VideoEditor.positionBottom, y: 0.80, overlay: overlay)
        }
      }

      Divider().opacity(0.5)

      Toggle(L10n.VideoEditor.textDualLineHeroFull, isOn: styleBinding(for: overlay.id, \.dualLineHero))
        .font(.system(size: 10.5, weight: .medium))
        .lineLimit(1)
        .toggleStyle(.switch)
        .controlSize(.small)

      if state.textOverlays.count > 1 {
        HStack(spacing: 6) {
          Button {
            onCommitTextFocus()
            _ = state.applySelectedTextStyleToAll(includeMotion: false)
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "paintbrush.pointed")
                .font(.system(size: 9.5, weight: .semibold))
              Text(L10n.VideoEditor.textApplyStyleToAll)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
            }
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(Color.accentColor.opacity(0.10), in: Radius.rect(Radius.ornament))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("video-editor.apply-style-to-all-text")

          Button {
            onCommitTextFocus()
            _ = state.applySelectedTextStyleToAll(includeMotion: true)
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 9.5, weight: .semibold))
              Text(L10n.VideoEditor.textApplyStyleMotionToAll)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.84)
            }
            .foregroundColor(SidebarColors.labelPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(
              Radius.rect(Radius.ornament)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                  Radius.rect(Radius.ornament)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
            )
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("video-editor.apply-style-motion-to-all-text")
        }
      }

      Button {
        onCommitTextFocus()
        state.syncSelectedTextStyleToCaptions()
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "captions.bubble")
            .font(.system(size: 10, weight: .semibold))
          Text(L10n.VideoEditor.textSyncStyleToCaptions)
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
        }
        .foregroundColor(.accentColor)
        .frame(maxWidth: .infinity)
        .frame(height: 27)
        .background(Color.accentColor.opacity(0.11), in: Radius.rect(Radius.ornament))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("video-editor.sync-text-style-to-captions")
    }
  }

  // MARK: - Controls & Bindings

  private func labeledSlider(
    title: String,
    displayValue: String,
    value: Binding<CGFloat>,
    range: ClosedRange<CGFloat>,
    accessibilityId: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        VideoEditorTextInspectorUI.rowLabel(title)
        Spacer()
        Text(displayValue)
          .font(.system(size: 10, weight: .semibold).monospacedDigit())
          .foregroundColor(SidebarColors.labelSecondary)
      }
      Slider(value: value, in: range) { editing in
        handleSliderEditing(editing)
      }
      .controlSize(.small)
      .accessibilityIdentifier(accessibilityId)
    }
  }

  private func casePill(
    _ value: VideoEditorCaptionSettings.TextCase,
    label: String,
    overlay: VideoEditorTextOverlay
  ) -> some View {
    let selected = overlay.style.textCase == value
    return Button {
      mutateStyle(id: overlay.id) { $0.textCase = value }
    } label: {
      Text(label)
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(selected ? .white : SidebarColors.labelSecondary)
        .frame(width: 24, height: 19)
        .background(Radius.rect(Radius.ornament).fill(selected ? Color.accentColor : .clear))
    }
    .buttonStyle(.plain)
  }

  private func treatmentPill(
    _ value: VideoEditorCaptionSettings.TextTreatment,
    title: String,
    overlay: VideoEditorTextOverlay
  ) -> some View {
    let selected = overlay.style.textTreatment == value
    return Button {
      mutateStyle(id: overlay.id) { $0.textTreatment = value }
    } label: {
      Text(title)
        .font(.system(size: 10, weight: selected ? .semibold : .medium))
        .foregroundColor(selected ? .white : SidebarColors.labelSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.84)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .background(Radius.controlRect(forHeight: 22).fill(selected ? Color.accentColor : .clear))
        .contentShape(Radius.controlRect(forHeight: 22))
    }
    .buttonStyle(.plain)
  }

  private func trackingPill(
    _ value: VideoEditorCaptionSettings.TrackingPreset,
    title: String,
    overlay: VideoEditorTextOverlay
  ) -> some View {
    let selected = overlay.style.tracking == value
    return Button {
      mutateStyle(id: overlay.id) { $0.tracking = value }
    } label: {
      Text(title)
        .font(.system(size: 10, weight: selected ? .semibold : .medium))
        .foregroundColor(selected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.84)
        .frame(maxWidth: .infinity)
        .frame(height: 21)
        .background {
          if selected {
            Radius.controlRect(forHeight: 21)
              .fill(Color.primary.opacity(0.12))
              .overlay(
                Radius.controlRect(forHeight: 21)
                  .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
              )
          }
        }
        .contentShape(Radius.controlRect(forHeight: 21))
    }
    .buttonStyle(.plain)
  }

  private func positionPill(_ label: String, y: CGFloat, overlay: VideoEditorTextOverlay) -> some View {
    let isActive = abs(overlay.normalizedX - 0.5) < 0.04 && abs(overlay.normalizedY - y) < 0.05
    return Button {
      state.updateTextOverlay(id: overlay.id) { item in
        item.normalizedX = 0.5
        item.normalizedY = y
      }
    } label: {
      Text(label)
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(isActive ? .white : SidebarColors.labelSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(height: 23)
        .background(
          Radius.rect(Radius.ornament)
            .fill(isActive ? Color.accentColor : Color.primary.opacity(0.06))
        )
    }
    .buttonStyle(.plain)
  }

  private func nearestWeightTier(for w: Int) -> VideoEditorCaptionSettings.WeightTier {
    VideoEditorCaptionSettings.WeightTier.allCases
      .min { abs($0.rawValue - w) < abs($1.rawValue - w) } ?? .bold
  }

  private func mutateStyle(id: UUID, recordUndo: Bool = true, _ body: (inout VideoEditorCaptionSettings) -> Void) {
    state.updateTextOverlay(id: id, recordUndo: recordUndo) { item in
      body(&item.style)
      item.syncLegacyMirrorFromStyle()
    }
  }

  private func styleBinding<Value>(
    for id: UUID,
    _ keyPath: WritableKeyPath<VideoEditorCaptionSettings, Value>
  ) -> Binding<Value> {
    Binding(
      get: {
        state.textOverlays.first(where: { $0.id == id })?.style[keyPath: keyPath]
          ?? VideoEditorCaptionSettings.default[keyPath: keyPath]
      },
      set: { newValue in
        mutateStyle(id: id) { $0[keyPath: keyPath] = newValue }
      }
    )
  }

  private func continuousStyleBinding<Value>(
    for id: UUID,
    _ keyPath: WritableKeyPath<VideoEditorCaptionSettings, Value>
  ) -> Binding<Value> {
    Binding(
      get: {
        state.textOverlays.first(where: { $0.id == id })?.style[keyPath: keyPath]
          ?? VideoEditorCaptionSettings.default[keyPath: keyPath]
      },
      set: { newValue in
        if sliderBefore == nil {
          sliderBefore = state.textOverlays
        }
        mutateStyle(id: id, recordUndo: false) { $0[keyPath: keyPath] = newValue }
      }
    )
  }

  private func rgbaBinding(
    for id: UUID,
    _ keyPath: WritableKeyPath<VideoEditorCaptionSettings, VideoEditorRGBAColor>
  ) -> Binding<Color> {
    Binding(
      get: {
        let c = state.textOverlays.first(where: { $0.id == id })?.style[keyPath: keyPath]
          ?? VideoEditorCaptionSettings.default[keyPath: keyPath]
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
      },
      set: { color in
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
        mutateStyle(id: id) {
          $0[keyPath: keyPath] = VideoEditorRGBAColor(
            red: ns.redComponent,
            green: ns.greenComponent,
            blue: ns.blueComponent,
            alpha: 1
          )
        }
      }
    )
  }

  private func handleSliderEditing(_ editing: Bool) {
    if editing {
      if sliderBefore == nil {
        sliderBefore = state.textOverlays
      }
    } else {
      commitSliderIfNeeded()
    }
  }

  private func commitSliderIfNeeded() {
    if let before = sliderBefore {
      sliderBefore = nil
      state.commitTextOverlayEdit(previous: before)
    }
  }
}
