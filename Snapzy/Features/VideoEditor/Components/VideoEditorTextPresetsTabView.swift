//
//  VideoEditorTextPresetsTabView.swift
//  Snapzy
//
//  Tab 1 (`Presets`) of the Text Studio inspector panel. Isolated into its own
//  view struct and backed by `VideoEditorFontResolver.cachedPreviewFont` so slider
//  drags in `Style` or `Motion` never re-evaluate or re-resolve preset specimens.
//

import SwiftUI

struct VideoEditorTextPresetsTabView: View {
  let state: VideoEditorState
  let selectedOverlayId: UUID?
  let selectedPreset: VideoEditorCaptionSettings.EditorialPreset?
  let fontId: String
  let hasCaptions: Bool
  let onCommitTextFocus: () -> Void

  @State private var hoveredPreset: VideoEditorCaptionSettings.EditorialPreset?

  private let presetColumns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VideoEditorTextInspectorUI.cardHeader(L10n.VideoEditor.captionsPresets)
          Spacer()
          Text("12")
            .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
            .foregroundColor(SidebarColors.labelTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .padding(.horizontal, 2)

        LazyVGrid(columns: presetColumns, spacing: 8) {
          ForEach(VideoEditorCaptionSettings.EditorialPreset.allCases) { preset in
            let isSelected = selectedPreset == preset && selectedOverlayId != nil
            let isHovered = hoveredPreset == preset

            Button {
              onCommitTextFocus()
              if let overlayId = selectedOverlayId {
                state.applyTextPreset(preset, to: overlayId)
              } else {
                state.addTextOverlayAtPlayheadAndOpenPanel(preset: preset)
              }
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                ZStack {
                  Radius.rect(Radius.ornament)
                    .fill(VideoEditorTextInspectorUI.stageMatteColor)
                    .overlay(
                      Radius.rect(Radius.ornament)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
                    .frame(height: 44)

                  architecturalSpecimen(for: preset, fontId: fontId)
                    .padding(.horizontal, 6)
                }

                HStack(spacing: 4) {
                  Text(VideoEditorTextInspectorUI.presetDisplayName(preset))
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? SidebarColors.labelPrimary : SidebarColors.labelSecondary)
                    .lineLimit(1)

                  Spacer(minLength: 2)

                  if isSelected {
                    Circle()
                      .fill(Color.accentColor)
                      .frame(width: 5.5, height: 5.5)
                  }
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 1)
              }
              .padding(5)
              .background(
                Radius.rect(Radius.tile)
                  .fill(
                    isSelected
                      ? Color.accentColor.opacity(0.11)
                      : (isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
                  )
                  .overlay(
                    Radius.rect(Radius.tile)
                      .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(isHovered ? 0.15 : 0.075),
                        lineWidth: isSelected ? 1.25 : 0.5
                      )
                  )
              )
              .contentShape(Radius.rect(Radius.tile))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
              hoveredPreset = hovering ? preset : (hoveredPreset == preset ? nil : hoveredPreset)
            }
            .accessibilityLabel(VideoEditorTextInspectorUI.presetDisplayName(preset))
            .accessibilityIdentifier("video-editor.text-preset.\(preset.rawValue)")
          }
        }
      }

      if selectedOverlayId == nil {
        if hasCaptions {
          VideoEditorTextInspectorUI.captionsQuickImportBanner(
            state: state,
            onCommitTextFocus: onCommitTextFocus
          )
        } else {
          VideoEditorTextInspectorUI.card {
            Text(L10n.VideoEditor.textEmptyHeadline)
              .font(.system(size: 10.5, weight: .medium))
              .foregroundColor(SidebarColors.labelSecondary)
              .fixedSize(horizontal: false, vertical: true)

            Text(L10n.VideoEditor.textEmptySubheadline)
              .font(.system(size: 10))
              .foregroundColor(SidebarColors.labelTertiary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  private func specimenFont(familyId: String, size: CGFloat, weight: Int, italic: Bool) -> Font {
    Font(VideoEditorFontResolver.cachedPreviewFont(
      familyId: familyId,
      size: size,
      weight: weight,
      italic: italic
    ))
  }

  @ViewBuilder
  private func architecturalSpecimen(
    for preset: VideoEditorCaptionSettings.EditorialPreset,
    fontId: String
  ) -> some View {
    switch preset {
    case .cyberCyan:
      VStack(spacing: 0) {
        Text("lead")
          .font(.system(size: 7.5, weight: .medium))
          .foregroundColor(.white.opacity(0.72))
        Text("HERO")
          .font(specimenFont(familyId: fontId, size: 12.5, weight: 800, italic: false))
          .foregroundColor(Color(red: 0.42, green: 0.86, blue: 1.0))
      }

    case .velvetSerif:
      Text("Velvet")
        .font(specimenFont(familyId: fontId, size: 13, weight: 700, italic: true))
        .foregroundColor(Color(red: 0.66, green: 0.54, blue: 1.0))

    case .splitTone:
      HStack(spacing: 3) {
        Text("Key")
          .foregroundColor(.white)
        Text("Focus")
          .foregroundColor(Color(red: 0.24, green: 0.78, blue: 1.0))
      }
      .font(specimenFont(familyId: fontId, size: 11.5, weight: 800, italic: false))

    case .hollowHero:
      HStack(spacing: 3) {
        Text("OUT")
          .foregroundColor(.white.opacity(0.45))
        Text("PRO")
          .foregroundColor(.white)
      }
      .font(specimenFont(familyId: fontId, size: 11.5, weight: 900, italic: false))

    case .rangeHighlight:
      Text("Select")
        .font(specimenFont(familyId: fontId, size: 10.5, weight: 600, italic: false))
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color(red: 0.09, green: 0.33, blue: 0.74).opacity(0.78))
        .overlay(alignment: .leading) {
          Rectangle().fill(Color(red: 0.29, green: 0.64, blue: 0.99)).frame(width: 1.8)
        }
        .overlay(alignment: .trailing) {
          Rectangle().fill(Color(red: 0.29, green: 0.64, blue: 0.99)).frame(width: 1.8)
        }

    case .selectFrame:
      Text("Frame")
        .font(specimenFont(familyId: fontId, size: 10.5, weight: 600, italic: false))
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .overlay(Rectangle().strokeBorder(Color(red: 0.23, green: 0.51, blue: 0.96), lineWidth: 1.1))

    case .solarSheen:
      Text("Preset")
        .font(specimenFont(familyId: fontId, size: 10.5, weight: 700, italic: false))
        .foregroundColor(Color(red: 0.04, green: 0.04, blue: 0.05))
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .background(
          Color(red: 1.0, green: 0.86, blue: 0.0),
          in: Radius.rect(Radius.ornament)
        )

    case .goldSlide:
      Text("SLIDE")
        .font(specimenFont(familyId: fontId, size: 12, weight: 900, italic: false))
        .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.22))

    case .editorialInk:
      Text("Paper")
        .font(specimenFont(familyId: fontId, size: 10.5, weight: 700, italic: false))
        .foregroundColor(Color(red: 0.07, green: 0.07, blue: 0.07))
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .background(
          Color(red: 0.98, green: 0.98, blue: 0.98),
          in: Radius.rect(Radius.ornament)
        )

    case .kineticPulse:
      HStack(spacing: 3) {
        Text("Live")
          .foregroundColor(.white.opacity(0.75))
        Text("Word")
          .foregroundColor(Color(red: 0.04, green: 0.05, blue: 0.08))
          .padding(.horizontal, 4.5)
          .padding(.vertical, 1)
          .background(Color(red: 0.24, green: 0.72, blue: 0.94), in: Radius.rect(Radius.ornament))
      }
      .font(specimenFont(familyId: fontId, size: 10, weight: 700, italic: false))

    case .monoTag:
      HStack(spacing: 4) {
        Circle()
          .fill(Color(red: 0.06, green: 0.73, blue: 0.51))
          .frame(width: 5, height: 5)
        Text("status")
          .font(specimenFont(familyId: fontId, size: 10, weight: 600, italic: false))
          .foregroundColor(.white)
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 2.5)
      .overlay(
        Radius.rect(Radius.ornament)
          .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
      )

    case .cinemaIvory:
      Text("Cinema")
        .font(specimenFont(familyId: fontId, size: 11.5, weight: 500, italic: true))
        .tracking(1.2)
        .foregroundColor(Color(red: 1.0, green: 0.96, blue: 0.82))
    }
  }
}
