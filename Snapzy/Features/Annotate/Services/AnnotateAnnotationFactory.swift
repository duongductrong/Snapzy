//
//  AnnotationFactory.swift
//  Snapzy
//
//  Factory for creating annotation items from drawing input
//

import CoreGraphics
import SwiftUI

/// Factory for creating annotation items
enum AnnotationFactory {
  struct CreationContext {
    var properties: AnnotationProperties
    var arrowStyle: ArrowStyle
    var arrowType: ArrowType = .tapered
    var arrowBendDirection: ArrowBendDirection = .primary
    var arrowStartHead: ArrowEndpointStyle = .none
    var arrowEndHead: ArrowEndpointStyle = .arrow
    var blurType: BlurType
    var counterValue: Int
    var watermarkText: String
    var activeAnnotationBounds: CGRect
  }

  static func createAnnotation(
    tool: AnnotationToolType,
    from start: CGPoint,
    to end: CGPoint,
    path: [CGPoint],
    state: AnnotateState
  ) -> AnnotationItem? {
    createAnnotation(
      tool: tool,
      from: start,
      to: end,
      path: path,
      context: CreationContext(
        properties: state.annotationCreationProperties(for: tool),
        arrowStyle: state.arrowStyle,
        arrowType: state.arrowType,
        arrowBendDirection: state.arrowBendDirection,
        arrowStartHead: state.arrowStartHead,
        arrowEndHead: state.arrowEndHead,
        blurType: state.blurType,
        counterValue: state.nextCounterValue(),
        watermarkText: state.watermarkText,
        activeAnnotationBounds: state.activeAnnotationBounds
      )
    )
  }

  static func createAnnotation(
    tool: AnnotationToolType,
    from start: CGPoint,
    to end: CGPoint,
    path: [CGPoint],
    context: CreationContext
  ) -> AnnotationItem? {

    let properties = context.properties

    let type: AnnotationType?

    switch tool {
    case .rectangle:
      type = .rectangle

    case .filledRectangle:
      type = .filledRectangle

    case .oval:
      type = .oval

    case .arrow:
      let initialStyle = context.arrowStyle
      let resolvedStyle: ArrowStyle
      if context.arrowBendDirection == .alternate {
        if initialStyle == .curvedRight {
          resolvedStyle = .curvedLeft
        } else if initialStyle == .curvedLeft {
          resolvedStyle = .curvedRight
        } else {
          resolvedStyle = initialStyle
        }
      } else {
        resolvedStyle = initialStyle
      }
      let resolvedDirection: ArrowBendDirection = (resolvedStyle == .curvedLeft) ? .primary : .alternate
      type = .arrow(ArrowGeometry(
        start: start,
        end: end,
        style: resolvedStyle,
        bendDirection: resolvedDirection,
        arrowType: context.arrowType,
        startHead: context.arrowStartHead,
        endHead: context.arrowEndHead
      ))

    case .line:
      type = .line(start: start, end: end)

    case .pencil:
      guard path.count > 1 else { return nil }
      type = .path(path)

    case .highlighter:
      guard path.count > 1 else { return nil }
      type = .highlight(normalizedHighlighterPath(path, strokeWidth: properties.strokeWidth))

    case .blur:
      type = .blur(context.blurType)

    case .spotlight:
      if abs(end.x - start.x) < 8 || abs(end.y - start.y) < 8 { return nil }
      type = .spotlight

    case .counter:
      type = .counter(context.counterValue)

    case .watermark:
      let text = context.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines)
      type = .watermark(text.isEmpty ? "Snapzy" : text)

    case .selection, .crop, .text, .mockup:
      return nil
    }

    guard let annotationType = type else { return nil }
    let bounds: CGRect
    switch annotationType {
    case .arrow(let geometry):
      bounds = geometry.bounds()
    case .counter:
      let diameter = AnnotationProperties.counterDiameter(for: properties.strokeWidth)
      bounds = CGRect(
        x: start.x - diameter / 2,
        y: start.y - diameter / 2,
        width: diameter,
        height: diameter
      )
    case .watermark:
      let drawnBounds = CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
      )
      bounds = watermarkBounds(
        drawnBounds: drawnBounds,
        center: start,
        canvasBounds: context.activeAnnotationBounds
      )
    case .highlight(let points):
      bounds = pathBounds(containing: points) ?? normalizedBounds(CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
      ))
    default:
      bounds = CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
      )
    }
    return AnnotationItem(type: annotationType, bounds: bounds, properties: properties)
  }

  private static func watermarkBounds(
    drawnBounds: CGRect,
    center: CGPoint,
    canvasBounds: CGRect
  ) -> CGRect {
    guard drawnBounds.width >= 24, drawnBounds.height >= 24 else {
      let width = min(max(canvasBounds.width * 0.42, 220), max(canvasBounds.width, 1))
      let height = min(max(canvasBounds.height * 0.18, 72), max(canvasBounds.height, 1))
      let origin = CGPoint(
        x: min(max(center.x - width / 2, canvasBounds.minX), max(canvasBounds.maxX - width, canvasBounds.minX)),
        y: min(max(center.y - height / 2, canvasBounds.minY), max(canvasBounds.maxY - height, canvasBounds.minY))
      )
      return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    return drawnBounds.standardized
  }

  private static func normalizedHighlighterPath(_ path: [CGPoint], strokeWidth: CGFloat) -> [CGPoint] {
    guard path.count > 2,
          let first = path.first,
          let last = path.last else {
      return path
    }

    let dx = last.x - first.x
    let dy = last.y - first.y
    let length = hypot(dx, dy)
    guard length >= 24, abs(dx) >= 24 else { return path }

    let angle = abs(atan2(dy, dx))
    let angleFromHorizontal = min(angle, abs(.pi - angle))
    guard angleFromHorizontal <= 10 * .pi / 180 else { return path }

    let minY = path.map(\.y).min() ?? first.y
    let maxY = path.map(\.y).max() ?? first.y
    let maximumVerticalRange = max(8, strokeWidth * 3 * 0.6)
    guard maxY - minY <= maximumVerticalRange else { return path }

    let minX = path.map(\.x).min() ?? min(first.x, last.x)
    let maxX = path.map(\.x).max() ?? max(first.x, last.x)
    guard maxX - minX >= 24 else { return path }

    let y = medianY(in: path)
    return [
      CGPoint(x: minX, y: y),
      CGPoint(x: maxX, y: y),
    ]
  }

  private static func medianY(in path: [CGPoint]) -> CGFloat {
    let values = path.map(\.y).sorted()
    guard !values.isEmpty else { return 0 }

    let midpoint = values.count / 2
    if values.count.isMultiple(of: 2) {
      return (values[midpoint - 1] + values[midpoint]) / 2
    }
    return values[midpoint]
  }

  private static func pathBounds(containing points: [CGPoint]) -> CGRect? {
    guard let first = points.first else { return nil }

    var minX = first.x
    var maxX = first.x
    var minY = first.y
    var maxY = first.y

    for point in points.dropFirst() {
      minX = min(minX, point.x)
      maxX = max(maxX, point.x)
      minY = min(minY, point.y)
      maxY = max(maxY, point.y)
    }

    return normalizedBounds(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
  }

  private static func normalizedBounds(_ rect: CGRect, minimumDimension: CGFloat = 1) -> CGRect {
    var normalized = rect.standardized

    if normalized.width < minimumDimension {
      normalized.origin.x -= (minimumDimension - normalized.width) / 2
      normalized.size.width = minimumDimension
    }

    if normalized.height < minimumDimension {
      normalized.origin.y -= (minimumDimension - normalized.height) / 2
      normalized.size.height = minimumDimension
    }

    return normalized
  }
}
