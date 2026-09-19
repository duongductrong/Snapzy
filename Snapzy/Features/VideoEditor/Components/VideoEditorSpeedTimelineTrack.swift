//
//  VideoEditorSpeedTimelineTrack.swift
//  Snapzy
//
//  Timeline track displaying speed (timelapse) segments with interactive blocks.
//  Mirrors ZoomTimelineTrack: track-level gestures, drag to reposition/resize, tap to add.
//

import AVFoundation
import SwiftUI

// MARK: - Speed Colors

enum SpeedColors {
  /// Speed-up (rate > 1) — warm/orange.
  static let speedUp = Color(red: 0.95, green: 0.55, blue: 0.15)
  /// Slow-down (rate < 1) — cool/blue.
  static let slowDown = Color(red: 0.20, green: 0.55, blue: 0.95)
  /// Neutral (rate == 1).
  static let neutral = Color(NSColor.systemGray)
  static let disabled = Color(NSColor.disabledControlTextColor)

  static func fill(for rate: Double) -> Color {
    if rate > 1.0 { return speedUp }
    if rate < 1.0 { return slowDown }
    return neutral
  }
}

/// Timeline track for speed segments — all gestures handled at track level.
struct SpeedTimelineTrack: View {
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
  @State private var dragPreviewSegment: SpeedSegment?
  @State private var lastDragModelUpdateTime: TimeInterval = 0

  // MARK: - Hover State (Placeholder Preview)

  @State private var isHovering: Bool = false
  @State private var hoverLocation: CGPoint = .zero
  @State private var activeCursor: NSCursor?

  // MARK: - Rate Picker

  @State private var ratePickerSegmentId: UUID?

  private enum DragMode {
    case none
    case position
    case startEdge
    case endEdge
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
    let logicalWidth = (SpeedSegment.defaultDuration / videoDuration) * timelineWidth
    return min(timelineWidth, max(minVisualBlockWidth, logicalWidth))
  }

  private var placeholderX: CGFloat {
    let centeredX = hoverLocation.x - (placeholderWidth / 2)
    return max(0, min(centeredX, timelineWidth - placeholderWidth))
  }

  // MARK: - Body

  var body: some View {
    let hover = hoverState

    ZStack(alignment: .leading) {
      TimelineTrackLaneWell()
        .frame(height: trackHeight)

      HStack {
        Image(systemName: "gauge.with.dots.needle.67percent")
          .font(.system(size: 9))
          .foregroundColor(.secondary)
        Text(L10n.VideoEditor.speeds)
          .font(.system(size: 9, weight: .medium))
          .foregroundColor(.secondary)
        Spacer()
      }
      .padding(.leading, 6)
      .help(L10n.VideoEditor.speedTrackTooltip)
      .allowsHitTesting(false)

      // Speed blocks (visual only - gestures handled at track level).
      // Blocks stay on the structural effect track. Playback/export later projects
      // their ranges over active clip material and collapses trim gaps.
      ForEach(visibleSegments) { segment in
        let displaySegment = dragPreviewSegment?.id == segment.id ? (dragPreviewSegment ?? segment) : segment
        if let span = displaySpan(for: displaySegment) {
          let paddedLayout = paddedLayout(for: span)
          SpeedBlockVisual(
            segment: displaySegment,
            isSelected: state.selectedSpeedId == segment.id,
            isDragging: dragSegmentId == segment.id,
            isHovered: hover.segmentId == segment.id,
            isEdgeHovered: hover.segmentId == segment.id && hover.edge != nil,
            overlapsZoom: overlapsEnabledZoom(displaySegment),
            blockX: paddedLayout.visualStartX,
            blockWidth: paddedLayout.visualWidth
          )
          .popover(isPresented: ratePickerBinding(for: segment.id), arrowEdge: .top) {
            SpeedRatePicker(
              rate: segment.rate,
              onSelect: { newRate in
                state.updateSpeed(id: segment.id, rate: newRate)
              }
            )
          }
        }
      }

      if shouldShowPlaceholder {
        SpeedPlaceholderView(width: placeholderWidth, xPosition: placeholderX)
      }
    }
    .frame(height: trackHeight)
    .clipShape(Radius.rect(Radius.tile))
    .contentShape(Rectangle())
    // The track owns the drag. Giving it priority prevents the tap/context
    // recognizers from competing for the same mouse sequence and leaving the
    // terminal event to the window responder chain.
    .highPriorityGesture(unifiedDragGesture)
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
    activeCursor = cursor
    // `push`/`pop` use one process-global stack. SwiftUI can recreate or
    // overlap hover responders during a drag, which makes that stack
    // unbalanced. Setting the current cursor is idempotent and has no stack
    // ownership to leak across view updates.
    cursor.set()
  }

  private func clearCursor() {
    guard activeCursor != nil else { return }
    self.activeCursor = nil
    NSCursor.arrow.set()
  }

  // MARK: - Rate Picker Binding

  private func ratePickerBinding(for id: UUID) -> Binding<Bool> {
    Binding(
      get: { ratePickerSegmentId == id },
      set: { newValue in ratePickerSegmentId = newValue ? id : nil }
    )
  }

  // MARK: - Unified Drag Gesture

  private var unifiedDragGesture: some Gesture {
    DragGesture(minimumDistance: 3)
      .onChanged { value in
        if dragMode == .none {
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

    state.selectSpeed(id: segment.id)
  }

  private func continueDrag(at location: CGPoint) {
    guard let segmentId = dragSegmentId,
          let segment = state.speedSegments.first(where: { $0.id == segmentId })
    else {
      return
    }

    guard let pointerSequence = sequenceTime(atX: location.x) else { return }

    let preview = previewSegment(from: segment, anchorTimeline: pointerSequence)
    dragPreviewSegment = preview
    commitDragPreviewIfNeeded(preview)
  }

  private func previewSegment(from segment: SpeedSegment, anchorTimeline: TimeInterval) -> SpeedSegment {
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
      preview.duration = max(SpeedSegment.minDuration, dragInitialEndTime - anchorTimeline)

    case .endEdge:
      preview.startTime = dragInitialStartTime
      preview.duration = max(SpeedSegment.minDuration, anchorTimeline - dragInitialStartTime)
    }

    return preview
  }

  private func commitDragPreviewIfNeeded(_ segment: SpeedSegment, force: Bool = false) {
    let now = ProcessInfo.processInfo.systemUptime
    guard force || now - lastDragModelUpdateTime >= dragModelUpdateInterval else { return }

    state.updateSpeed(
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
      state.selectSpeed(id: segment.id)
      return
    }
    // Add on any active video clip; the effect track is independent from clip source.
    guard let tappedSequence = sequenceTime(atX: location.x),
          state.isPlayableMaterial(atSequence: tappedSequence)
    else { return }
    state.addSpeed(at: tappedSequence)
  }

  private func handleDoubleTap(at location: CGPoint) {
    guard let (segment, _) = interactionSegment(atX: location.x) else { return }
    state.selectSpeed(id: segment.id)
    ratePickerSegmentId = segment.id
  }

  // MARK: - Context Menu

  @ViewBuilder
  private var trackContextMenu: some View {
    Button {
      let addTime = hoverSequenceTime ?? CMTimeGetSeconds(state.currentTime)
      state.addSpeed(at: addTime)
    } label: {
      Label(
        isHovering ? L10n.VideoEditor.addSpeedHere : L10n.VideoEditor.addSpeedAtPlayhead,
        systemImage: "gauge.with.dots.needle.67percent"
      )
    }

    if let selected = state.selectedSpeedSegment {
      Divider()

      Menu {
        ForEach(SpeedSegment.presets, id: \.self) { preset in
          Button {
            state.updateSpeed(id: selected.id, rate: preset)
          } label: {
            Text(rateLabel(preset))
          }
        }
      } label: {
        Label(L10n.VideoEditor.speeds, systemImage: "speedometer")
      }

      Button {
        state.toggleSpeedEnabled(id: selected.id)
      } label: {
        Label(
          selected.isEnabled ? L10n.VideoEditor.disableSpeed : L10n.VideoEditor.enableSpeed,
          systemImage: selected.isEnabled ? "eye.slash" : "eye"
        )
      }

      Button(role: .destructive) {
        state.removeSpeed(id: selected.id)
      } label: {
        Label(L10n.VideoEditor.deleteSpeed, systemImage: "trash")
      }
    }

    if !state.speedSegments.isEmpty {
      Divider()
      Button(role: .destructive) {
        state.removeAllSpeeds()
      } label: {
        Label(L10n.VideoEditor.removeAllSpeeds, systemImage: "trash.fill")
      }
    }
  }

  private func rateLabel(_ rate: Double) -> String {
    rate == floor(rate) ? String(format: "%.0fx", rate) : String(format: "%.2gx", rate)
  }

  // MARK: - Layout & Hit Testing

  /// True-time span of a segment on the independent structural timeline. Trimmed
  /// slots remain visible in this editing axis, so reorder does not alter the span.
  private func displaySpan(for segment: SpeedSegment) -> ClosedRange<TimeInterval>? {
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
      return SegmentLayout(visualStartX: 0, visualEndX: minVisualBlockWidth, visualWidth: minVisualBlockWidth)
    }
    let logicalStartX = (span.lowerBound / videoDuration) * timelineWidth
    let logicalWidth = ((span.upperBound - span.lowerBound) / videoDuration) * timelineWidth
    let visualWidth = min(timelineWidth, max(minVisualBlockWidth, logicalWidth))
    let maxStartX = max(0, timelineWidth - visualWidth)
    let visualStartX = max(0, min(logicalStartX, maxStartX))
    return SegmentLayout(visualStartX: visualStartX, visualEndX: visualStartX + visualWidth, visualWidth: visualWidth)
  }

  /// Segments with somewhere true to sit — the drawable set.
  private var visibleSegments: [SpeedSegment] {
    state.speedSegments.filter { displaySpan(for: $0) != nil }
  }

  /// Hit test under a pointer x. The true span answers first so what a block
  /// covers in time is what it activates; the padded visual is the fallback for
  /// narrow blocks, resolved by nearest centre. Dead segments never answer.
  private func interactionSegment(atX x: CGFloat) -> (segment: SpeedSegment, layout: SegmentLayout)? {
    let trueHits: [(segment: SpeedSegment, layout: SegmentLayout)] = state.speedSegments.compactMap { segment in
      guard let span = displaySpan(for: segment) else { return nil }
      let startX = (span.lowerBound / videoDuration) * timelineWidth
      let endX = (span.upperBound / videoDuration) * timelineWidth
      guard endX - startX > 0.01, x >= startX, x <= endX else { return nil }
      return (segment, SegmentLayout(visualStartX: startX, visualEndX: endX, visualWidth: endX - startX))
    }
    if let hit = resolveCandidate(trueHits, atX: x) { return hit }

    let paddedHits: [(segment: SpeedSegment, layout: SegmentLayout)] = visibleSegments.compactMap { segment in
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
    _ candidates: [(segment: SpeedSegment, layout: SegmentLayout)],
    atX x: CGFloat
  ) -> (segment: SpeedSegment, layout: SegmentLayout)? {
    guard !candidates.isEmpty else { return nil }

    if let selectedId = state.selectedSpeedId,
       let selected = candidates.first(where: { $0.segment.id == selectedId }) {
      return selected
    }

    return candidates.sorted { lhs, rhs in
      let leftDistance = abs(lhs.layout.centerX - x)
      let rightDistance = abs(rhs.layout.centerX - x)
      if leftDistance != rightDistance {
        return leftDistance < rightDistance
      }
      let leftIndex = state.speedSegments.firstIndex(where: { $0.id == lhs.segment.id }) ?? -1
      let rightIndex = state.speedSegments.firstIndex(where: { $0.id == rhs.segment.id }) ?? -1
      return leftIndex > rightIndex
    }.first
  }

  /// True when the segment's timeline range intersects an enabled zoom range
  /// (informational cue).
  private func overlapsEnabledZoom(_ segment: SpeedSegment) -> Bool {
    let speedStart = segment.startTime
    let speedEnd = segment.endTime
    return state.zoomSegments.contains { zoom in
      zoom.isEnabled && speedStart < zoom.endTime && speedEnd > zoom.startTime
    }
  }
}

// MARK: - Speed Block Visual (No Gestures)

private struct SpeedBlockVisual: View {
  let segment: SpeedSegment
  let isSelected: Bool
  let isDragging: Bool
  let isHovered: Bool
  let isEdgeHovered: Bool
  let overlapsZoom: Bool
  let blockX: CGFloat
  let blockWidth: CGFloat

  private let handleWidth: CGFloat = 8
  private let blockHeight: CGFloat = 32
  /// Minimum block width that fits icon + rate label without clipping.
  private let compactContentThreshold: CGFloat = 72
  /// Minimum block width that fits icon + rate label + zoom-overlap cue without clipping.
  private let extendedContentThreshold: CGFloat = 88

  var body: some View {
    ZStack(alignment: .leading) {
      TimelineSegmentChrome(
        height: blockHeight,
        baseColor: blockFillColor,
        isHovered: isHovered && !isDragging && !isSelected,
        isSelected: isSelected,
        isDragging: isDragging,
        borderColor: stateBorderColor,
        borderStyle: StrokeStyle(lineWidth: stateBorderWidth, dash: stateBorderDash),
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
    .allowsHitTesting(false)
  }

  private var stateBorderColor: Color {
    if isSelected { return .white }
    if overlapsZoom { return Color.red.opacity(0.8) }
    if isEdgeHovered { return Color.white.opacity(0.55) }
    return .clear
  }

  private var stateBorderWidth: CGFloat {
    isSelected || overlapsZoom ? 1.5 : 1
  }

  private var stateBorderDash: [CGFloat] {
    overlapsZoom && !isSelected ? [4, 3] : []
  }

  @ViewBuilder
  private var blockContent: some View {
    if blockWidth >= compactContentThreshold {
      HStack(spacing: 3) {
        Image(systemName: segment.rate >= 1.0 ? "hare.fill" : "tortoise.fill")
          .font(.system(size: 10, weight: .semibold))

        Text(segment.formattedRate)
          .font(.system(size: 10, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.75)

        Spacer(minLength: 0)

        if overlapsZoom, blockWidth >= extendedContentThreshold {
          Image(systemName: "plus.magnifyingglass")
            .font(.system(size: 8, weight: .medium))
            .help(L10n.VideoEditor.speedZoomOverlapHint)
        }
      }
      .padding(.horizontal, handleWidth + 4)
      .foregroundColor(.white)
    } else {
      HStack {
        Spacer(minLength: 0)
        Image(systemName: segment.rate >= 1.0 ? "hare.fill" : "tortoise.fill")
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
    if !segment.isEnabled { return SpeedColors.disabled }
    return SpeedColors.fill(for: segment.rate)
  }
}

// MARK: - Speed Rate Picker

private struct SpeedRatePicker: View {
  let rate: Double
  let onSelect: (Double) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.VideoEditor.speeds)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)

      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
        ForEach(SpeedSegment.presets, id: \.self) { preset in
          Button {
            onSelect(preset)
          } label: {
            Text(label(preset))
              .font(.system(size: 11, weight: .medium))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 5)
              .background(
                Capsule(style: .continuous)
                  .fill(isCurrent(preset) ? SpeedColors.fill(for: preset).opacity(0.9) : Color.gray.opacity(0.15))
              )
              .foregroundColor(isCurrent(preset) ? .white : .primary)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(12)
    .frame(width: 180)
  }

  private func isCurrent(_ preset: Double) -> Bool {
    abs(preset - rate) < 0.001
  }

  private func label(_ value: Double) -> String {
    value == floor(value) ? String(format: "%.0fx", value) : String(format: "%.2gx", value)
  }
}

// MARK: - Speed Placeholder View

private struct SpeedPlaceholderView: View {
  let width: CGFloat
  let xPosition: CGFloat

  private let blockHeight: CGFloat = 32
  /// Minimum placeholder width that fits icon + label without clipping.
  private let labelThreshold: CGFloat = 92

  var body: some View {
    Radius.rect(Radius.tile)
      .fill(SpeedColors.speedUp.opacity(0.16))
      .overlay(
        Radius.rect(Radius.tile)
          .strokeBorder(
            SpeedColors.speedUp.opacity(0.5),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
          )
      )
      .overlay {
        if width >= labelThreshold {
          HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.67percent")
              .font(.system(size: 10, weight: .medium))
            Text(L10n.VideoEditor.speedClickToAdd)
              .font(.system(size: 9, weight: .medium))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          .foregroundColor(SpeedColors.speedUp.opacity(0.9))
        } else {
          Image(systemName: "gauge.with.dots.needle.67percent")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(SpeedColors.speedUp.opacity(0.9))
        }
      }
      .frame(width: width, height: blockHeight)
      .offset(x: xPosition)
      .allowsHitTesting(false)
      .transition(.opacity.animation(.easeOut(duration: 0.15)))
  }
}
