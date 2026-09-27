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
struct SpeedTimelineTrack: View, Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.state === rhs.state && lhs.timelineWidth == rhs.timelineWidth && lhs.visibleRange == rhs.visibleRange
  }
  let state: VideoEditorState
  @StateObject private var observation: VideoEditorTimelineObservation
  let timelineWidth: CGFloat
  var visibleRange: ClosedRange<CGFloat>? = nil

  init(state: VideoEditorState, timelineWidth: CGFloat, visibleRange: ClosedRange<CGFloat>? = nil) {
    self.state = state
    self.timelineWidth = timelineWidth
    self.visibleRange = visibleRange
    _observation = StateObject(wrappedValue: VideoEditorTimelineObservation(state: state, surface: .speed))
  }

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
  @State private var resolvedHover: HoverState = .none

  // MARK: - Rate Picker

  @State private var ratePickerSegmentId: UUID?

  private enum DragMode {
    case none
    case position
    case startEdge
    case endEdge
  }

  private enum SegmentEdge: Equatable {
    case start
    case end
  }

  private struct HoverState: Equatable {
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
    isHovering && dragMode == .none ? resolvedHover : .none
  }

  private var isHoveringOverSegment: Bool {
    resolvedHover.segmentId != nil
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
    let _ = observation.revision
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
          TimelineSegmentPopoverAnchor(
            layout: TimelineSegmentPopoverAnchorLayout(
              leading: paddedLayout.visualStartX,
              segmentWidth: paddedLayout.visualWidth,
              trackWidth: timelineWidth
            ),
            height: trackHeight,
            isPresented: ratePickerBinding(for: segment.id),
            arrowEdge: .top
          ) {
            SpeedBlockVisual(
              segment: displaySegment,
              isSelected: state.selectedSpeedId == segment.id,
              isDragging: dragSegmentId == segment.id,
              isHovered: hover.segmentId == segment.id,
              isEdgeHovered: hover.segmentId == segment.id && hover.edge != nil,
              overlapsZoom: overlapsEnabledZoom(displaySegment),
              blockWidth: paddedLayout.visualWidth
            )
            .equatable()
          } popoverContent: {
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
    .accessibilityIdentifier("video-editor.speed-track")
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
        updateHover(at: location)
      case .ended:
        isHovering = false
        resolvedHover = .none
        clearCursor()
      }
    }
    .onChange(of: observation.revision) { _ in
      if isHovering { updateHover(at: hoverLocation) }
    }
    .contextMenu {
      trackContextMenu
    }
    .onDisappear {
      if dragMode != .none { endDrag() }
    }
  }

  // MARK: - Cursor

  private func updateHover(at location: CGPoint) {
    guard dragMode == .none else { return }
    if let (segment, layout) = interactionSegment(atX: location.x) {
      let edge: SegmentEdge? = location.x <= layout.visualStartX + handleWidth ? .start
        : (location.x >= layout.visualEndX - handleWidth ? .end : nil)
      let hover = HoverState(segmentId: segment.id, edge: edge)
      if hover != resolvedHover { resolvedHover = hover }
      setCursor(edge != nil ? .resizeLeftRight : .pointingHand)
    } else {
      if resolvedHover != .none { resolvedHover = .none }
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
      .onEnded { value in
        continueDrag(at: value.location)
        endDrag()
      }
  }

  private func beginDrag(at location: CGPoint) {
    PerfSignpost.VideoEditor.event("SegmentDragBegin")
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
    state.beginSpeedEdit(id: segment.id)
  }

  private func continueDrag(at location: CGPoint) {
    let interval = PerfSignpost.VideoEditor.beginInterval("SegmentPointerUpdate")
    defer { PerfSignpost.VideoEditor.endInterval(interval) }
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

    return state.resolvedSpeedSegment(id: segment.id, startTime: preview.startTime, duration: preview.duration) ?? segment
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
    guard let id = dragSegmentId else { return }
    PerfSignpost.VideoEditor.event("SegmentDragEnd")
    if let dragPreviewSegment {
      commitDragPreviewIfNeeded(dragPreviewSegment, force: true)
    }
    state.endSpeedEdit(id: id)
    dragMode = .none
    dragSegmentId = nil
    dragPreviewSegment = nil
    lastDragModelUpdateTime = 0
    if isHovering { updateHover(at: hoverLocation) }
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
    state.speedSegments.filter { segment in
      guard let span = displaySpan(for: segment) else { return false }
      if segment.id == dragSegmentId || segment.id == ratePickerSegmentId { return true }
      guard let visibleRange else { return true }
      let layout = paddedLayout(for: span)
      return layout.visualEndX >= visibleRange.lowerBound && layout.visualStartX <= visibleRange.upperBound
    }
  }

  /// Hit test under a pointer x. The true span answers first so what a block
  /// covers in time is what it activates; the padded visual is the fallback for
  /// narrow blocks, resolved by nearest centre. Dead segments never answer.
  private func interactionSegment(atX x: CGFloat) -> (segment: SpeedSegment, layout: SegmentLayout)? {
    var trueWinner: (segment: SpeedSegment, layout: SegmentLayout)?
    var paddedWinner: (segment: SpeedSegment, layout: SegmentLayout)?
    func preferred(_ candidate: (segment: SpeedSegment, layout: SegmentLayout),
                   over winner: (segment: SpeedSegment, layout: SegmentLayout)?) -> Bool {
      guard let winner else { return true }
      if winner.segment.id == state.selectedSpeedId { return false }
      if candidate.segment.id == state.selectedSpeedId { return true }
      // Iteration follows authored order; equal distance replaces with later index.
      return abs(candidate.layout.centerX - x) <= abs(winner.layout.centerX - x)
    }
    for segment in state.speedSegments {
      guard let span = displaySpan(for: segment) else { continue }
      let startX = (span.lowerBound / videoDuration) * timelineWidth
      let endX = (span.upperBound / videoDuration) * timelineWidth
      if endX - startX > 0.01, x >= startX, x <= endX {
        let candidate = (segment, SegmentLayout(visualStartX: startX, visualEndX: endX, visualWidth: endX - startX))
        if preferred(candidate, over: trueWinner) { trueWinner = candidate }
      }
      let layout = paddedLayout(for: span)
      if x >= layout.visualStartX, x <= layout.visualEndX {
        let candidate = (segment, layout)
        if preferred(candidate, over: paddedWinner) { paddedWinner = candidate }
      }
    }
    return trueWinner ?? paddedWinner
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

/// The normal-flow frame used by a timeline segment and its popover source.
/// Keeping this geometry explicit prevents visual offsets from diverging from
/// the frame SwiftUI uses to place presentations.
struct TimelineSegmentPopoverAnchorLayout: Equatable {
  let leading: CGFloat
  let segmentWidth: CGFloat
  let trackWidth: CGFloat

  var contentFrame: CGRect {
    let safeTrackWidth = max(0, trackWidth)
    let safeSegmentWidth = min(max(0, segmentWidth), safeTrackWidth)
    let maxLeading = max(0, safeTrackWidth - safeSegmentWidth)
    let safeLeading = max(0, min(leading, maxLeading))
    return CGRect(x: safeLeading, y: 0, width: safeSegmentWidth, height: 0)
  }
}

/// Places a timeline segment in normal layout flow so SwiftUI popovers use the
/// same anchor as the segment's rendered position. An `offset` would move only
/// the pixels and leave the popover source frame at the track's leading edge.
struct TimelineSegmentPopoverAnchor<Content: View, PopoverContent: View>: View {
  let layout: TimelineSegmentPopoverAnchorLayout
  let height: CGFloat
  @Binding var isPresented: Bool
  let arrowEdge: Edge
  let content: Content
  let popoverContent: PopoverContent

  init(
    layout: TimelineSegmentPopoverAnchorLayout,
    height: CGFloat,
    isPresented: Binding<Bool>,
    arrowEdge: Edge,
    @ViewBuilder content: () -> Content,
    @ViewBuilder popoverContent: () -> PopoverContent
  ) {
    self.layout = layout
    self.height = height
    _isPresented = isPresented
    self.arrowEdge = arrowEdge
    self.content = content()
    self.popoverContent = popoverContent()
  }

  var body: some View {
    HStack(spacing: 0) {
      Color.clear
        .frame(width: layout.contentFrame.minX)
        .allowsHitTesting(false)

      content
        .frame(width: layout.contentFrame.width)
        .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
          popoverContent
        }

      Spacer(minLength: 0)
    }
    .frame(width: layout.trackWidth, height: height, alignment: .leading)
  }
}

// MARK: - Speed Block Visual (No Gestures)

private struct SpeedBlockVisual: View, Equatable {
  let segment: SpeedSegment
  let isSelected: Bool
  let isDragging: Bool
  let isHovered: Bool
  let isEdgeHovered: Bool
  let overlapsZoom: Bool
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
        .accessibilityIdentifier("video-editor.speed-item.\(segment.id.uuidString).start-handle")
        .offset(x: 0)

      handleIndicator()
        .accessibilityIdentifier("video-editor.speed-item.\(segment.id.uuidString).end-handle")
        .offset(x: blockWidth - handleWidth)
    }
    .frame(width: blockWidth, height: blockHeight)
    .opacity(segment.isEnabled ? 1.0 : 0.5)
    .scaleEffect(isDragging ? 1.02 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isDragging)
    .animation(.easeOut(duration: 0.12), value: isHovered)
    .accessibilityIdentifier("video-editor.speed-item.\(segment.id.uuidString)")
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
