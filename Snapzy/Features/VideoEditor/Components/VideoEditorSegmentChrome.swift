//
//  VideoEditorSegmentChrome.swift
//  Snapzy
//
//  Shared studio-style chrome for timeline segment blocks (zoom + speed tracks)
//

import SwiftUI

/// Matte chip chrome used by zoom and speed timeline segment blocks.
///
/// One fill, one soft top-light, one hairline border, one state overlay —
/// every layer is drawn inside the block bounds so the rendered footprint
/// always matches the segment it represents: no glow, halo, or sheen can
/// bleed past the chip edge and read as a second, larger block.
struct TimelineSegmentChrome: View {
  let height: CGFloat
  let baseColor: Color
  let isHovered: Bool
  let isSelected: Bool
  let isDragging: Bool
  let borderColor: Color
  var borderStyle: StrokeStyle

  init(
    height: CGFloat,
    baseColor: Color,
    isHovered: Bool = false,
    isSelected: Bool = false,
    isDragging: Bool = false,
    borderColor: Color = .clear,
    borderStyle: StrokeStyle = StrokeStyle(lineWidth: 1),
    cornerRadius: CGFloat? = nil
  ) {
    self.height = height
    self.baseColor = baseColor
    self.isHovered = isHovered
    self.isSelected = isSelected
    self.isDragging = isDragging
    self.borderColor = borderColor
    self.borderStyle = borderStyle
    self.cornerRadius = cornerRadius ?? Radius.control(forHeight: height)
  }

  private let cornerRadius: CGFloat

  var body: some View {
    let shape = Radius.rect(cornerRadius)

    shape
      .fill(baseColor)
      .overlay(
        LinearGradient(
          stops: [
            .init(color: .white.opacity(0.12), location: 0),
            .init(color: .white.opacity(0.0), location: 0.5),
            .init(color: .black.opacity(0.10), location: 1),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay(
        shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
      )
      .overlay(
        shape.fill(Color.white.opacity(isSelected ? 0.12 : (isHovered ? 0.08 : 0)))
      )
      .overlay(
        shape.fill(Color.black.opacity(isDragging ? 0.14 : 0))
      )
      .overlay(
        shape.strokeBorder(borderColor, style: borderStyle)
      )
  }
}

/// Rounded grip indicator drawn inside the resize zone of a segment block.
/// Grip only — no zone highlight, so block ends stay clean while the bar
/// still reads as the resize affordance.
struct TimelineSegmentHandleIndicator: View {
  let height: CGFloat
  let gripOpacity: Double

  var body: some View {
    Radius.rect(Radius.ornament)
      .fill(Color.white.opacity(gripOpacity))
      .frame(width: 3, height: height * 0.5)
  }
}

/// Recessed track-lane well shared by the zoom and speed timeline tracks.
///
/// The well must read *below* the surrounding timeline panel, so its fill is a
/// step deeper than the panel's, an inner shadow runs along the top edge (light
/// falls from above, so a recess darkens at its top lip), and a hairline rim
/// keeps the edge crisp against the panel. Radius matches the segment blocks
/// and the timeline container so every rounded corner on the timeline agrees.
struct TimelineTrackLaneWell: View {
  var body: some View {
    Radius.rect(Radius.tile)
      .fill(
        Color.black.opacity(0.26)
          .shadow(.inner(color: Color.black.opacity(0.30), radius: 3, x: 0, y: 2))
      )
      .overlay(
        Radius.rect(Radius.tile)
          .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
      )
  }
}
