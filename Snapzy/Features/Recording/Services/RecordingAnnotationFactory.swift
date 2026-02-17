//
//  RecordingAnnotationFactory.swift
//  Snapzy
//
//  Factory for creating annotations during recording
//  Adapts AnnotationFactory to work with RecordingAnnotationState
//

import CoreGraphics
import SwiftUI

enum RecordingAnnotationFactory {

  static func createAnnotation(
    tool: AnnotationToolType,
    from start: CGPoint,
    to end: CGPoint,
    path: [CGPoint],
    strokeColor: Color,
    strokeWidth: CGFloat
  ) -> AnnotationItem? {

    let properties = AnnotationProperties(
      strokeColor: strokeColor,
      fillColor: .clear,
      strokeWidth: strokeWidth
    )

    let bounds = CGRect(
      x: min(start.x, end.x),
      y: min(start.y, end.y),
      width: abs(end.x - start.x),
      height: abs(end.y - start.y)
    )

    let type: AnnotationType?

    switch tool {
    case .rectangle:
      type = .rectangle
    case .oval:
      type = .oval
    case .arrow:
      type = .arrow(start: start, end: end)
    case .line:
      type = .line(start: start, end: end)
    case .pencil:
      guard path.count > 1 else { return nil }
      type = .path(path)
    case .highlighter:
      guard path.count > 1 else { return nil }
      type = .highlight(path)
    default:
      return nil
    }

    guard let annotationType = type else { return nil }
    return AnnotationItem(type: annotationType, bounds: bounds, properties: properties)
  }
}
