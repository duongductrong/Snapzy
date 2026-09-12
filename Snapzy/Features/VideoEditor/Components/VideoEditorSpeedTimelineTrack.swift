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

  private let trackHeight: CGFloat = 32
  private let handleWidth: CGFloat = 8
  private let minVisualBlockWidth: CGFloat = 64
  private let dragModelUpdateInterval: TimeInterval = 1.0 / 30.0

  // MARK: - Drag State (Track-Level)

  @State private var dragMode: DragMode = .none
  @State private var dragSegmentId: UUID?
  @State private var dragInitialStartTime: TimeInterval = 0
  @State private var dragInitialEndTime: TimeInterval = 0
  @State private var dragPreviewSegment: SpeedSegment?
  @State private var lastDragModelUpdateTime: TimeInterval = 0

  // MARK: - Hover State (Placeholder Preview)

  @State private var isHovering: Bool = false
  @State private var hoverLocation: CGPoint = .zero

  // MARK: - Rate Picker

  @State private var ratePickerSegmentId: UUID?

  private enum DragMode {
    case none
    case position
    case startEdge
    case endEdge
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
    let logicalWidth = (SpeedSegment.defaultDuration / videoDuration) * timelineWidth
    return min(timelineWidth, max(minVisualBlockWidth, logicalWidth))
  }

  private var placeholderX: CGFloat {
    let centeredX = hoverLocation.x - (placeholderWidth / 2)
    return max(0, min(centeredX, timelineWidth - placeholderWidth))
  }

  // MARK: - Body

  var body: some View {
    ZStack(alignment: .leading) {
      Radius.rect(Radius.ornament)
        .fill(Color.black.opacity(0.15))
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

      ForEach(state.speedSegments) { segment in
        let displaySegment = dragPreviewSegment?.id == segment.id ? (dragPreviewSegment ?? segment) : segment
        let segmentLayout = layout(for: displaySegment)
        SpeedBlockVisual(
          segment: displaySegment,
          isSelected: state.selectedSpeedId == segment.id,
          isDragging: dragSegmentId == segment.id,
          overlapsZoom: overlapsEnabledZoom(displaySegment),
          blockX: segmentLayout.visualStartX,
          blockWidth: segmentLayout.visualWidth
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

      if shouldShowPlaceholder {
        SpeedPlaceholderView(width: placeholderWidth, xPosition: placeholderX)
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

    state.selectSpeed(id: segment.id)
  }

  private func continueDrag(translation: CGSize) {
    guard let segmentId = dragSegmentId,
          let segment = state.speedSegments.first(where: { $0.id == segmentId }) else {
      return
    }

    let deltaSeconds = translation.width / pixelsPerSecond
    let preview = previewSegment(from: segment, deltaSeconds: deltaSeconds)
    dragPreviewSegment = preview
    commitDragPreviewIfNeeded(preview)
  }

  private func previewSegment(from segment: SpeedSegment, deltaSeconds: TimeInterval) -> SpeedSegment {
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
      let clampedStart = max(0, min(newStart, dragInitialEndTime - SpeedSegment.minDuration))
      preview.startTime = clampedStart
      preview.duration = max(SpeedSegment.minDuration, dragInitialEndTime - clampedStart)

    case .endEdge:
      let newEnd = dragInitialEndTime + deltaSeconds
      let clampedEnd = max(dragInitialStartTime + SpeedSegment.minDuration, min(newEnd, videoDuration))
      preview.startTime = dragInitialStartTime
      preview.duration = max(SpeedSegment.minDuration, clampedEnd - dragInitialStartTime)
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
    let tappedTime = (location.x / timelineWidth) * videoDuration

    if let (segment, _) = interactionSegment(atX: location.x) {
      state.selectSpeed(id: segment.id)
    } else {
      state.addSpeed(at: tappedTime)
    }
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
      let addTime = isHovering ? hoverTime : CMTimeGetSeconds(state.currentTime)
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

  private func layout(for segment: SpeedSegment) -> SegmentLayout {
    guard videoDuration > 0, timelineWidth > 0 else {
      return SegmentLayout(visualStartX: 0, visualEndX: minVisualBlockWidth, visualWidth: minVisualBlockWidth)
    }

    let logicalStartX = (segment.startTime / videoDuration) * timelineWidth
    let logicalWidth = (segment.duration / videoDuration) * timelineWidth
    let visualWidth = min(timelineWidth, max(minVisualBlockWidth, logicalWidth))
    let maxStartX = max(0, timelineWidth - visualWidth)
    let visualStartX = max(0, min(logicalStartX, maxStartX))

    return SegmentLayout(visualStartX: visualStartX, visualEndX: visualStartX + visualWidth, visualWidth: visualWidth)
  }

  private func interactionSegment(atX x: CGFloat) -> (segment: SpeedSegment, layout: SegmentLayout)? {
    let containing = state.speedSegments.compactMap { segment -> (segment: SpeedSegment, layout: SegmentLayout)? in
      let segmentLayout = layout(for: segment)
      guard x >= segmentLayout.visualStartX, x <= segmentLayout.visualEndX else { return nil }
      return (segment: segment, layout: segmentLayout)
    }

    guard !containing.isEmpty else { return nil }

    if let selectedId = state.selectedSpeedId,
       let selected = containing.first(where: { $0.segment.id == selectedId }) {
      return selected
    }

    return containing.sorted { lhs, rhs in
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

  /// True when the segment's range intersects an enabled zoom segment (informational cue).
  private func overlapsEnabledZoom(_ segment: SpeedSegment) -> Bool {
    state.zoomSegments.contains { zoom in
      zoom.isEnabled && segment.startTime < zoom.endTime && segment.endTime > zoom.startTime
    }
  }
}

// MARK: - Speed Block Visual (No Gestures)

private struct SpeedBlockVisual: View {
  let segment: SpeedSegment
  let isSelected: Bool
  let isDragging: Bool
  let overlapsZoom: Bool
  let blockX: CGFloat
  let blockWidth: CGFloat

  private let handleWidth: CGFloat = 8

  var body: some View {
    ZStack(alignment: .leading) {
      Radius.controlRect(forHeight: 28)
        .fill(blockFillColor)
        .overlay(
          Radius.controlRect(forHeight: 28)
            .strokeBorder(borderColor, style: borderStyle)
        )
        .shadow(color: isSelected ? SpeedColors.fill(for: segment.rate).opacity(0.4) : .clear, radius: 4, y: 2)

      HStack(spacing: 4) {
        Image(systemName: segment.rate >= 1.0 ? "hare.fill" : "tortoise.fill")
          .font(.system(size: 10, weight: .semibold))

        if blockWidth >= 44 {
          Text(segment.formattedRate)
            .font(.system(size: 10, weight: .semibold))
        }

        Spacer(minLength: 0)

        if overlapsZoom, blockWidth >= 72 {
          Image(systemName: "plus.magnifyingglass")
            .font(.system(size: 8, weight: .medium))
            .help(L10n.VideoEditor.speedZoomOverlapHint)
        }
      }
      .padding(.horizontal, blockWidth < 48 ? handleWidth + 2 : handleWidth + 4)
      .foregroundColor(.white)

      handleIndicator().offset(x: 0)
      handleIndicator().offset(x: blockWidth - handleWidth)
    }
    .frame(width: blockWidth, height: 28)
    .offset(x: blockX)
    .opacity(segment.isEnabled ? 1.0 : 0.5)
    .scaleEffect(isDragging ? 1.02 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isDragging)
    .allowsHitTesting(false)
  }

  private func handleIndicator() -> some View {
    ZStack {
      Rectangle()
        .fill(isSelected ? Color.white.opacity(0.2) : Color.clear)
      Radius.rect(Radius.ornament)
        .fill(isSelected ? Color.white.opacity(0.8) : Color.white.opacity(0.4))
        .frame(width: 3, height: 14)
    }
    .frame(width: handleWidth, height: 28)
  }

  private var blockFillColor: Color {
    if !segment.isEnabled { return SpeedColors.disabled }
    let base = SpeedColors.fill(for: segment.rate)
    return isDragging ? base.opacity(0.85) : base
  }

  private var borderColor: Color {
    if isSelected { return .white }
    if overlapsZoom { return .red.opacity(0.8) }
    return .clear
  }

  private var borderStyle: StrokeStyle {
    overlapsZoom && !isSelected
      ? StrokeStyle(lineWidth: 1.5, dash: [4, 3])
      : StrokeStyle(lineWidth: 2)
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

  var body: some View {
    Radius.controlRect(forHeight: 28)
      .fill(SpeedColors.speedUp.opacity(0.2))
      .overlay(
        Radius.controlRect(forHeight: 28)
          .strokeBorder(
            SpeedColors.speedUp.opacity(0.5),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
          )
      )
      .overlay(
        HStack(spacing: 4) {
          Image(systemName: "gauge.with.dots.needle.67percent")
            .font(.system(size: 10, weight: .medium))
          Text(L10n.VideoEditor.speedClickToAdd)
            .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(SpeedColors.speedUp.opacity(0.9))
      )
      .frame(width: width, height: 28)
      .offset(x: xPosition)
      .allowsHitTesting(false)
      .transition(.opacity.animation(.easeOut(duration: 0.15)))
  }
}
