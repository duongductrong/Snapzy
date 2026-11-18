//
//  VideoEditorCaptionTimelineTrack.swift
//  Snapzy
//
//  "Captions" timeline track: one block per caption piece on the structural axis
//  (a caption split by a cut shows as two blocks). Drag the body to move, an edge to
//  re-time, click to seek, double-click to edit the text. Captions live in source
//  time, which moves 1:1 with structural time inside a clip.
//

import AVFoundation
import SwiftUI

struct VideoEditorCaptionTimelineTrack: View, Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.state === rhs.state && lhs.timelineWidth == rhs.timelineWidth
  }

  let state: VideoEditorState
  let timelineWidth: CGFloat
  @StateObject private var observation: VideoEditorTimelineObservation
  @State private var selectedId: UUID?
  @State private var editingId: UUID?
  @State private var editText = ""
  @State private var drag: DragState?

  private let trackHeight: CGFloat = 40
  private let blockHeight: CGFloat = 28
  private let edgeWidth: CGFloat = 6

  private struct Piece: Identifiable {
    let id: String
    let segment: CaptionSegment
    let x: CGFloat
    let width: CGFloat
  }

  private struct DragState {
    enum Mode { case move, start, end }
    let id: UUID
    let mode: Mode
    let original: VideoEditorCaptions
  }

  init(state: VideoEditorState, timelineWidth: CGFloat) {
    self.state = state
    self.timelineWidth = timelineWidth
    _observation = StateObject(wrappedValue: VideoEditorTimelineObservation(state: state, surface: .captions))
  }

  var body: some View {
    let _ = observation.revision
    ZStack(alignment: .topLeading) {
      TimelineTrackLaneWell()
        .frame(height: trackHeight)
      HStack(spacing: 4) {
        Image(systemName: "captions.bubble").font(.system(size: 9))
        Text(L10n.VideoEditor.captionsSection).font(.system(size: 9, weight: .medium))
      }
      .foregroundColor(.secondary)
      .padding(.leading, 6)
      .frame(height: trackHeight)
      .allowsHitTesting(false)

      ForEach(pieces) { piece in
        block(piece)
      }
    }
    .frame(width: timelineWidth, height: trackHeight, alignment: .leading)
  }

  private var duration: TimeInterval { CMTimeGetSeconds(state.timelineDuration) }

  /// Caption pieces laid on primary clips of the structural timeline.
  private var pieces: [Piece] {
    let segments = Dictionary(uniqueKeysWithValues: state.captions.segments.map { ($0.id, $0) })
    return VideoEditorSourceTrackLayout.pieces(
      state.captions.segments.map { ($0.id, $0.start, $0.end) },
      placements: state.placements,
      duration: duration,
      width: timelineWidth
    ).compactMap { piece in
      segments[piece.rangeID].map { Piece(id: piece.id, segment: $0, x: piece.x, width: piece.width) }
    }
  }

  private func block(_ piece: Piece) -> some View {
    let isSelected = selectedId == piece.segment.id
    return ZStack(alignment: .leading) {
      TimelineSegmentChrome(
        height: blockHeight,
        baseColor: Color.teal.opacity(0.75),
        isSelected: isSelected,
        isDragging: drag?.id == piece.segment.id,
        borderColor: isSelected ? .white : .clear,
        cornerRadius: Radius.tile
      )
      Text(piece.segment.text)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(.white)
        .lineLimit(1)
        .padding(.horizontal, 6)
    }
    .frame(width: piece.width, height: blockHeight)
    .clipped()
    .contentShape(Rectangle())
    .offset(x: piece.x, y: (trackHeight - blockHeight) / 2)
    .gesture(dragGesture(piece))
    .simultaneousGesture(TapGesture(count: 2).onEnded { beginEditing(piece.segment) })
    .simultaneousGesture(TapGesture().onEnded {
      selectedId = piece.segment.id
      state.seek(to: CMTime(seconds: piece.x / timelineWidth * duration + 0.001, preferredTimescale: 600))
    })
    .popover(isPresented: Binding(
      get: { editingId == piece.segment.id },
      set: { if !$0 { endEditing() } }
    )) {
      TextField("", text: $editText, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(1 ... 4)
        .frame(width: 280)
        .padding(10)
        .onSubmit { endEditing() }
    }
  }

  private func dragGesture(_ piece: Piece) -> some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        if drag == nil {
          let local = value.startLocation.x
          let mode: DragState.Mode = local < edgeWidth ? .start : (local > piece.width - edgeWidth ? .end : .move)
          drag = DragState(id: piece.segment.id, mode: mode, original: state.captions)
          selectedId = piece.segment.id
        }
        guard let drag, let original = drag.original.segments.first(where: { $0.id == drag.id }) else { return }
        let delta = value.translation.width / timelineWidth * duration
        let range: ClosedRange<TimeInterval>
        switch drag.mode {
        case .move:
          let start = max(0, original.start + delta)
          range = start ... start + (original.end - original.start)
        case .start:
          range = min(original.start + delta, original.end - 0.2) ... original.end
        case .end:
          range = original.start ... max(original.end + delta, original.start + 0.2)
        }
        state.updateCaptionRange(id: drag.id, range: range, recordUndo: false)
      }
      .onEnded { _ in
        if let drag { state.commitCaptions(from: drag.original) }
        drag = nil
      }
  }

  private func beginEditing(_ segment: CaptionSegment) {
    selectedId = segment.id
    editText = segment.text
    editingId = segment.id
  }

  private func endEditing() {
    if let id = editingId {
      state.updateCaptionText(id: id, text: editText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    editingId = nil
  }
}
