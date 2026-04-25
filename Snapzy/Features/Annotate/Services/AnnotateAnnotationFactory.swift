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

  static func createAnnotation(
    tool: AnnotationToolType,
    from start: CGPoint,
    to end: CGPoint,
    path: [CGPoint],
    state: AnnotateState
  ) -> AnnotationItem? {

    let properties = state.annotationCreationProperties(for: tool)

    let type: AnnotationType?

    switch tool {
    case .rectangle:
      type = .rectangle

    case .filledRectangle:
      type = .filledRectangle

    case .oval:
      type = .oval

    case .arrow:
      type = .arrow(ArrowGeometry(start: start, end: end, style: state.arrowStyle))

    case .line:
      type = .line(start: start, end: end)

    case .pencil:
      guard path.count > 1 else { return nil }
      type = .path(path)

    case .highlighter:
      guard path.count > 1 else { return nil }
      type = .highlight(path)

    case .blur:
      type = .blur(state.blurType)

    case .counter:
      type = .counter(state.nextCounterValue())

    case .watermark:
      let text = state.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        imageSize: CGSize(width: state.imageWidth, height: state.imageHeight)
      )
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
    imageSize: CGSize
  ) -> CGRect {
    guard drawnBounds.width >= 24, drawnBounds.height >= 24 else {
      let width = min(max(imageSize.width * 0.42, 220), max(imageSize.width, 1))
      let height = min(max(imageSize.height * 0.18, 72), max(imageSize.height, 1))
      let origin = CGPoint(
        x: min(max(center.x - width / 2, 0), max(imageSize.width - width, 0)),
        y: min(max(center.y - height / 2, 0), max(imageSize.height - height, 0))
      )
      return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    return drawnBounds.standardized
  }
}
