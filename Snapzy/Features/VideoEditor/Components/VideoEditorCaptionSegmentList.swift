//
//  VideoEditorCaptionSegmentList.swift
//  Snapzy
//
//  Editable caption list for the captions panel: start time (click to jump),
//  1-click promote to independent Text (`Aa`) overlay, inline text editing, and delete.
//

import AVFoundation
import SwiftUI

struct VideoEditorCaptionSegmentList: View {
  @ObservedObject var state: VideoEditorState

  var body: some View {
    LazyVStack(alignment: .leading, spacing: Spacing.xs) {
      ForEach(state.captions.segments) { segment in
        VideoEditorCaptionSegmentRow(state: state, segment: segment)
      }
    }
    Button(L10n.VideoEditor.captionsClear, role: .destructive) { state.clearCaptions() }
      .controlSize(.small)
  }
}

private struct VideoEditorCaptionSegmentRow: View {
  let state: VideoEditorState
  let segment: CaptionSegment
  @State private var draft = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Button(Self.timestamp(segment.start)) { jump() }
          .buttonStyle(.plain)
          .font(Typography.labelSmall.monospacedDigit())
          .foregroundColor(SidebarColors.labelSecondary)

        Spacer()

        Button {
          _ = state.promoteCaptionToTextOverlay(captionId: segment.id)
        } label: {
          HStack(spacing: 2.5) {
            Image(systemName: "arrow.up.forward.square")
              .font(.system(size: 8.5, weight: .semibold))
            Text("Aa")
              .font(.system(size: 9, weight: .bold))
          }
          .foregroundColor(.accentColor)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.accentColor.opacity(0.11), in: Radius.rect(Radius.ornament))
        }
        .buttonStyle(.plain)
        .help(L10n.VideoEditor.captionsPromoteCueToText)
        .accessibilityLabel(L10n.VideoEditor.captionsPromoteCueToText)

        Button { state.deleteCaption(id: segment.id) } label: {
          Image(systemName: "xmark")
            .font(.system(size: 9, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundColor(SidebarColors.labelSecondary)
        .help(L10n.VideoEditor.captionsDelete)
      }

      TextField("", text: $draft, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .font(Typography.labelSmall)
        .lineLimit(1 ... 3)
        .focused($isFocused)
        .onSubmit {
          commit()
          isFocused = false
        }
        .onChange(of: isFocused) { focused in
          let token = "caption-row-\(segment.id.uuidString)"
          if focused {
            state.beginTextFieldEditing(token: token)
          } else {
            state.endTextFieldEditing(token: token)
            commit()
          }
        }
        .onDisappear {
          state.endTextFieldEditing(token: "caption-row-\(segment.id.uuidString)")
        }
    }
    .onAppear { draft = segment.text }
    .onChange(of: segment.text) { draft = $0 }
  }

  private func commit() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text != segment.text else { return }
    state.updateCaptionText(id: segment.id, text: text)
  }

  private func jump() {
    guard let placement = state.placements.first(where: {
      $0.clip.isPrimary && segment.start >= $0.clip.sourceStart && segment.start < $0.clip.sourceEnd
    }) else { return }
    let time = placement.sequenceTime(atSource: segment.start) + 0.001
    state.seek(to: CMTime(seconds: time, preferredTimescale: 600))
  }

  static func timestamp(_ seconds: TimeInterval) -> String {
    let tenths = Int((max(seconds, 0) * 10).rounded())
    return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
  }
}
