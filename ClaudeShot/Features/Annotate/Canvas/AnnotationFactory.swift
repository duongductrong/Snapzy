//
//  AnnotationFactory.swift
//  ClaudeShot
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

    let properties = AnnotationProperties(
      strokeColor: state.strokeColor,
      fillColor: state.fillColor,
      strokeWidth: state.strokeWidth
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

    case .blur:
      type = .blur(state.blurType)

    case .counter:
      type = .counter(state.nextCounterValue())

    case .selection, .crop, .text, .mockup:
      return nil
    }

    guard let annotationType = type else { return nil }
    return AnnotationItem(type: annotationType, bounds: bounds, properties: properties)
  }
}
