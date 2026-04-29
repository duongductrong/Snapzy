//
//  ZoomBlockView.swift
//  Snapzy
//
//  Interactive zoom block displayed on timeline track
//

import SwiftUI

// MARK: - Zoom Colors

enum ZoomColors {
  // Primary colors - use system accent for native feel
  static var primary: Color { Color(NSColor.controlAccentColor) }
  static var primaryDark: Color { Color(NSColor.controlAccentColor).opacity(0.85) }

  // Semantic colors
  static let disabled = Color(NSColor.disabledControlTextColor)
  static let selected = Color.white
  static let handleHighlight = Color.white.opacity(0.8)

  // Additional semantic colors for consistency
  static var background: Color { Color(NSColor.controlBackgroundColor) }
  static var secondaryLabel: Color { Color(NSColor.secondaryLabelColor) }
  static var tertiaryLabel: Color { Color(NSColor.tertiaryLabelColor) }
}

/// Individual zoom block with drag handles for resizing
struct ZoomBlockView: View {
  let segment: ZoomSegment
  let isSelected: Bool
  let timelineWidth: CGFloat
  let videoDuration: TimeInterval
  let onSelect: () -> Void
  let onStartDrag: (TimeInterval) -> Void
  let onEndDrag: (TimeInterval) -> Void
  let onPositionDrag: (TimeInterval) -> Void

  // Drag state - track initial values when drag begins
  @State private var isDraggingStart = false
  @State private var isDraggingEnd = false
  @State private var isDraggingPosition = false
  @State private var dragInitialStartTime: TimeInterval = 0
  @State private var dragInitialEndTime: TimeInterval = 0

  // Hover state for resize handles
  @State private var isHoveringLeftHandle = false
  @State private var isHoveringRightHandle = false

  private let handleWidth: CGFloat = 8
  private let minBlockWidth: CGFloat = 32

  // MARK: - Computed Properties

  private var blockX: CGFloat {
    guard videoDuration > 0 else { return 0 }
    return (segment.startTime / videoDuration) * timelineWidth
  }

  private var blockWidth: CGFloat {
    guard videoDuration > 0 else { return minBlockWidth }
    let width = (segment.duration / videoDuration) * timelineWidth
    return max(minBlockWidth, width)
  }

  private var pixelsPerSecond: CGFloat {
    guard videoDuration > 0 else { return 1 }
    return timelineWidth / videoDuration
  }

  private var isDragging: Bool {
    isDraggingStart || isDraggingEnd || isDraggingPosition
  }

  // MARK: - Body

  var body: some View {
    ZStack(alignment: .leading) {
      // Main block background
      RoundedRectangle(cornerRadius: 6)
        .fill(blockFillColor)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(isSelected ? ZoomColors.selected : Color.clear, lineWidth: 2)
        )
        .shadow(color: isSelected ? ZoomColors.primary.opacity(0.35) : .clear, radius: 3, y: 1)

      // Content
      HStack(spacing: 4) {
        // Zoom icon
        Image(systemName: "plus.magnifyingglass")
          .font(.system(size: 10, weight: .semibold))

        // Zoom level
        Text(segment.formattedZoomLevel)
          .font(.system(size: 10, weight: .semibold))

        Spacer(minLength: 0)

        // Type badge
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

      // Left resize handle
      resizeHandle(isStart: true, isHovering: isHoveringLeftHandle)
        .offset(x: 0)
        .gesture(startResizeGesture)
        .onHover { hovering in
          isHoveringLeftHandle = hovering
          updateCursor(hovering: hovering, isResize: true)
        }

      // Right resize handle
      resizeHandle(isStart: false, isHovering: isHoveringRightHandle)
        .offset(x: blockWidth - handleWidth)
        .gesture(endResizeGesture)
        .onHover { hovering in
          isHoveringRightHandle = hovering
          updateCursor(hovering: hovering, isResize: true)
        }
    }
    .frame(width: blockWidth, height: 28)
    .offset(x: blockX)
    .opacity(segment.isEnabled ? 1.0 : 0.5)
    .scaleEffect(isDragging ? 1.02 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isDragging)
    .contentShape(Rectangle())
    .onTapGesture {
      onSelect()
    }
    .gesture(positionDragGesture)
    .contextMenu {
      contextMenuItems
    }
  }

  // MARK: - Subviews

  private func resizeHandle(isStart: Bool, isHovering: Bool) -> some View {
    ZStack {
      // Handle background
      Rectangle()
        .fill(isHovering || isSelected ? ZoomColors.handleHighlight.opacity(0.3) : Color.clear)

      // Handle grip indicator
      RoundedRectangle(cornerRadius: 1)
        .fill(isHovering || isSelected ? ZoomColors.handleHighlight : Color.white.opacity(0.4))
        .frame(width: 3, height: 14)
    }
    .frame(width: handleWidth, height: 28)
    .contentShape(Rectangle().inset(by: -6))
  }

  private func updateCursor(hovering: Bool, isResize: Bool) {
    if hovering && isResize {
      NSCursor.resizeLeftRight.push()
    } else {
      NSCursor.pop()
    }
  }

  @ViewBuilder
  private var contextMenuItems: some View {
    Button {
      onSelect()
    } label: {
      Label(L10n.VideoEditor.editZoom, systemImage: "slider.horizontal.3")
    }

    Divider()

    Button {
      // Toggle enabled handled by parent
    } label: {
      Label(
        segment.isEnabled ? L10n.VideoEditor.disableZoom : L10n.VideoEditor.enableZoom,
        systemImage: segment.isEnabled ? "eye.slash" : "eye"
      )
    }

    Button(role: .destructive) {
      // Delete handled by parent
    } label: {
      Label(L10n.VideoEditor.deleteZoom, systemImage: "trash")
    }
  }

  // MARK: - Styling

  private var blockFillColor: Color {
    if !segment.isEnabled {
      return ZoomColors.disabled
    }
    if isDragging {
      return ZoomColors.primaryDark
    }
    return ZoomColors.primary
  }

  // MARK: - Gestures

  private var startResizeGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        if !isDraggingStart {
          // Capture initial state at drag start
          dragInitialStartTime = segment.startTime
          dragInitialEndTime = segment.endTime
          isDraggingStart = true
        }
        let deltaSeconds = value.translation.width / pixelsPerSecond
        let newStart = dragInitialStartTime + deltaSeconds
        let clampedStart = max(0, min(newStart, dragInitialEndTime - ZoomSegment.minDuration))
        onStartDrag(clampedStart)
      }
      .onEnded { _ in
        isDraggingStart = false
      }
  }

  private var endResizeGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { value in
        if !isDraggingEnd {
          // Capture initial state at drag start
          dragInitialStartTime = segment.startTime
          dragInitialEndTime = segment.endTime
          isDraggingEnd = true
        }
        let deltaSeconds = value.translation.width / pixelsPerSecond
        let newEnd = dragInitialEndTime + deltaSeconds
        let clampedEnd = max(dragInitialStartTime + ZoomSegment.minDuration, min(newEnd, videoDuration))
        onEndDrag(clampedEnd)
      }
      .onEnded { _ in
        isDraggingEnd = false
      }
  }

  private var positionDragGesture: some Gesture {
    DragGesture(minimumDistance: 5)
      .onChanged { value in
        guard !isDraggingStart && !isDraggingEnd else {
          return
        }
        if !isDraggingPosition {
          // Capture initial state at drag start
          dragInitialStartTime = segment.startTime
          isDraggingPosition = true
        }
        let deltaSeconds = value.translation.width / pixelsPerSecond
        let newStart = dragInitialStartTime + deltaSeconds
        let maxStart = videoDuration - segment.duration
        let clampedStart = max(0, min(newStart, maxStart))
        onPositionDrag(clampedStart)
      }
      .onEnded { _ in
        isDraggingPosition = false
      }
  }
}
