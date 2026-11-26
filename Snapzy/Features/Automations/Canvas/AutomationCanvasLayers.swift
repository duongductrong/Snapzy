//
//  AutomationCanvasLayers.swift
//  Snapzy
//
//  Non-interactive layers under and between the nodes: the dot grid, the
//  links and the dashed "Otherwise" jumps of conditions.
//  Everything is drawn in screen space from canvas geometry and the viewport.
//

import SwiftUI

enum AutomationCanvasGeometry {
  static func outPort(of frame: CGRect) -> CGPoint {
    CGPoint(x: frame.maxX, y: frame.midY)
  }

  static func inPort(of frame: CGRect) -> CGPoint {
    CGPoint(x: frame.minX, y: frame.midY)
  }

  /// Control points of the link curve; links that go backwards loop out wider.
  static func controls(from start: CGPoint, to end: CGPoint, scale: CGFloat) -> (CGPoint, CGPoint) {
    let dx = end.x - start.x
    let reach = max(40 * scale, abs(dx) / 2) + (dx < 0 ? 80 * scale : 0)
    return (CGPoint(x: start.x + reach, y: start.y), CGPoint(x: end.x - reach, y: end.y))
  }

  static func curve(from start: CGPoint, to end: CGPoint, scale: CGFloat) -> Path {
    let (c1, c2) = controls(from: start, to: end, scale: scale)
    var path = Path()
    path.move(to: start)
    path.addCurve(to: end, control1: c1, control2: c2)
    return path
  }

  /// Point halfway along the link curve.
  static func midpoint(from start: CGPoint, to end: CGPoint, scale: CGFloat) -> CGPoint {
    let (c1, c2) = controls(from: start, to: end, scale: scale)
    return CGPoint(
      x: (start.x + 3 * c1.x + 3 * c2.x + end.x) / 8,
      y: (start.y + 3 * c1.y + 3 * c2.y + end.y) / 8
    )
  }

  static func arrowHead(at tip: CGPoint, size: CGFloat) -> Path {
    var path = Path()
    path.move(to: tip)
    path.addLine(to: CGPoint(x: tip.x - size, y: tip.y - size * 0.6))
    path.addLine(to: CGPoint(x: tip.x - size, y: tip.y + size * 0.6))
    path.closeSubpath()
    return path
  }
}

/// Dot grid that pans and zooms with the canvas; thins out when zoomed far out.
struct AutomationCanvasGrid: View {
  let viewport: AutomationCanvasViewport

  var body: some View {
    Canvas { context, size in
      var spacing = 24 * viewport.scale
      while spacing < 16 { spacing *= 2 }
      let radius = max(0.6, min(1, viewport.scale * 0.9))
      let startX = viewport.offset.width.truncatingRemainder(dividingBy: spacing) - spacing
      let startY = viewport.offset.height.truncatingRemainder(dividingBy: spacing) - spacing
      var dots = Path()
      var y = startY
      while y < size.height + spacing {
        var x = startX
        while x < size.width + spacing {
          dots.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
          x += spacing
        }
        y += spacing
      }
      context.fill(dots, with: .color(AutomationCanvasTheme.gridDot))
    }
  }
}

/// A condition's "Otherwise" jump, drawn as a dashed curve under the chain.
struct AutomationCanvasOtherwiseJump: Hashable {
  let condition: UUID
  /// Step the run continues at when the condition fails; nil ends the run.
  let target: UUID?
}

/// Link curve whose end points animate, so links follow nodes during springs.
struct AutomationCanvasLinkShape: Shape {
  var start: CGPoint
  var end: CGPoint
  var scale: CGFloat

  var animatableData: AnimatablePair<AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>, CGFloat> {
    get { AnimatablePair(AnimatablePair(start.animatableData, end.animatableData), scale) }
    set {
      start.animatableData = newValue.first.first
      end.animatableData = newValue.first.second
      scale = newValue.second
    }
  }

  func path(in rect: CGRect) -> Path {
    AutomationCanvasGeometry.curve(from: start, to: end, scale: scale)
  }
}

/// One link: a hairline-weight curve, accent-colored when it touches the selection.
struct AutomationCanvasLinkView: View {
  let start: CGPoint
  let end: CGPoint
  let scale: CGFloat
  var isHot = false
  var isDetached = false

  var body: some View {
    AutomationCanvasLinkShape(start: start, end: end, scale: scale)
      .stroke(
        isHot ? Color.accentColor : AutomationCanvasTheme.link,
        style: StrokeStyle(
          lineWidth: max(1, 1.5 * scale),
          lineCap: .round,
          dash: isDetached ? [4 * scale, 4 * scale] : []
        )
      )
  }
}

/// Dashed "Otherwise" curve that dips under the chain (or a short stub to End).
struct AutomationCanvasJumpShape: Shape {
  var start: CGPoint
  var end: CGPoint
  var scale: CGFloat
  var isStub: Bool

  var animatableData: AnimatablePair<AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>, CGFloat> {
    get { AnimatablePair(AnimatablePair(start.animatableData, end.animatableData), scale) }
    set {
      start.animatableData = newValue.first.first
      end.animatableData = newValue.first.second
      scale = newValue.second
    }
  }

  static func bottom(from start: CGPoint, to end: CGPoint, scale: CGFloat) -> CGFloat {
    max(start.y, end.y) + 56 * scale + abs(end.x - start.x) * 0.06
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: start)
    if isStub {
      path.addLine(to: end)
    } else {
      let bottom = Self.bottom(from: start, to: end, scale: scale)
      path.addCurve(to: end, control1: CGPoint(x: start.x, y: bottom), control2: CGPoint(x: end.x, y: bottom))
    }
    return path
  }
}

struct AutomationCanvasJumpView: View {
  let start: CGPoint
  let end: CGPoint
  let scale: CGFloat
  let isStub: Bool
  let label: String

  var body: some View {
    let color = AutomationCanvasTheme.otherwise
    let labelPoint = isStub
      ? CGPoint(x: end.x, y: end.y + 12 * scale)
      : CGPoint(x: (start.x + end.x) / 2, y: AutomationCanvasJumpShape.bottom(from: start, to: end, scale: scale) - 14 * scale)
    ZStack {
      AutomationCanvasJumpShape(start: start, end: end, scale: scale, isStub: isStub)
        .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: max(1, 1.25 * scale), lineCap: .round, dash: [4 * scale, 4 * scale]))
      Circle()
        .fill(color)
        .frame(width: max(4, 5 * scale), height: max(4, 5 * scale))
        .position(end)
      if scale > 0.5 {
        Text(label)
          .font(.system(size: 10 * scale, weight: .medium))
          .foregroundStyle(color)
          .padding(.horizontal, 4 * scale)
          .background(AutomationCanvasTheme.backdrop)
          .fixedSize()
          .position(labelPoint)
      }
    }
  }
}
