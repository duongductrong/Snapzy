//
//  VideoEditorZoomTimelineTrack.swift
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

  private let trackHeight: CGFloat = 40
  private let blockHeight: CGFloat = 32
  private let handleWidth: CGFloat = 8
  private let minVisualBlockWidth: CGFloat = 64
  private let dragModelUpdateInterval: TimeInterval = 1.0 / 30.0

  // MARK: - Drag State (Track-Level)

  @State private var dragMode: DragMode = .none
  @State private var dragSegmentId: UUID?
  @State private var dragInitialStartTime: TimeInterval = 0
  @State private var dragInitialEndTime: TimeInterval = 0
  /// Grab offset on the independent structural effect track, captured at drag begin.
  /// Keeping this in one coordinate system prevents seam/reorder jumps.
  @State private var dragGrabTimelineOffset: TimeInterval = 0
  @State private var dragPreviewSegment: ZoomSegment?
  @State private var lastDragModelUpdateTime: TimeInterval = 0

  // MARK: - Hover State (Placeholder Preview)

  @State private var isHovering: Bool = false
  @State private var hoverLocation: CGPoint = .zero
  @State private var activeCursor: NSCursor?

  private enum DragMode {
    case none
    case position // Dragging entire segment
    case startEdge // Dragging left edge
    case endEdge // Dragging right edge
  }

  private enum SegmentEdge {
    case start
    case end
  }

  private struct HoverState {
    let segmentId: UUID?
    let edge: SegmentEdge?

    static let none = HoverState(segmentId: nil, edge: nil)
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

  /// The track's drawing axis: sequence time, matching the ruler and playhead.
  private var videoDuration: TimeInterval {
    CMTimeGetSeconds(state.timelineDuration)
  }

  /// Structural timeline time under a pointer x. The effect track uses this same
  /// coordinate for drawing, hit testing, and mutation.
  private func sequenceTime(atX x: CGFloat) -> TimeInterval? {
    guard videoDuration > 0, timelineWidth > 0 else { return nil }
    return (x / timelineWidth) * videoDuration
  }

  // MARK: - Hover Computed Properties

  private var hoverSequenceTime: TimeInterval? {
    sequenceTime(atX: hoverLocation.x)
  }

  private var hoverState: HoverState {
    guard isHovering, dragMode == .none,
          let (segment, segmentLayout) = interactionSegment(atX: hoverLocation.x)
    else { return .none }

    let isOnStartEdge = hoverLocation.x <= segmentLayout.visualStartX + handleWidth
    let isOnEndEdge = hoverLocation.x >= segmentLayout.visualEndX - handleWidth
    let edge: SegmentEdge? = isOnStartEdge ? .start : (isOnEndEdge ? .end : nil)
    return HoverState(segmentId: segment.id, edge: edge)
  }

  private var isHoveringOverSegment: Bool {
    interactionSegment(atX: hoverLocation.x) != nil
  }

  private var shouldShowPlaceholder: Bool {
    guard isHovering, dragMode == .none, !isHoveringOverSegment,
          let hoverSequence = hoverSequenceTime
    else { return false }
    // Do not offer a block over an inactive trim slot, but inserted video is a valid
    // host because effects are independent from clip identity.
    return state.isPlayableMaterial(atSequence: hoverSequence)
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
    let hover = hoverState

    ZStack(alignment: .leading) {
      // Track background (recessed lane)
      TimelineTrackLaneWell()
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

      // Zoom blocks (visual only - gestures handled at track level).
      // Blocks stay on the structural effect track. Playback/export later projects
      // their ranges over active clip material and collapses trim gaps.
      ForEach(visibleSegments) { segment in
        let displaySegment = dragPreviewSegment?.id == segment.id ? dragPreviewSegment ?? segment : segment
        if let span = displaySpan(for: displaySegment) {
          let paddedLayout = paddedLayout(for: span)
          ZoomBlockVisual(
            segment: displaySegment,
            isSelected: state.selectedZoomId == segment.id,
            isDragging: dragSegmentId == segment.id,
            isHovered: hover.segmentId == segment.id,
            isEdgeHovered: hover.segmentId == segment.id && hover.edge != nil,
            blockX: paddedLayout.visualStartX,
            blockWidth: paddedLayout.visualWidth
          )
        }
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
    .clipShape(Radius.rect(Radius.tile))
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
        updateCursor(at: location)
      case .ended:
        isHovering = false
        clearCursor()
      }
    }
    .contextMenu {
      trackContextMenu
    }
  }

  // MARK: - Cursor

  private func updateCursor(at location: CGPoint) {
    guard dragMode == .none else { return }

    if let (_, segmentLayout) = interactionSegment(atX: location.x) {
      let isOnEdge =
        location.x <= segmentLayout.visualStartX + handleWidth
          || location.x >= segmentLayout.visualEndX - handleWidth
      setCursor(isOnEdge ? .resizeLeftRight : .pointingHand)
    } else {
      setCursor(.crosshair)
    }
  }

  private func setCursor(_ cursor: NSCursor) {
    guard activeCursor !== cursor else { return }
    activeCursor?.pop()
    cursor.push()
    activeCursor = cursor
  }

  private func clearCursor() {
    guard let activeCursor else { return }
    activeCursor.pop()
    self.activeCursor = nil
  }

  // MARK: - Unified Drag Gesture

  private var unifiedDragGesture: some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        if dragMode == .none {
          // Determine what we're dragging based on start location
          beginDrag(at: value.startLocation)
        }
        continueDrag(at: value.location)
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

    dragSegmentId = segment.id
    dragInitialStartTime = segment.startTime
    dragInitialEndTime = segment.endTime
    dragPreviewSegment = segment
    lastDragModelUpdateTime = 0

    let leftHandleEnd = segmentLayout.visualStartX + handleWidth
    let rightHandleStart = segmentLayout.visualEndX - handleWidth

    if location.x <= leftHandleEnd {
      dragMode = .startEdge
    } else if location.x >= rightHandleStart {
      dragMode = .endEdge
    } else {
      dragMode = .position
      // Anchor the grab directly on the effect track. No clip/source conversion is
      // involved, so crossing a seam remains a continuous 1:1 drag.
      let pointerSequence = sequenceTime(atX: location.x) ?? 0
      dragGrabTimelineOffset = pointerSequence - segment.startTime
    }

    // Select the segment being dragged
    state.selectZoom(id: segment.id)
  }

  private func continueDrag(at location: CGPoint) {
    guard let segmentId = dragSegmentId,
          let segment = state.zoomSegments.first(where: { $0.id == segmentId })
    else {
      return
    }

    guard let pointerSequence = sequenceTime(atX: location.x) else { return }

    let previewSegment = previewSegment(from: segment, anchorTimeline: pointerSequence)
    dragPreviewSegment = previewSegment
    commitDragPreviewIfNeeded(previewSegment)
  }

  private func previewSegment(from segment: ZoomSegment, anchorTimeline: TimeInterval) -> ZoomSegment {
    var preview = segment
    let initialDuration = dragInitialEndTime - dragInitialStartTime

    switch dragMode {
    case .none:
      return preview

    case .position:
      preview.startTime = anchorTimeline - dragGrabTimelineOffset
      preview.duration = initialDuration

    case .startEdge:
      preview.startTime = anchorTimeline
      preview.duration = max(ZoomSegment.minDuration, dragInitialEndTime - anchorTimeline)

    case .endEdge:
      preview.startTime = dragInitialStartTime
      preview.duration = max(ZoomSegment.minDuration, anchorTimeline - dragInitialStartTime)
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
    if let (segment, _) = interactionSegment(atX: location.x) {
      // Tapped on existing segment - activate it for editing (select + sidebar).
      state.openZoomConfiguration(id: segment.id)
      return
    }
    // Tapped on empty area - add new zoom centered at tap position. Inserted clips
    // are valid hosts; inactive trim slots remain ignored for direct add gestures.
    guard let tappedSequence = sequenceTime(atX: location.x),
          state.isPlayableMaterial(atSequence: tappedSequence)
    else { return }
    state.addZoom(at: tappedSequence)
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
      let addTime = hoverSequenceTime ?? CMTimeGetSeconds(state.currentTime)
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

  // MARK: - Layout & Hit Testing

  /// True-time span of a segment on the independent structural timeline. Trimmed
  /// slots remain visible in this editing axis, so reorder does not alter the span.
  private func displaySpan(for segment: ZoomSegment) -> ClosedRange<TimeInterval>? {
    guard videoDuration > 0 else { return nil }
    let start = max(0, min(segment.startTime, videoDuration))
    let end = min(videoDuration, max(start, segment.endTime))
    guard end - start > 0.0001 else { return nil }
    return start ... end
  }

  /// Padded visual span for drawing: blocks below `minVisualBlockWidth` stretch to
  /// stay grabbable and the start is clamped inside the track.
  private func paddedLayout(for span: ClosedRange<TimeInterval>) -> SegmentLayout {
    guard videoDuration > 0, timelineWidth > 0 else {
      return SegmentLayout(
        visualStartX: 0,
        visualEndX: minVisualBlockWidth,
        visualWidth: minVisualBlockWidth
      )
    }
    let logicalStartX = (span.lowerBound / videoDuration) * timelineWidth
    let logicalWidth = ((span.upperBound - span.lowerBound) / videoDuration) * timelineWidth
    let visualWidth = min(timelineWidth, max(minVisualBlockWidth, logicalWidth))
    let maxStartX = max(0, timelineWidth - visualWidth)
    let visualStartX = max(0, min(logicalStartX, maxStartX))

    return SegmentLayout(
      visualStartX: visualStartX,
      visualEndX: visualStartX + visualWidth,
      visualWidth: visualWidth
    )
  }

  /// Segments with somewhere true to sit — the drawable set.
  private var visibleSegments: [ZoomSegment] {
    state.zoomSegments.filter { displaySpan(for: $0) != nil }
  }

  /// Hit test under a pointer x. The true span answers first so what a block
  /// covers in time is what it activates; the padded visual is the fallback for
  /// narrow blocks, resolved by nearest centre. Dead segments never answer.
  private func interactionSegment(atX x: CGFloat) -> (segment: ZoomSegment, layout: SegmentLayout)? {
    let trueHits: [(segment: ZoomSegment, layout: SegmentLayout)] = state.zoomSegments.compactMap { segment in
      guard let span = displaySpan(for: segment) else { return nil }
      let startX = (span.lowerBound / videoDuration) * timelineWidth
      let endX = (span.upperBound / videoDuration) * timelineWidth
      guard endX - startX > 0.01, x >= startX, x <= endX else { return nil }
      return (segment, SegmentLayout(visualStartX: startX, visualEndX: endX, visualWidth: endX - startX))
    }
    if let hit = resolveCandidate(trueHits, atX: x) { return hit }

    let paddedHits: [(segment: ZoomSegment, layout: SegmentLayout)] = visibleSegments.compactMap { segment in
      guard let span = displaySpan(for: segment) else { return nil }
      let layout = paddedLayout(for: span)
      guard x >= layout.visualStartX, x <= layout.visualEndX else { return nil }
      return (segment, layout)
    }
    return resolveCandidate(paddedHits, atX: x)
  }

  /// Selected segment wins, then the one whose centre is nearest the pointer,
  /// then the later index — a deterministic rule for overlapping spans.
  private func resolveCandidate(
    _ candidates: [(segment: ZoomSegment, layout: SegmentLayout)],
    atX x: CGFloat
  ) -> (segment: ZoomSegment, layout: SegmentLayout)? {
    guard !candidates.isEmpty else { return nil }

    if let selectedId = state.selectedZoomId,
       let selected = candidates.first(where: { $0.segment.id == selectedId }) {
      return selected
    }

    return candidates.sorted { lhs, rhs in
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
  let isHovered: Bool
  let isEdgeHovered: Bool
  let blockX: CGFloat
  let blockWidth: CGFloat

  private let handleWidth: CGFloat = 8
  private let blockHeight: CGFloat = 32
  /// Minimum block width that fits icon + zoom level without clipping.
  private let compactContentThreshold: CGFloat = 64
  /// Minimum block width that fits icon + zoom level + type badge without clipping.
  private let extendedContentThreshold: CGFloat = 110

  var body: some View {
    ZStack(alignment: .leading) {
      TimelineSegmentChrome(
        height: blockHeight,
        baseColor: blockFillColor,
        isHovered: isHovered && !isDragging && !isSelected,
        isSelected: isSelected,
        isDragging: isDragging,
        borderColor: stateBorderColor,
        borderStyle: StrokeStyle(lineWidth: isSelected ? 1.5 : 1),
        cornerRadius: Radius.tile
      )
      .shadow(
        color: Color.black.opacity(isSelected || isDragging ? 0.35 : 0.22),
        radius: isSelected || isDragging ? 3 : 2,
        y: 1
      )

      blockContent

      handleIndicator()
        .offset(x: 0)

      handleIndicator()
        .offset(x: blockWidth - handleWidth)
    }
    .frame(width: blockWidth, height: blockHeight)
    .offset(x: blockX)
    .opacity(segment.isEnabled ? 1.0 : 0.5)
    .scaleEffect(isDragging ? 1.02 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isDragging)
    .animation(.easeOut(duration: 0.12), value: isHovered)
    .allowsHitTesting(false) // Parent handles all gestures
  }

  private var stateBorderColor: Color {
    if isSelected { return .white }
    if isEdgeHovered { return Color.white.opacity(0.55) }
    return .clear
  }

  @ViewBuilder
  private var blockContent: some View {
    if blockWidth >= compactContentThreshold {
      HStack(spacing: 3) {
        Image(systemName: "plus.magnifyingglass")
          .font(.system(size: 10, weight: .semibold))

        Text(segment.formattedZoomLevel)
          .font(.system(size: 10, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.75)

        Spacer(minLength: 0)

        if blockWidth >= extendedContentThreshold {
          Text(segment.zoomType.displayName)
            .font(.system(size: 8, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.22)))
        }
      }
      .padding(.horizontal, handleWidth + 4)
      .foregroundColor(.white)
    } else {
      HStack {
        Spacer(minLength: 0)
        Image(systemName: "plus.magnifyingglass")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.white)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, handleWidth + 2)
    }
  }

  private func handleIndicator() -> some View {
    TimelineSegmentHandleIndicator(
      height: blockHeight,
      gripOpacity: gripOpacity
    )
    .frame(width: handleWidth, height: blockHeight)
  }

  private var gripOpacity: Double {
    if isEdgeHovered { return 0.85 }
    if isSelected { return 0.8 }
    if isHovered { return 0.55 }
    return 0.38
  }

  private var blockFillColor: Color {
    if !segment.isEnabled {
      return ZoomColors.disabled
    }
    return ZoomColors.primary
  }
}

// MARK: - Zoom Placeholder View

/// Ghost placeholder showing where new zoom will be added on click
private struct ZoomPlaceholderView: View {
  let width: CGFloat
  let xPosition: CGFloat

  private let blockHeight: CGFloat = 32
  /// Minimum placeholder width that fits icon + label without clipping.
  private let labelThreshold: CGFloat = 92

  var body: some View {
    Radius.rect(Radius.tile)
      .fill(ZoomColors.primary.opacity(0.16))
      .overlay(
        Radius.rect(Radius.tile)
          .strokeBorder(
            ZoomColors.primary.opacity(0.5),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
          )
      )
      .overlay {
        if width >= labelThreshold {
          HStack(spacing: 4) {
            Image(systemName: "plus.magnifyingglass")
              .font(.system(size: 10, weight: .medium))
            Text(L10n.VideoEditor.clickToAdd)
              .font(.system(size: 9, weight: .medium))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          .foregroundColor(ZoomColors.primary.opacity(0.85))
        } else {
          Image(systemName: "plus.magnifyingglass")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(ZoomColors.primary.opacity(0.85))
        }
      }
      .frame(width: width, height: blockHeight)
      .offset(x: xPosition)
      .allowsHitTesting(false)
      .transition(.opacity.animation(.easeOut(duration: 0.15)))
  }
}

// MARK: - Preview

#Preview {
  ZoomTimelineTrack(
    state: VideoEditorState(url: URL(fileURLWithPath: "/tmp/test.mov")),
    timelineWidth: 400
  )
  .padding()
  .background(Color(NSColor.windowBackgroundColor))
}
