//
//  VideoTrimHandlesView.swift
//  Snapzy
//
//  Draggable trim handles for adjusting video start/end points
//

import AVFoundation
import SwiftUI

/// Overlay view with draggable trim handles at start and end
struct VideoTrimHandlesView: View {
  @ObservedObject var state: VideoEditorState
  let timelineWidth: CGFloat

  @State private var isDraggingStart = false
  @State private var isDraggingEnd = false
  @State private var startDragPlayheadTime: CMTime?
  @State private var endDragPlayheadTime: CMTime?

  private let handleWidth: CGFloat = 14
  private let handleHeight: CGFloat = 60
  private let playheadSnapThreshold: CGFloat = 10

  var body: some View {
    ZStack(alignment: .leading) {
      // Dimmed region before trim start
      Rectangle()
        .fill(Color.black.opacity(0.5))
        .frame(width: startHandleOffset)

      // Dimmed region after trim end
      Rectangle()
        .fill(Color.black.opacity(0.5))
        .frame(width: timelineWidth - endHandleOffset)
        .offset(x: endHandleOffset)

      // Yellow rounded border between trim handles
      let leftEdge = max(0, min(startHandleOffset - handleWidth / 2, timelineWidth - handleWidth))
      let rightEdge = max(0, min(endHandleOffset - handleWidth / 2, timelineWidth - handleWidth)) + handleWidth
      let borderWidth = max(0, rightEdge - leftEdge)

      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(Color.yellow, lineWidth: 3)
        .frame(width: borderWidth, height: handleHeight)
        .offset(x: leftEdge)
        .allowsHitTesting(false)

      // Start handle — clamped so it stays fully visible within timeline
      TrimHandle(isStart: true, isDragging: isDraggingStart)
        .offset(x: max(0, min(startHandleOffset - handleWidth / 2, timelineWidth - handleWidth)))
        .gesture(startHandleGesture)

      // End handle — clamped so it stays fully visible within timeline
      TrimHandle(isStart: false, isDragging: isDraggingEnd)
        .offset(x: max(0, min(endHandleOffset - handleWidth / 2, timelineWidth - handleWidth)))
        .gesture(endHandleGesture)
    }
    .frame(height: handleHeight)
  }

  // MARK: - Computed Properties

  private var startHandleOffset: CGFloat {
    guard CMTimeGetSeconds(state.duration) > 0 else { return 0 }
    let progress = CMTimeGetSeconds(state.trimStart) / CMTimeGetSeconds(state.duration)
    return CGFloat(progress) * timelineWidth
  }

  private var endHandleOffset: CGFloat {
    guard CMTimeGetSeconds(state.duration) > 0 else { return timelineWidth }
    let progress = CMTimeGetSeconds(state.trimEnd) / CMTimeGetSeconds(state.duration)
    return CGFloat(progress) * timelineWidth
  }

  // MARK: - Gestures

  private var startHandleGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        if !isDraggingStart {
          startDragPlayheadTime = state.currentTime
        }
        isDraggingStart = true
        let newOffset = snappedTimelineOffset(
          clampedTimelineOffset(value.location.x),
          to: startDragPlayheadTime
        )
        let newTime = time(atTimelineOffset: newOffset)
        state.setTrimStart(newTime)
      }
      .onEnded { _ in
        isDraggingStart = false
        startDragPlayheadTime = nil
      }
  }

  private var endHandleGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        if !isDraggingEnd {
          endDragPlayheadTime = state.currentTime
        }
        isDraggingEnd = true
        let newOffset = snappedTimelineOffset(
          clampedTimelineOffset(value.location.x),
          to: endDragPlayheadTime
        )
        let newTime = time(atTimelineOffset: newOffset)
        state.setTrimEnd(newTime)
      }
      .onEnded { _ in
        isDraggingEnd = false
        endDragPlayheadTime = nil
      }
  }

  private func clampedTimelineOffset(_ offset: CGFloat) -> CGFloat {
    max(0, min(offset, timelineWidth))
  }

  private func snappedTimelineOffset(_ offset: CGFloat, to snapTime: CMTime?) -> CGFloat {
    guard let snapTime else { return offset }

    let durationSeconds = CMTimeGetSeconds(state.duration)
    let snapSeconds = CMTimeGetSeconds(snapTime)
    guard timelineWidth > 0,
          durationSeconds > 0,
          durationSeconds.isFinite,
          snapSeconds.isFinite
    else {
      return offset
    }

    let snapProgress = max(0, min(snapSeconds / durationSeconds, 1))
    let snapOffset = CGFloat(snapProgress) * timelineWidth
    guard abs(offset - snapOffset) <= playheadSnapThreshold else { return offset }
    return snapOffset
  }

  private func time(atTimelineOffset offset: CGFloat) -> CMTime {
    let durationSeconds = CMTimeGetSeconds(state.duration)
    guard timelineWidth > 0,
          durationSeconds > 0,
          durationSeconds.isFinite
    else {
      return .zero
    }

    let progress = clampedTimelineOffset(offset) / timelineWidth
    return CMTime(
      seconds: progress * durationSeconds,
      preferredTimescale: 600
    )
  }
}

// MARK: - Trim Handle

/// Individual trim handle appearance
private struct TrimHandle: View {
  let isStart: Bool
  let isDragging: Bool

  var body: some View {
    RoundedRectangle(cornerRadius: 3)
      .fill(isDragging ? Color.white : Color.yellow)
      .frame(width: 14, height: 60)
      .overlay(
        Image(systemName: isStart ? "chevron.compact.left" : "chevron.compact.right")
          .font(.system(size: 16, weight: .bold))
          .foregroundColor(.black.opacity(0.5))
      )
      .contentShape(Rectangle().inset(by: -10))
  }
}
