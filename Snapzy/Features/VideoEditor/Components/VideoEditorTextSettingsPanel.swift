//
//  VideoEditorTextSettingsPanel.swift
//  Snapzy
//
//  300pt Typography & Motion Studio (`Aa`) inspector panel shell.
//  Each tab (`Presets`, `Style`, `Motion`, `Items`) lives in its own dedicated
//  subview struct so continuous slider drags only re-evaluate the active tab.
//

import AppKit
import AVFoundation
import SwiftUI

enum VideoEditorTextStudioTab: String, CaseIterable, Identifiable {
  case presets
  case style
  case motion
  case items

  var id: String {
    rawValue
  }
}

enum VideoEditorTextMotionSubTab: String, CaseIterable, Identifiable {
  case enter
  case exit
  case word

  var id: String {
    rawValue
  }
}

struct VideoEditorTextSettingsPanel: View {
  @ObservedObject var state: VideoEditorState

  @FocusState private var isTextFieldFocused: Bool
  @State private var selectedTab: VideoEditorTextStudioTab = .presets
  @State private var localText: String = ""
  @State private var textEditBefore: [VideoEditorTextOverlay]?
  @State private var editingOverlayId: UUID?
  @Namespace private var tabNamespace

  private var selectedOverlay: VideoEditorTextOverlay? {
    state.selectedTextOverlay
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 10) {
        headerSection

        if state.selectedTextOverlayIds.count > 1 {
          bulkSelectionBanner
        }

        if let overlay = selectedOverlay {
          textInputCard(for: overlay)
        }

        studioTabSwitcher

        switch selectedTab {
        case .presets:
          VideoEditorTextPresetsTabView(
            state: state,
            selectedOverlayId: selectedOverlay?.id,
            selectedPreset: selectedOverlay?.style.matchingPreset,
            fontId: selectedOverlay?.style.customFontId ?? VideoEditorFontResolver.defaultFamilyId,
            hasCaptions: !state.captions.isEmpty,
            onCommitTextFocus: commitAndResignFocus
          )

        case .style:
          VideoEditorTextStyleTabView(
            state: state,
            overlay: selectedOverlay,
            onCommitTextFocus: commitAndResignFocus
          )

        case .motion:
          VideoEditorTextMotionTabView(
            state: state,
            overlay: selectedOverlay,
            onCommitTextFocus: commitAndResignFocus
          )

        case .items:
          VideoEditorTextItemsTabView(
            state: state,
            onCommitTextFocus: commitAndResignFocus
          )
        }

        Spacer(minLength: 10)
      }
      .padding(12)
    }
    .frame(maxHeight: .infinity)
    .onAppear {
      syncLocalFields()
      if selectedOverlay != nil, selectedTab == .presets {
        selectedTab = .style
      }
    }
    .onChange(of: state.selectedTextOverlayId) { _ in
      commitPendingTextEdit()
      syncLocalFields()
    }
    .onChange(of: selectedOverlay?.text) { _ in
      if !isTextFieldFocused {
        syncLocalFields()
      }
    }
    .onChange(of: isTextFieldFocused) { focused in
      if focused {
        state.beginTextFieldEditing(token: "text-sidebar")
      } else {
        state.endTextFieldEditing(token: "text-sidebar")
        commitPendingTextEdit()
      }
    }
    .onDisappear {
      commitPendingTextEdit()
      state.endTextFieldEditing(token: "text-sidebar")
    }
    .accessibilityIdentifier("video-editor.text-settings-panel")
  }

  // MARK: - Top Studio Toolbar & 4-Tab Segmented Switcher

  private var bulkSelectionBanner: some View {
    HStack(spacing: 8) {
      Text(L10n.VideoEditor.bulkSelectedCount(state.selectedTextOverlayIds.count))
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(SidebarColors.labelPrimary)
        .lineLimit(1)
      Spacer(minLength: 4)
      Button(role: .destructive) {
        commitAndResignFocus()
        _ = state.removeSelectedTextOverlays()
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

  private var headerSection: some View {
    HStack(spacing: 6) {
      Button {
        state.addTextOverlayAtPlayheadAndOpenPanel(preset: .cyberCyan)
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "plus")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.accentColor)
          Text(L10n.VideoEditor.addTitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(SidebarColors.labelPrimary)
            .lineLimit(1)
          Text("T")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(SidebarColors.labelSecondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Color.primary.opacity(0.08), in: Radius.rect(Radius.ornament))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(
          Radius.controlRect(forHeight: 28)
            .fill(Color.accentColor.opacity(0.12))
            .overlay(
              Radius.controlRect(forHeight: 28)
                .strokeBorder(Color.accentColor.opacity(0.34), lineWidth: 0.75)
            )
        )
        .contentShape(Radius.controlRect(forHeight: 28))
      }
      .buttonStyle(.plain)
      .disabled(state.isGIF)
      .accessibilityLabel(L10n.VideoEditor.addTextAtPlayhead)
      .accessibilityIdentifier("video-editor.add-text-overlay-button")

      if !state.captions.isEmpty {
        Button {
          commitAndResignFocus()
          state.leftSidebarPanel = .captions
          state.isLeftSidebarVisible = true
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "captions.bubble")
              .font(.system(size: 10, weight: .semibold))
            Text("\(state.captions.segments.count)")
              .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
              .foregroundColor(.accentColor)
          }
          .foregroundColor(SidebarColors.labelSecondary)
          .padding(.horizontal, 8)
          .frame(height: 28)
          .background(
            Radius.controlRect(forHeight: 28)
              .fill(Color.primary.opacity(0.05))
              .overlay(
                Radius.controlRect(forHeight: 28)
                  .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
              )
          )
        }
        .buttonStyle(.plain)
        .help(L10n.VideoEditor.captionsSection)
      }
    }
  }

  private var studioTabSwitcher: some View {
    HStack(spacing: 2) {
      ForEach(VideoEditorTextStudioTab.allCases) { tab in
        let isSelected = selectedTab == tab
        Button {
          commitAndResignFocus()
          withAnimation(LiquidGlassTokens.settleSpring) {
            selectedTab = tab
          }
        } label: {
          HStack(spacing: 3) {
            Text(tabTitle(for: tab))
              .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
              .lineLimit(1)
              .minimumScaleFactor(0.82)

            if tab == .items, !state.textOverlays.isEmpty {
              Text("\(state.textOverlays.count)")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundColor(isSelected ? .accentColor : SidebarColors.labelTertiary)
            }
          }
          .foregroundColor(isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
          .frame(maxWidth: .infinity)
          .frame(height: 24)
          .background {
            if isSelected {
              Radius.controlRect(forHeight: 24)
                .fill(Color.primary.opacity(0.11))
                .overlay(
                  Radius.controlRect(forHeight: 24)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                )
                .matchedGeometryEffect(id: "textStudioTabThumb", in: tabNamespace)
            }
          }
          .contentShape(Radius.controlRect(forHeight: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tabTitle(for: tab))
        .accessibilityIdentifier("video-editor.text-tab.\(tab.rawValue)")
      }
    }
    .padding(2)
    .background(
      Radius.controlRect(forHeight: 28)
        .fill(Color.primary.opacity(0.05))
        .overlay(
          Radius.controlRect(forHeight: 28)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    )
  }

  private func tabTitle(for tab: VideoEditorTextStudioTab) -> String {
    switch tab {
    case .presets:
      L10n.VideoEditor.textTabPresets
    case .style:
      L10n.VideoEditor.textTabDesign
    case .motion:
      L10n.VideoEditor.textTabEffects
    case .items:
      L10n.VideoEditor.textTabItems
    }
  }

  // MARK: - Selected Item Inline Text Bar

  private func textInputCard(for overlay: VideoEditorTextOverlay) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .center, spacing: 5) {
        TextField(L10n.VideoEditor.enterTitlePlaceholder, text: $localText, axis: .vertical)
          .textFieldStyle(.plain)
          .font(.system(size: 11.5, weight: .medium))
          .lineLimit(1 ... 3)
          .padding(.horizontal, 8)
          .padding(.vertical, 5.5)
          .frame(minHeight: 28)
          .background(
            Radius.controlRect(forHeight: 28)
              .fill(Color.primary.opacity(0.05))
              .overlay(
                Radius.controlRect(forHeight: 28)
                  .strokeBorder(
                    isTextFieldFocused ? Color.accentColor.opacity(0.80) : Color.primary.opacity(0.09),
                    lineWidth: isTextFieldFocused ? 1.0 : 0.5
                  )
              )
          )
          .focused($isTextFieldFocused)
          .onChange(of: localText) { newValue in
            guard editingOverlayId == overlay.id else { return }
            if textEditBefore == nil {
              textEditBefore = state.textOverlays
            }
            state.updateTextOverlay(id: overlay.id, recordUndo: false) { item in
              item.text = newValue
            }
          }
          .onSubmit {
            commitAndResignFocus()
          }
          .onExitCommand {
            commitAndResignFocus()
          }
          .accessibilityIdentifier("video-editor.text-overlay-input")

        HStack(spacing: 4) {
          Button {
            commitAndResignFocus()
            state.duplicateTextOverlay(id: overlay.id)
          } label: {
            Image(systemName: "plus.square.on.square")
              .font(.system(size: 10.5, weight: .medium))
              .foregroundColor(SidebarColors.labelSecondary)
              .frame(width: 26, height: 28)
              .background(
                Radius.rect(Radius.ornament)
                  .fill(Color.primary.opacity(0.05))
                  .overlay(
                    Radius.rect(Radius.ornament)
                      .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                  )
              )
          }
          .buttonStyle(.plain)
          .help(L10n.VideoEditor.duplicate)
          .accessibilityIdentifier("video-editor.duplicate-text-overlay")

          Button(role: .destructive) {
            commitAndResignFocus()
            state.removeTextOverlay(id: overlay.id)
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 10.5, weight: .medium))
              .foregroundColor(SidebarColors.labelSecondary)
              .frame(width: 26, height: 28)
              .background(
                Radius.rect(Radius.ornament)
                  .fill(Color.primary.opacity(0.05))
                  .overlay(
                    Radius.rect(Radius.ornament)
                      .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                  )
              )
          }
          .buttonStyle(.plain)
          .help(L10n.VideoEditor.deleteTextOverlayHint)
          .accessibilityIdentifier("video-editor.delete-text-overlay")
        }
      }

      if isTextFieldFocused {
        HStack {
          Spacer()
          Button {
            commitAndResignFocus()
          } label: {
            Text(L10n.VideoEditor.textCommitShortcutHint)
              .font(.system(size: 9.5, weight: .semibold))
              .lineLimit(1)
              .foregroundColor(.accentColor)
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(Color.accentColor.opacity(0.12), in: Capsule())
          }
          .buttonStyle(.plain)
          .keyboardShortcut(.return, modifiers: .command)
        }
      }
    }
  }

  private func syncLocalFields() {
    guard let overlay = selectedOverlay else {
      editingOverlayId = nil
      localText = ""
      return
    }
    editingOverlayId = overlay.id
    localText = overlay.text
  }

  private func commitAndResignFocus() {
    commitPendingTextEdit()
    if isTextFieldFocused {
      isTextFieldFocused = false
      NSApp.keyWindow?.makeFirstResponder(nil)
    }
  }

  private func commitPendingTextEdit() {
    if let before = textEditBefore {
      state.commitTextOverlayEdit(previous: before)
      textEditBefore = nil
    }
  }
}

// MARK: - Shared Inspector Primitives & Display Names

enum VideoEditorTextInspectorUI {
  static let stageMatteColor = Color(red: 12.0 / 255.0, green: 15.0 / 255.0, blue: 22.0 / 255.0)

  static func card(@ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      content()
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Radius.rect(Radius.card)
        .fill(Color.primary.opacity(0.035))
        .overlay(
          Radius.rect(Radius.card)
            .strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.5)
        )
    )
  }

  static func cardHeader(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(SidebarColors.labelPrimary)
  }

  static func rowLabel(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 10.5, weight: .medium))
      .foregroundColor(SidebarColors.labelSecondary)
      .lineLimit(1)
  }

  static func labeledColorWell(title: String, selection: Binding<Color>) -> some View {
    HStack(spacing: 5) {
      Text(title)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(SidebarColors.labelSecondary)
        .lineLimit(1)
      ColorPicker("", selection: selection, supportsOpacity: false)
        .labelsHidden()
    }
    .padding(.leading, 7)
    .padding(.trailing, 4)
    .padding(.vertical, 2.5)
    .background(
      Radius.rect(Radius.ornament)
        .fill(Color.primary.opacity(0.05))
        .overlay(
          Radius.rect(Radius.ornament)
            .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
        )
    )
  }

  static func noSelectionPromptCard(state: VideoEditorState) -> some View {
    card {
      VStack(alignment: .leading, spacing: 8) {
        Text(L10n.VideoEditor.textSelectOrCreateHint)
          .font(.system(size: 10.5))
          .foregroundColor(SidebarColors.labelSecondary)
          .fixedSize(horizontal: false, vertical: true)

        if let latest = state.textOverlays.last {
          Button {
            state.selectTextOverlay(id: latest.id)
          } label: {
            HStack(spacing: 5) {
              Image(systemName: "cursorarrow.click")
                .font(.system(size: 10, weight: .semibold))
              Text(latest.text.isEmpty ? L10n.VideoEditor.defaultTitleText : latest.text)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
            }
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(Color.accentColor.opacity(0.11), in: Radius.rect(Radius.ornament))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  static func captionsQuickImportBanner(state: VideoEditorState, onCommitTextFocus: @escaping () -> Void) -> some View {
    card {
      Text(L10n.VideoEditor.captionsTextRelationshipHint)
        .font(.system(size: 10.5))
        .foregroundColor(SidebarColors.labelSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Button {
        onCommitTextFocus()
        _ = state.convertAllCaptionsToTextOverlays()
      } label: {
        HStack(spacing: 5) {
          Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 10, weight: .semibold))
          Text(L10n.VideoEditor.captionsConvertAllToText)
            .font(.system(size: 10.5, weight: .semibold))
            .lineLimit(1)
        }
        .foregroundColor(.accentColor)
        .frame(maxWidth: .infinity)
        .frame(height: 27)
        .background(Color.accentColor.opacity(0.11), in: Radius.rect(Radius.ornament))
      }
      .buttonStyle(.plain)
    }
  }

  static func presetDisplayName(_ preset: VideoEditorCaptionSettings.EditorialPreset) -> String {
    switch preset {
    case .cyberCyan: L10n.VideoEditor.captionsPresetCyberCyan
    case .velvetSerif: L10n.VideoEditor.captionsPresetVelvetSerif
    case .splitTone: L10n.VideoEditor.captionsPresetSplitTone
    case .hollowHero: L10n.VideoEditor.captionsPresetHollowHero
    case .rangeHighlight: L10n.VideoEditor.captionsPresetRangeHighlight
    case .selectFrame: L10n.VideoEditor.captionsPresetSelectFrame
    case .solarSheen: L10n.VideoEditor.captionsPresetSolarSheen
    case .goldSlide: L10n.VideoEditor.captionsPresetGoldSlide
    case .editorialInk: L10n.VideoEditor.captionsPresetEditorialInk
    case .kineticPulse: L10n.VideoEditor.captionsPresetKineticPulse
    case .monoTag: L10n.VideoEditor.captionsPresetMonoTag
    case .cinemaIvory: L10n.VideoEditor.captionsPresetCinemaIvory
    }
  }

  static func surfaceDisplayName(_ surface: VideoEditorCaptionSettings.SurfaceStyle) -> String {
    switch surface {
    case .classicPill: L10n.VideoEditor.captionsSurfaceClassicPill
    case .glowBloom: L10n.VideoEditor.captionsSurfaceGlowBloom
    case .rangeHighlight: L10n.VideoEditor.captionsSurfaceRangeHighlight
    case .selectionFrame: L10n.VideoEditor.captionsSurfaceSelectionFrame
    case .solarPill: L10n.VideoEditor.captionsSurfaceSolarPill
    case .studioGlass: L10n.VideoEditor.captionsSurfaceStudioGlass
    case .editorialPaper: L10n.VideoEditor.captionsSurfaceEditorialPaper
    case .monoTag: L10n.VideoEditor.captionsSurfaceMonoTag
    case .accentRule: L10n.VideoEditor.captionsSurfaceAccentRule
    case .cinemaClean: L10n.VideoEditor.captionsSurfaceCinemaClean
    }
  }

  static func animationDisplayName(_ anim: VideoEditorCaptionSettings.AnimationStyle) -> String {
    switch anim {
    case .none: L10n.VideoEditor.noneOption
    case .wordCascade: L10n.VideoEditor.captionsAnimWordCascade
    case .wordBlurIn: L10n.VideoEditor.captionsAnimWordBlurIn
    case .typewriterPro: L10n.VideoEditor.captionsAnimTypewriterPro
    case .shutterFlip: L10n.VideoEditor.captionsAnimShutterFlip
    case .trackingPull: L10n.VideoEditor.captionsAnimTrackingPull
    case .opticalBlur: L10n.VideoEditor.captionsAnimOpticalBlur
    case .maskSlideUp: L10n.VideoEditor.captionsAnimMaskSlideUp
    case .elasticBounce: L10n.VideoEditor.captionsAnimElasticBounce
    case .whipBlur: L10n.VideoEditor.captionsAnimWhipBlur
    case .neonFlicker: L10n.VideoEditor.captionsAnimNeonFlicker
    case .springRise: L10n.VideoEditor.captionsAnimSpringRise
    case .studioPop: L10n.VideoEditor.captionsAnimStudioPop
    case .editorialWipe: L10n.VideoEditor.captionsAnimEditorialWipe
    case .cinematicFade: L10n.VideoEditor.captionsAnimCinematicFade
    case .driftSlide: L10n.VideoEditor.captionsAnimDriftSlide
    }
  }
}
