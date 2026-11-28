//
//  VideoEditorTextTimelineTrack.swift
//  Snapzy
//
//  Dedicated Text / Title Overlay timeline lane with draggable positioning,
//  independent left/right duration trim handles, magnetic snapping,
//  visible-range culling, and quick duplicate/delete actions.
//

import AppKit
import AVFoundation
import SwiftUI

struct VideoEditorTextTimelineTrack: View, Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.state === rhs.state
      && lhs.timelineWidth == rhs.timelineWidth
      && lhs.visibleRange == rhs.visibleRange
  }

  let state: VideoEditorState
  @StateObject private var observation: VideoEditorTimelineObservation
  let timelineWidth: CGFloat
  let visibleRange: ClosedRange<CGFloat>?

  static let trackHeight: CGFloat = 34
  private static let blockHeight: CGFloat = 28
  private static let coordinateSpace = "VideoEditorTextTrack"

  @State private var hoveredId: UUID?
  @State private var dragSession: DragSession?

  private enum DragKind: Equatable {
    case move
    case trimLeading
    case trimTrailing
  }

  private struct DragSession: Equatable {
    let overlayId: UUID
    let kind: DragKind
    let anchorX: CGFloat
    let anchorY: CGFloat
    let anchorStart: TimeInterval
    let anchorDuration: TimeInterval
    let anchorTrackIndex: Int
    let anchorOverlays: [VideoEditorTextOverlay]
  }

  init(
    state: VideoEditorState,
    timelineWidth: CGFloat,
    visibleRange: ClosedRange<CGFloat>? = nil
  ) {
    self.state = state
    _observation = StateObject(wrappedValue: VideoEditorTimelineObservation(state: state, surface: .text))
    self.timelineWidth = timelineWidth
    self.visibleRange = visibleRange
  }

  private var axisDuration: TimeInterval {
    max(0.0001, CMTimeGetSeconds(state.timelineDuration))
  }

  private var pixelsPerSecond: CGFloat {
    timelineWidth / CGFloat(axisDuration)
  }

  private func x(for time: TimeInterval) -> CGFloat {
    CGFloat(time / axisDuration) * timelineWidth
  }

  private var renderedOverlays: [VideoEditorTextOverlay] {
    guard let visibleRange else { return state.textOverlays }
    return state.textOverlays.filter { overlay in
      overlay.id == dragSession?.overlayId
        || overlay.id == state.selectedTextOverlayId
        || state.selectedTextOverlayIds.contains(overlay.id)
        || (x(for: overlay.endTime) >= visibleRange.lowerBound
          && x(for: overlay.startTime) <= visibleRange.upperBound)
    }
  }

  private var laneCount: Int {
    state.textLaneCount
  }

  var body: some View {
    let _ = observation.revision
    let totalH = TextTimelineLaneLayout.totalHeight(forLaneCount: laneCount)
    let lanePitch = Self.trackHeight + TextTimelineLaneLayout.laneSpacing

    ZStack(alignment: .topLeading) {
      // Background lane wells + subtle non-colliding top-right lane badges
      VStack(spacing: TextTimelineLaneLayout.laneSpacing) {
        ForEach(0 ..< laneCount, id: \.self) { laneIndex in
          ZStack(alignment: .trailing) {
            TimelineTrackLaneWell()
              .frame(height: Self.trackHeight)
              .contentShape(Rectangle())
              .gesture(emptyLaneScrubGesture)

            HStack(spacing: 4) {
              if laneIndex == 0, laneCount < TextTimelineLaneLayout.maxLanes {
                let nextTrackLabel = "T\(laneCount + 1)"
                Button {
                  state.addTextTrackLane()
                } label: {
                  Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.08), in: Circle())
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.VideoEditor.addTextTrackNumbered(nextTrackLabel))
                .help(L10n.VideoEditor.addTextTrackNumbered(nextTrackLabel))
              }

              Text("T\(laneIndex + 1)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .foregroundColor(.secondary.opacity(0.9))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: Radius.rect(Radius.ornament))
                .allowsHitTesting(false)
            }
            .padding(.trailing, 6)
          }
          .frame(width: timelineWidth, height: Self.trackHeight, alignment: .leading)
        }
      }

      // Single unified ForEach across all lanes so cross-lane vertical dragging (`T1 <-> T2`)
      // preserves view identity and NEVER cancels the active DragGesture mid-drag.
      ForEach(renderedOverlays) { overlay in
        let clampedLane = max(0, min(laneCount - 1, overlay.trackIndex))
        let laneTopY = CGFloat(clampedLane) * lanePitch + (Self.trackHeight - Self.blockHeight) / 2
        textOverlayBlock(overlay)
          .offset(y: laneTopY)
      }
    }
    .frame(width: timelineWidth, height: totalH, alignment: .topLeading)
    .coordinateSpace(name: Self.coordinateSpace)
    .onDisappear {
      if dragSession != nil {
        dragSession = nil
        state.timelineSnapGuide.clear()
      }
    }
  }

  @ViewBuilder
  private func textOverlayBlock(_ overlay: VideoEditorTextOverlay) -> some View {
    let isSelected = state.selectedTextOverlayId == overlay.id
      || state.selectedTextOverlayIds.contains(overlay.id)
    let isHovered = hoveredId == overlay.id
    let rawWidth = x(for: overlay.endTime) - x(for: overlay.startTime)
    let width = max(18, rawWidth - 2)
    let offsetX = x(for: overlay.startTime) + 1
    let accent = Color(red: 0.68, green: 0.42, blue: 0.98)

    ZStack(alignment: .leading) {
      Radius.rect(Radius.tile)
        .fill(overlay.isEnabled ? accent.opacity(isSelected ? 0.36 : 0.24) : Color.primary.opacity(0.08))

      if width > 34 {
        HStack(spacing: 4) {
          Image(systemName: "textformat")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(overlay.isEnabled ? .white.opacity(0.95) : .secondary)

          Text(overlay.text.isEmpty ? L10n.VideoEditor.defaultTitleText : overlay.text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(overlay.isEnabled ? .white.opacity(0.95) : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)

          Spacer(minLength: 0)

          if width > 86 {
            Text(String(format: "%.1fs", overlay.duration))
              .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
              .foregroundColor(.white.opacity(0.75))
              .padding(.trailing, isSelected ? 8 : 2)
          }
        }
        .padding(.leading, isSelected ? 10 : 6)
        .padding(.trailing, 6)
        .allowsHitTesting(false)
      }

      Radius.rect(Radius.tile)
        .strokeBorder(
          isSelected ? Color.white.opacity(0.95) : accent.opacity(0.6),
          lineWidth: isSelected ? 1.8 : 1.0
        )
        .allowsHitTesting(false)
    }
    .frame(width: width, height: Self.blockHeight)
    .clipShape(Radius.rect(Radius.tile))
    .contentShape(Rectangle())
    .overlay(alignment: .leading) {
      if isSelected || isHovered {
        trimHandle(for: overlay, isLeading: true)
      }
    }
    .overlay(alignment: .trailing) {
      if isSelected || isHovered {
        trimHandle(for: overlay, isLeading: false)
      }
    }
    .opacity(overlay.isEnabled ? 1.0 : 0.5)
    .offset(x: offsetX)
    .zIndex(isSelected ? 3 : (isHovered ? 2 : 1))
    .onHover { hovering in
      if hovering {
        hoveredId = overlay.id
      } else if hoveredId == overlay.id {
        hoveredId = nil
      }
    }
    .gesture(moveGesture(for: overlay))
    .contextMenu {
      Button {
        state.selectTextOverlay(id: overlay.id)
        state.leftSidebarPanel = .text
        state.isLeftSidebarVisible = true
      } label: {
        Label(L10n.VideoEditor.editTextOverlay, systemImage: "textformat")
      }

      Button {
        state.duplicateTextOverlay(id: overlay.id)
      } label: {
        Label(L10n.VideoEditor.duplicateTextOverlay, systemImage: "doc.on.doc")
      }

      Divider()

      Button(role: .destructive) {
        state.removeTextOverlay(id: overlay.id)
      } label: {
        Label(L10n.VideoEditor.deleteTextOverlay, systemImage: "trash")
      }
    }
    .accessibilityLabel(
      L10n.VideoEditor.textOverlayAccessibility(
        overlay.text.isEmpty ? L10n.VideoEditor.defaultTitleText : overlay.text
      )
    )
    .accessibilityIdentifier("video-editor.text-overlay-item.\(overlay.id.uuidString)")
  }

  private func trimHandle(for overlay: VideoEditorTextOverlay, isLeading: Bool) -> some View {
    Rectangle()
      .fill(Color.white.opacity(0.9))
      .frame(width: 5, height: Self.blockHeight)
      .clipShape(Radius.rect(Radius.ornament))
      .frame(width: 11, height: Self.blockHeight, alignment: isLeading ? .leading : .trailing)
      .contentShape(Rectangle())
      .onHover { hovering in
        if hovering {
          NSCursor.resizeLeftRight.set()
        } else if dragSession == nil {
          NSCursor.arrow.set()
        }
      }
      .highPriorityGesture(
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.coordinateSpace))
          .onChanged { value in
            if dragSession == nil {
              state.selectTextOverlay(id: overlay.id)
              dragSession = DragSession(
                overlayId: overlay.id,
                kind: isLeading ? .trimLeading : .trimTrailing,
                anchorX: value.location.x,
                anchorY: value.location.y,
                anchorStart: overlay.startTime,
                anchorDuration: overlay.duration,
                anchorTrackIndex: overlay.trackIndex,
                anchorOverlays: state.textOverlays
              )
            }
            guard let session = dragSession, session.overlayId == overlay.id, pixelsPerSecond > 0 else { return }
            let delta = TimeInterval((value.location.x - session.anchorX) / pixelsPerSecond)
            let bypassSnap = !state.isSnappingEnabled || VideoEditorTimelineSnapGuideState.isBypassKeyPressed
            let candidates = state.timelineSnapCandidates(excludingTextOverlayId: overlay.id)
            let anchorEnd = session.anchorStart + session.anchorDuration

            if isLeading {
              let rawStart = max(0, min(session.anchorStart + delta, anchorEnd - VideoEditorTextOverlay.minDuration))
              let snapped = VideoEditorTimelineSnapper.snap(
                time: rawStart,
                candidates: candidates,
                pixelsPerSecond: pixelsPerSecond,
                isDisabled: bypassSnap
              )
              state.timelineSnapGuide.update(snapped.target)
              let clampedStart = max(0, min(snapped.time, anchorEnd - VideoEditorTextOverlay.minDuration))
              state.updateTextOverlay(id: overlay.id, recordUndo: false) { item in
                item.startTime = clampedStart
                item.duration = max(VideoEditorTextOverlay.minDuration, anchorEnd - clampedStart)
              }
            } else {
              let rawEnd = max(
                session.anchorStart + VideoEditorTextOverlay.minDuration,
                min(axisDuration, anchorEnd + delta)
              )
              let snapped = VideoEditorTimelineSnapper.snap(
                time: rawEnd,
                candidates: candidates,
                pixelsPerSecond: pixelsPerSecond,
                isDisabled: bypassSnap
              )
              state.timelineSnapGuide.update(snapped.target)
              let clampedEnd = max(
                session.anchorStart + VideoEditorTextOverlay.minDuration,
                min(axisDuration, snapped.time)
              )
              state.updateTextOverlay(id: overlay.id, recordUndo: false) { item in
                item.duration = max(VideoEditorTextOverlay.minDuration, clampedEnd - session.anchorStart)
              }
            }
          }
          .onEnded { _ in
            if let prior = dragSession?.anchorOverlays {
              state.commitTextOverlayEdit(previous: prior)
            }
            dragSession = nil
            state.timelineSnapGuide.clear()
            NSCursor.arrow.set()
          }
      )
      .accessibilityLabel(isLeading ? L10n.VideoEditor.clipTrimStartHint : L10n.VideoEditor.clipTrimEndHint)
  }

  private func moveGesture(for overlay: VideoEditorTextOverlay) -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
      .onChanged { value in
        if dragSession == nil {
          state.selectTextOverlay(id: overlay.id)
          dragSession = DragSession(
            overlayId: overlay.id,
            kind: .move,
            anchorX: value.location.x,
            anchorY: value.location.y,
            anchorStart: overlay.startTime,
            anchorDuration: overlay.duration,
            anchorTrackIndex: overlay.trackIndex,
            anchorOverlays: state.textOverlays
          )
        }
        guard let session = dragSession,
              session.overlayId == overlay.id,
              session.kind == .move,
              pixelsPerSecond > 0,
              hypot(value.location.x - session.anchorX, value.location.y - session.anchorY) > 3
        else { return }

        let delta = TimeInterval((value.location.x - session.anchorX) / pixelsPerSecond)
        let maxStart = max(0, axisDuration - session.anchorDuration)
        let rawStart = max(0, min(maxStart, session.anchorStart + delta))
        let bypassSnap = !state.isSnappingEnabled || VideoEditorTimelineSnapGuideState.isBypassKeyPressed
        let snapped = VideoEditorTimelineSnapper.snapRange(
          start: rawStart,
          duration: session.anchorDuration,
          candidates: state.timelineSnapCandidates(excludingTextOverlayId: overlay.id),
          pixelsPerSecond: pixelsPerSecond,
          isDisabled: bypassSnap
        )
        state.timelineSnapGuide.update(snapped.target)
        let clampedStart = max(0, min(maxStart, snapped.start))

        let lanePitch = Self.trackHeight + TextTimelineLaneLayout.laneSpacing
        let laneDelta = Int(((value.location.y - session.anchorY) / lanePitch).rounded())
        let maxAllowedLane = min(TextTimelineLaneLayout.maxLanes - 1, max(laneCount - 1, session.anchorTrackIndex + 1))
        let targetLane = max(0, min(maxAllowedLane, session.anchorTrackIndex + laneDelta))

        state.updateTextOverlay(id: overlay.id, recordUndo: false) { item in
          item.startTime = clampedStart
          item.trackIndex = targetLane
        }
      }
      .onEnded { value in
        let prior = dragSession?.anchorOverlays
        let wasTap = dragSession.map {
          hypot(value.location.x - $0.anchorX, value.location.y - $0.anchorY) <= 3
        } ?? true
        dragSession = nil
        state.timelineSnapGuide.clear()

        if wasTap {
          state.selectTextOverlay(id: overlay.id)
          state.leftSidebarPanel = .text
          state.isLeftSidebarVisible = true
          let now = CMTimeGetSeconds(state.currentTime)
          if now < overlay.startTime || now >= overlay.endTime {
            state.seek(to: CMTime(seconds: overlay.startTime + min(0.2, overlay.duration / 2), preferredTimescale: 600))
          }
        } else if let prior {
          state.commitTextOverlayEdit(previous: prior)
        }
      }
  }

  private var emptyLaneScrubGesture: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
      .onChanged { value in
        guard pixelsPerSecond > 0 else { return }
        if !state.playbackState.isScrubbing {
          state.selectTextOverlay(id: nil)
          state.startScrubbing()
        }
        let seconds = max(0, TimeInterval(value.location.x / pixelsPerSecond))
        state.scrub(to: CMTime(seconds: seconds, preferredTimescale: 600))
      }
      .onEnded { value in
        guard pixelsPerSecond > 0 else { return }
        let seconds = max(0, TimeInterval(value.location.x / pixelsPerSecond))
        state.scrub(to: CMTime(seconds: seconds, preferredTimescale: 600))
        state.endScrubbing()
      }
  }
}
