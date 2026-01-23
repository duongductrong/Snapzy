//
//  ZoomTimelineTrack.swift
//  ClaudeShot
//
//  Timeline track displaying zoom segments with interactive blocks
//

import AVFoundation
import SwiftUI

/// Timeline track for zoom segments - all gestures handled at track level
struct ZoomTimelineTrack: View {
  @ObservedObject var state: VideoEditorState
  let timelineWidth: CGFloat

  private let trackHeight: CGFloat = 32
  private let handleWidth: CGFloat = 10

  // MARK: - Drag State (Track-Level)

  @State private var dragMode: DragMode = .none
  @State private var dragSegmentId: UUID?
  @State private var dragInitialStartTime: TimeInterval = 0
  @State private var dragInitialEndTime: TimeInterval = 0

  private enum DragMode {
    case none
    case position    // Dragging entire segment
    case startEdge   // Dragging left edge
    case endEdge     // Dragging right edge
  }

  // MARK: - Computed Properties

  private var videoDuration: TimeInterval {
    CMTimeGetSeconds(state.duration)
  }

  private var pixelsPerSecond: CGFloat {
    guard videoDuration > 0 else { return 1 }
    return timelineWidth / videoDuration
  }

  // MARK: - Body

  var body: some View {
    ZStack(alignment: .leading) {
      // Track background
      RoundedRectangle(cornerRadius: 4)
        .fill(Color.black.opacity(0.15))
        .frame(height: trackHeight)

      // Track label
      HStack {
        Image(systemName: "plus.magnifyingglass")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
        Text("Zooms")
          .font(.system(size: 9, weight: .medium))
          .foregroundColor(.secondary)
        Spacer()
      }
      .padding(.leading, 6)
      .allowsHitTesting(false)

      // Zoom blocks (visual only - gestures handled at track level)
      ForEach(state.zoomSegments) { segment in
        ZoomBlockVisual(
          segment: segment,
          isSelected: state.selectedZoomId == segment.id,
          isDragging: dragSegmentId == segment.id,
          timelineWidth: timelineWidth,
          videoDuration: videoDuration
        )
      }
    }
    .frame(height: trackHeight)
    .contentShape(Rectangle())
    .gesture(unifiedDragGesture)
    .onTapGesture { location in
      handleTap(at: location)
    }
    .contextMenu {
      trackContextMenu
    }
  }

  // MARK: - Unified Drag Gesture

  private var unifiedDragGesture: some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        if dragMode == .none {
          // Determine what we're dragging based on start location
          beginDrag(at: value.startLocation)
        }
        continueDrag(translation: value.translation)
      }
      .onEnded { _ in
        endDrag()
      }
  }

  private func beginDrag(at location: CGPoint) {
    let tappedTime = (location.x / timelineWidth) * videoDuration

    // Find segment at tap location
    guard let segment = state.activeZoomSegment(at: tappedTime) else {
      dragMode = .none
      return
    }

    // Calculate block bounds
    let blockStartX = (segment.startTime / videoDuration) * timelineWidth
    let blockEndX = (segment.endTime / videoDuration) * timelineWidth

    // Determine drag mode based on tap position within block
    let leftHandleEnd = blockStartX + handleWidth
    let rightHandleStart = blockEndX - handleWidth

    dragSegmentId = segment.id
    dragInitialStartTime = segment.startTime
    dragInitialEndTime = segment.endTime

    if location.x <= leftHandleEnd {
      dragMode = .startEdge
      print("🎯 [Drag] Begin START EDGE drag for segment: \(segment.id)")
    } else if location.x >= rightHandleStart {
      dragMode = .endEdge
      print("🎯 [Drag] Begin END EDGE drag for segment: \(segment.id)")
    } else {
      dragMode = .position
      print("🎯 [Drag] Begin POSITION drag for segment: \(segment.id)")
    }

    // Select the segment being dragged
    state.selectZoom(id: segment.id)
  }

  private func continueDrag(translation: CGSize) {
    guard let segmentId = dragSegmentId,
          let segment = state.zoomSegments.first(where: { $0.id == segmentId }) else {
      return
    }

    let deltaSeconds = translation.width / pixelsPerSecond

    switch dragMode {
    case .none:
      break

    case .position:
      let newStart = dragInitialStartTime + deltaSeconds
      let maxStart = videoDuration - segment.duration
      let clampedStart = max(0, min(newStart, maxStart))
      print("🎯 [Drag] Position: delta=\(deltaSeconds)s, newStart=\(clampedStart)s")
      state.updateZoom(id: segmentId, startTime: clampedStart)

    case .startEdge:
      let newStart = dragInitialStartTime + deltaSeconds
      let clampedStart = max(0, min(newStart, dragInitialEndTime - ZoomSegment.minDuration))
      let newDuration = dragInitialEndTime - clampedStart
      print("🎯 [Drag] Start edge: newStart=\(clampedStart)s, newDuration=\(newDuration)s")
      state.updateZoom(id: segmentId, startTime: clampedStart, duration: max(ZoomSegment.minDuration, newDuration))

    case .endEdge:
      let newEnd = dragInitialEndTime + deltaSeconds
      let clampedEnd = max(dragInitialStartTime + ZoomSegment.minDuration, min(newEnd, videoDuration))
      let newDuration = clampedEnd - dragInitialStartTime
      print("🎯 [Drag] End edge: newEnd=\(clampedEnd)s, newDuration=\(newDuration)s")
      state.updateZoom(id: segmentId, duration: max(ZoomSegment.minDuration, newDuration))
    }
  }

  private func endDrag() {
    print("🎯 [Drag] End drag - mode was: \(dragMode)")
    dragMode = .none
    dragSegmentId = nil
  }

  // MARK: - Tap Handling

  private func handleTap(at location: CGPoint) {
    let tappedTime = (location.x / timelineWidth) * videoDuration
    print("🎯 [Tap] location: \(location), time: \(tappedTime)s")

    if let segment = state.activeZoomSegment(at: tappedTime) {
      print("🎯 [Tap] Selected segment: \(segment.id)")
      state.selectZoom(id: segment.id)
    } else {
      print("🎯 [Tap] Deselecting (empty area)")
      state.selectZoom(id: nil)
    }
  }

  // MARK: - Context Menu

  @ViewBuilder
  private var trackContextMenu: some View {
    Button {
      addZoomAtPlayhead()
    } label: {
      Label("Add Zoom at Playhead", systemImage: "plus.magnifyingglass")
    }

    if state.selectedZoomId != nil {
      Divider()

      Button {
        if let id = state.selectedZoomId {
          state.toggleZoomEnabled(id: id)
        }
      } label: {
        if let segment = state.selectedZoomSegment {
          Label(
            segment.isEnabled ? "Disable Zoom" : "Enable Zoom",
            systemImage: segment.isEnabled ? "eye.slash" : "eye"
          )
        }
      }

      Button(role: .destructive) {
        if let id = state.selectedZoomId {
          state.removeZoom(id: id)
        }
      } label: {
        Label("Delete Zoom", systemImage: "trash")
      }
    }

    if !state.zoomSegments.isEmpty {
      Divider()

      Button(role: .destructive) {
        state.zoomSegments.removeAll()
        state.selectedZoomId = nil
      } label: {
        Label("Remove All Zooms", systemImage: "trash.fill")
      }
    }
  }

  private func addZoomAtPlayhead() {
    let currentTime = CMTimeGetSeconds(state.currentTime)
    state.addZoom(at: currentTime)
  }
}

// MARK: - Zoom Block Visual (No Gestures)

/// Visual-only zoom block - all interactions handled by parent track
private struct ZoomBlockVisual: View {
  let segment: ZoomSegment
  let isSelected: Bool
  let isDragging: Bool
  let timelineWidth: CGFloat
  let videoDuration: TimeInterval

  private let handleWidth: CGFloat = 10
  private let minBlockWidth: CGFloat = 24

  private var blockX: CGFloat {
    guard videoDuration > 0 else { return 0 }
    return (segment.startTime / videoDuration) * timelineWidth
  }

  private var blockWidth: CGFloat {
    guard videoDuration > 0 else { return minBlockWidth }
    let width = (segment.duration / videoDuration) * timelineWidth
    return max(minBlockWidth, width)
  }

  var body: some View {
    ZStack(alignment: .leading) {
      // Main block background
      RoundedRectangle(cornerRadius: 6)
        .fill(blockFillColor)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2)
        )
        .shadow(color: isSelected ? ZoomColors.primary.opacity(0.4) : .clear, radius: 4, y: 2)

      // Content
      HStack(spacing: 4) {
        Image(systemName: "plus.magnifyingglass")
          .font(.system(size: 10, weight: .semibold))

        Text(segment.formattedZoomLevel)
          .font(.system(size: 10, weight: .semibold))

        Spacer(minLength: 0)

        if blockWidth > 80 {
          Text(segment.zoomType.displayName)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.2))
            .cornerRadius(3)
        }
      }
      .padding(.horizontal, handleWidth + 4)
      .foregroundColor(.white)

      // Left handle indicator
      handleIndicator()
        .offset(x: 0)

      // Right handle indicator
      handleIndicator()
        .offset(x: blockWidth - handleWidth)
    }
    .frame(width: blockWidth, height: 28)
    .offset(x: blockX)
    .opacity(segment.isEnabled ? 1.0 : 0.5)
    .scaleEffect(isDragging ? 1.02 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isDragging)
    .allowsHitTesting(false) // Parent handles all gestures
  }

  private func handleIndicator() -> some View {
    ZStack {
      Rectangle()
        .fill(isSelected ? Color.white.opacity(0.2) : Color.clear)

      RoundedRectangle(cornerRadius: 1)
        .fill(isSelected ? Color.white.opacity(0.8) : Color.white.opacity(0.4))
        .frame(width: 3, height: 14)
    }
    .frame(width: handleWidth, height: 28)
  }

  private var blockFillColor: Color {
    if !segment.isEnabled {
      return ZoomColors.disabled
    }
    if isDragging {
      return ZoomColors.primaryDark
    }
    return ZoomColors.primary
  }
}

// MARK: - Preview

#Preview {
  ZoomTimelineTrack(
    state: {
      let state = VideoEditorState(url: URL(fileURLWithPath: "/tmp/test.mov"))
      return state
    }(),
    timelineWidth: 400
  )
  .padding()
  .background(Color(NSColor.windowBackgroundColor))
}
