//
//  VideoEditorTextItemsTabView.swift
//  Snapzy
//
//  Tab 4 (`Items`) of the Text Studio inspector panel: timeline title list
//  with playhead jump, convert-to-caption action, delete, and Captions import banner.
//

import AVFoundation
import SwiftUI

struct VideoEditorTextItemsTabView: View {
  @ObservedObject var state: VideoEditorState
  let onCommitTextFocus: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if state.textOverlays.isEmpty {
        VideoEditorTextInspectorUI.card {
          VStack(spacing: 8) {
            Image(systemName: "textformat")
              .font(.system(size: 18, weight: .regular))
              .foregroundColor(SidebarColors.labelTertiary)

            Text(L10n.VideoEditor.textItemsEmpty)
              .font(.system(size: 11, weight: .medium))
              .foregroundColor(SidebarColors.labelSecondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
        }
      } else {
        VideoEditorTextInspectorUI.card {
          ForEach(state.textOverlays) { overlay in
            let isSelected = state.selectedTextOverlayId == overlay.id
            HStack(spacing: 6) {
              Button {
                onCommitTextFocus()
                state.selectTextOverlay(id: overlay.id)
                let now = CMTimeGetSeconds(state.currentTime)
                if now < overlay.startTime || now >= overlay.endTime {
                  state.seek(to: CMTime(
                    seconds: overlay.startTime + min(0.2, overlay.duration / 2),
                    preferredTimescale: 600
                  ))
                }
              } label: {
                HStack(spacing: 6) {
                  Image(systemName: "textformat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                  VStack(alignment: .leading, spacing: 1) {
                    Text(overlay.text.isEmpty ? L10n.VideoEditor.defaultTitleText : overlay.text)
                      .font(.system(size: 11, weight: .medium))
                      .foregroundColor(.primary)
                      .lineLimit(1)

                    Text("\(formatTimestamp(overlay.startTime)) – \(formatTimestamp(overlay.endTime))")
                      .font(.system(size: 9.5).monospacedDigit())
                      .foregroundColor(.secondary)
                  }

                  Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)

              Button {
                onCommitTextFocus()
                _ = state.convertTextOverlayToCaption(id: overlay.id)
              } label: {
                Image(systemName: "captions.bubble")
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundColor(.accentColor)
                  .frame(width: 24, height: 24)
                  .background(Color.accentColor.opacity(0.10), in: Radius.rect(Radius.ornament))
              }
              .buttonStyle(.plain)
              .help(L10n.VideoEditor.textConvertToCaption)

              Button(role: .destructive) {
                onCommitTextFocus()
                state.removeTextOverlay(id: overlay.id)
              } label: {
                Image(systemName: "trash")
                  .font(.system(size: 10, weight: .medium))
                  .foregroundColor(.secondary)
                  .frame(width: 24, height: 24)
                  .background(Color.primary.opacity(0.06), in: Radius.rect(Radius.ornament))
              }
              .buttonStyle(.plain)
              .help(L10n.VideoEditor.deleteTextOverlayHint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
              Radius.rect(Radius.ornament)
                .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035))
                .overlay(
                  Radius.rect(Radius.ornament)
                    .strokeBorder(
                      isSelected ? Color.accentColor.opacity(0.50) : Color.primary.opacity(0.07),
                      lineWidth: 0.75
                    )
                )
            )
          }
        }
      }

      if !state.captions.isEmpty {
        VideoEditorTextInspectorUI.captionsQuickImportBanner(
          state: state,
          onCommitTextFocus: onCommitTextFocus
        )
      }
    }
  }

  private func formatTimestamp(_ seconds: TimeInterval) -> String {
    let clamped = seconds.isFinite ? max(0, seconds) : 0
    let mins = Int(clamped) / 60
    let secs = clamped - Double(mins * 60)
    return String(format: "%d:%04.1f", mins, secs)
  }
}
