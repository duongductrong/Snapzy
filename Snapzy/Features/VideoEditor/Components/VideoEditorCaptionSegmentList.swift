//
//  VideoEditorCaptionSegmentList.swift
//  Snapzy
//
//  Editable caption list for the captions panel: start time (click to jump there),
//  text field (commits on Return or when focus leaves, one undo step), delete.
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
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Button(Self.timestamp(segment.start)) { jump() }
          .buttonStyle(.plain)
          .font(Typography.labelSmall.monospacedDigit())
          .foregroundColor(SidebarColors.labelSecondary)
        Spacer()
        Button { state.deleteCaption(id: segment.id) } label: {
          Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
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
        .onSubmit(commit)
        .onChange(of: isFocused) { focused in
          if !focused { commit() }
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

  /// Jumps the playhead to the caption's first visible frame on the timeline.
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
