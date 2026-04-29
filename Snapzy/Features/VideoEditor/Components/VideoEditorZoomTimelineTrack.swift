//
//  ZoomTimelineTrack.swift
//  Snapzy
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
  private let handleWidth: CGFloat = 8
  private let minVisualBlockWidth: CGFloat = 64
  private let dragModelUpdateInterval: TimeInterval = 1.0 / 30.0

  // MARK: - Drag State (Track-Level)

  @State private var dragMode: DragMode = .none
  @State private var dragSegmentId: UUID?
  @State private var dragInitialStartTime: TimeInterval = 0
  @State private var dragInitialEndTime: TimeInterval = 0
  @State private var dragPreviewSegment: ZoomSegment?
  @State private var lastDragModelUpdateTime: TimeInterval = 0

  // MARK: - Hover State (Placeholder Preview)

  @State private var isHovering: Bool = false
  @State private var hoverLocation: CGPoint = .zero

  private enum DragMode {
    case none
    case position    // Dragging entire segment
    case startEdge   // Dragging left edge
    case endEdge     // Dragging right edge
  }

  private struct SegmentLayout {
    let visualStartX: CGFloat
    let visualEndX: CGFloat
    let visualWidth: CGFloat

    var centerX: CGFloat {
      visualStartX + (visualWidth / 2)
    }
  }

  // MARK: - Computed Properties

  private var videoDuration: TimeInterval {
    CMTimeGetSeconds(state.duration)
  }

  private var pixelsPerSecond: CGFloat {
    guard videoDuration > 0 else { return 1 }
    return timelineWidth / videoDuration
  }

  // MARK: - Hover Computed Properties

  private var hoverTime: TimeInterval {
    guard videoDuration > 0 else { return 0 }
    return (hoverLocation.x / timelineWidth) * videoDuration
  }

  private var isHoveringOverSegment: Bool {
    interactionSegment(atX: hoverLocation.x) != nil
  }

  private var shouldShowPlaceholder: Bool {
    isHovering && !isHoveringOverSegment && dragMode == .none
  }

  private var placeholderWidth: CGFloat {
    guard videoDuration > 0 else { return minVisualBlockWidth }
    let logicalWidth = (ZoomSegment.defaultDuration / videoDuration) * timelineWidth
    return min(timelineWidth, max(minVisualBlockWidth, logicalWidth))
  }

  private var placeholderX: CGFloat {
    // Center placeholder on mouse position
    let centeredX = hoverLocation.x - (placeholderWidth / 2)
    // Clamp to track bounds
    return max(0, min(centeredX, timelineWidth - placeholderWidth))
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
        Text(L10n.VideoEditor.zooms)
          .font(.system(size: 9, weight: .medium))
          .foregroundColor(.secondary)
        Spacer()
      }
      .padding(.leading, 6)
      .allowsHitTesting(false)

      // Zoom blocks (visual only - gestures handled at track level)
      ForEach(state.zoomSegments) { segment in
        let displaySegment = dragPreviewSegment?.id == segment.id ? dragPreviewSegment ?? segment : segment
        let segmentLayout = layout(for: displaySegment)
        ZoomBlockVisual(
          segment: displaySegment,
          isSelected: state.selectedZoomId == segment.id,
          isDragging: dragSegmentId == segment.id,
          blockX: segmentLayout.visualStartX,
          blockWidth: segmentLayout.visualWidth
        )
      }

      // Placeholder preview for adding new zoom
      if shouldShowPlaceholder {
        ZoomPlaceholderView(
          width: placeholderWidth,
          xPosition: placeholderX
        )
      }
    }
    .frame(height: trackHeight)
    .contentShape(Rectangle())
    .gesture(unifiedDragGesture)
    .onTapGesture(count: 2) { location in
      handleDoubleTap(at: location)
    }
    .onTapGesture { location in
      handleTap(at: location)
    }
    .onContinuousHover { phase in
      switch phase {
      case .active(let location):
        isHovering = true
        hoverLocation = location
      case .ended:
        isHovering = false
      }
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
    guard let (segment, segmentLayout) = interactionSegment(atX: location.x) else {
      dragMode = .none
      return
    }

    // Determine drag mode based on tap position within block
    let leftHandleEnd = segmentLayout.visualStartX + handleWidth
    let rightHandleStart = segmentLayout.visualEndX - handleWidth

    dragSegmentId = segment.id
    dragInitialStartTime = segment.startTime
    dragInitialEndTime = segment.endTime
    dragPreviewSegment = segment
    lastDragModelUpdateTime = 0

    if location.x <= leftHandleEnd {
      dragMode = .startEdge
    } else if location.x >= rightHandleStart {
      dragMode = .endEdge
    } else {
      dragMode = .position
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
    let previewSegment = previewSegment(from: segment, deltaSeconds: deltaSeconds)
    dragPreviewSegment = previewSegment
    commitDragPreviewIfNeeded(previewSegment)
  }

  private func previewSegment(from segment: ZoomSegment, deltaSeconds: TimeInterval) -> ZoomSegment {
    var preview = segment
    let initialDuration = dragInitialEndTime - dragInitialStartTime

    switch dragMode {
    case .none:
      return preview

    case .position:
      let newStart = dragInitialStartTime + deltaSeconds
      let maxStart = max(0, videoDuration - initialDuration)
      let clampedStart = max(0, min(newStart, maxStart))
      preview.startTime = clampedStart
      preview.duration = initialDuration

    case .startEdge:
      let newStart = dragInitialStartTime + deltaSeconds
      let clampedStart = max(0, min(newStart, dragInitialEndTime - ZoomSegment.minDuration))
      let newDuration = dragInitialEndTime - clampedStart
      preview.startTime = clampedStart
      preview.duration = max(ZoomSegment.minDuration, newDuration)

    case .endEdge:
      let newEnd = dragInitialEndTime + deltaSeconds
      let clampedEnd = max(dragInitialStartTime + ZoomSegment.minDuration, min(newEnd, videoDuration))
      let newDuration = clampedEnd - dragInitialStartTime
      preview.startTime = dragInitialStartTime
      preview.duration = max(ZoomSegment.minDuration, newDuration)
    }

    return preview
  }

  private func commitDragPreviewIfNeeded(_ segment: ZoomSegment, force: Bool = false) {
    let now = ProcessInfo.processInfo.systemUptime
    guard force || now - lastDragModelUpdateTime >= dragModelUpdateInterval else { return }

    state.updateZoom(
      id: segment.id,
      startTime: segment.startTime,
      duration: segment.duration
    )
    lastDragModelUpdateTime = now
  }

  private func endDrag() {
    if let dragPreviewSegment {
      commitDragPreviewIfNeeded(dragPreviewSegment, force: true)
    }

    dragMode = .none
    dragSegmentId = nil
    dragPreviewSegment = nil
    lastDragModelUpdateTime = 0
  }

  // MARK: - Tap Handling

  private func handleTap(at location: CGPoint) {
    let tappedTime = (location.x / timelineWidth) * videoDuration

    if let (segment, _) = interactionSegment(atX: location.x) {
      // Tapped on existing segment - select it
      state.selectZoom(id: segment.id)
    } else {
      // Tapped on empty area - add new zoom centered at tap position
      state.addZoom(at: tappedTime)
    }
  }

  private func handleDoubleTap(at location: CGPoint) {
    guard let (segment, _) = interactionSegment(atX: location.x) else { return }
    state.openZoomConfiguration(id: segment.id)
  }

  // MARK: - Context Menu

  @ViewBuilder
  private var trackContextMenu: some View {
    Button {
      // Add at hover position if hovering, otherwise at playhead
      let addTime = isHovering ? hoverTime : CMTimeGetSeconds(state.currentTime)
      state.addZoom(at: addTime)
    } label: {
      Label(
        isHovering ? L10n.VideoEditor.addZoomHere : L10n.VideoEditor.addZoomAtPlayhead,
        systemImage: "plus.magnifyingglass"
      )
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
            segment.isEnabled ? L10n.VideoEditor.disableZoom : L10n.VideoEditor.enableZoom,
            systemImage: segment.isEnabled ? "eye.slash" : "eye"
          )
        }
      }

      Button(role: .destructive) {
        if let id = state.selectedZoomId {
          state.removeZoom(id: id)
        }
      } label: {
        Label(L10n.VideoEditor.deleteZoom, systemImage: "trash")
      }
    }

    if !state.zoomSegments.isEmpty {
      Divider()

      Button(role: .destructive) {
        state.zoomSegments.removeAll()
        state.selectedZoomId = nil
      } label: {
        Label(L10n.VideoEditor.removeAllZooms, systemImage: "trash.fill")
      }
    }
  }

  private func addZoomAtPlayhead() {
    let currentTime = CMTimeGetSeconds(state.currentTime)
    state.addZoom(at: currentTime)
  }

  private func layout(for segment: ZoomSegment) -> SegmentLayout {
    guard videoDuration > 0, timelineWidth > 0 else {
      return SegmentLayout(
        visualStartX: 0,
        visualEndX: minVisualBlockWidth,
        visualWidth: minVisualBlockWidth
      )
    }

    let logicalStartX = (segment.startTime / videoDuration) * timelineWidth
    let logicalWidth = (segment.duration / videoDuration) * timelineWidth
    let visualWidth = min(timelineWidth, max(minVisualBlockWidth, logicalWidth))
    let maxStartX = max(0, timelineWidth - visualWidth)
    let visualStartX = max(0, min(logicalStartX, maxStartX))

    return SegmentLayout(
      visualStartX: visualStartX,
      visualEndX: visualStartX + visualWidth,
      visualWidth: visualWidth
    )
  }

  private func interactionSegment(atX x: CGFloat) -> (segment: ZoomSegment, layout: SegmentLayout)? {
    let containing = state.zoomSegments.compactMap { segment -> (segment: ZoomSegment, layout: SegmentLayout)? in
      let segmentLayout = layout(for: segment)
      guard x >= segmentLayout.visualStartX && x <= segmentLayout.visualEndX else {
        return nil
      }
      return (segment: segment, layout: segmentLayout)
    }

    guard !containing.isEmpty else { return nil }

    if let selectedId = state.selectedZoomId,
       let selected = containing.first(where: { $0.segment.id == selectedId }) {
      return selected
    }

    return containing.sorted { lhs, rhs in
      let leftDistance = abs(lhs.layout.centerX - x)
      let rightDistance = abs(rhs.layout.centerX - x)
      if leftDistance != rightDistance {
        return leftDistance < rightDistance
      }

      let leftIndex = state.zoomSegments.firstIndex(where: { $0.id == lhs.segment.id }) ?? -1
      let rightIndex = state.zoomSegments.firstIndex(where: { $0.id == rhs.segment.id }) ?? -1
      return leftIndex > rightIndex
    }.first
  }
}

// MARK: - Zoom Block Visual (No Gestures)

/// Visual-only zoom block - all interactions handled by parent track
private struct ZoomBlockVisual: View {
  let segment: ZoomSegment
  let isSelected: Bool
  let isDragging: Bool
  let blockX: CGFloat
  let blockWidth: CGFloat

  private let handleWidth: CGFloat = 8

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

        if blockWidth >= 48 {
          Text(segment.formattedZoomLevel)
            .font(.system(size: 10, weight: .semibold))
        }

        Spacer(minLength: 0)

        if blockWidth >= 96 {
          Text(segment.zoomType.displayName)
            .font(.system(size: 8, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.2))
            .cornerRadius(3)
        }
      }
      .padding(.horizontal, blockWidth < 48 ? handleWidth + 2 : handleWidth + 4)
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

// MARK: - Zoom Placeholder View

/// Ghost placeholder showing where new zoom will be added on click
private struct ZoomPlaceholderView: View {
  let width: CGFloat
  let xPosition: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: 6)
      .fill(ZoomColors.primary.opacity(0.2))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(
            ZoomColors.primary.opacity(0.5),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
          )
      )
      .overlay(
        HStack(spacing: 4) {
          Image(systemName: "plus.magnifyingglass")
            .font(.system(size: 10, weight: .medium))
          Text(L10n.VideoEditor.clickToAdd)
            .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(ZoomColors.primary.opacity(0.8))
      )
      .frame(width: width, height: 28)
      .offset(x: xPosition)
      .allowsHitTesting(false)
      .transition(.opacity.animation(.easeOut(duration: 0.15)))
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
