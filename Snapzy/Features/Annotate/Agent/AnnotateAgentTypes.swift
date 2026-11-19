//
//  AnnotateAgentTypes.swift
//  Snapzy
//
//  Shared vocabulary of the Annotate AI prompt: how an agent names a place on the
//  image (`AnnotateAgentTarget`), colors, tool results, and the coordinate rules.
//
//  Agent space: image units (the same units as `AnnotationItem.bounds`, i.e. the
//  image's point size) with a TOP-LEFT origin, y growing downward. Annotate space is
//  bottom-left. Conversion happens only in `AnnotateAgentCoordinates`.
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Coordinates

nonisolated enum AnnotateAgentCoordinates {
  /// Agent (top-left) rect → annotate (bottom-left) rect. The flip is its own inverse.
  static func annotateRect(fromAgent rect: CGRect, imageHeight: CGFloat) -> CGRect {
    VisionImageGeometry.flippedVertically(rect, imageHeight: imageHeight)
  }

  static func agentRect(fromAnnotate rect: CGRect, imageHeight: CGFloat) -> CGRect {
    VisionImageGeometry.flippedVertically(rect, imageHeight: imageHeight)
  }

  static func annotatePoint(fromAgent point: CGPoint, imageHeight: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: imageHeight - point.y)
  }

  static func agentPoint(fromAnnotate point: CGPoint, imageHeight: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: imageHeight - point.y)
  }
}

/// Rect encoded as `[x, y, width, height]` with whole numbers — compact for small context windows.
nonisolated struct AnnotateAgentRect: Equatable, Codable {
  var rect: CGRect

  init(_ rect: CGRect) {
    self.rect = rect
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode([rect.minX, rect.minY, rect.width, rect.height].map { Int($0.rounded()) })
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.singleValueContainer().decode([Double].self)
    guard values.count == 4 else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected [x, y, width, height]"))
    }
    rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
  }
}

// MARK: - Target

/// Where an agent wants something. Models are poor at guessing numbers, so the
/// preferred forms are references to things the scene already lists.
nonisolated enum AnnotateAgentTarget: Equatable {
  /// Matches an OCR text block (case/diacritic insensitive).
  case text(String)
  /// `t3` (text block), `e2` (UI element), `a5` (annotation).
  case reference(String)
  /// Agent space.
  case rect(CGRect)
  /// Agent space.
  case point(CGPoint)

  /// `t12`, `e3`, `a7`.
  static func isReference(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    guard let prefix = trimmed.first, "tea".contains(prefix), trimmed.count > 1 else { return false }
    return trimmed.dropFirst().allSatisfy(\.isNumber)
  }
}

extension AnnotateAgentTarget: Decodable {
  private enum Keys: String, CodingKey {
    case text, id, block, element, annotation, rect, point, x, y, width, height
  }

  /// Accepts `{"text": …}`, `{"id"|"block"|"element"|"annotation": "t3"}`, `{"rect": [x,y,w,h]}`,
  /// `{"point": [x,y]}`, `{"x":…, "y":…, "width"?:…, "height"?:…}`, a bare string (id or text),
  /// or a bare `[x, y]` / `[x, y, w, h]` array.
  init(from decoder: Decoder) throws {
    if let single = try? decoder.singleValueContainer() {
      if let string = try? single.decode(String.self) {
        self = Self.fromString(string)
        return
      }
      if let numbers = try? single.decode([Double].self), let target = Self.fromNumbers(numbers) {
        self = target
        return
      }
    }

    let container = try decoder.container(keyedBy: Keys.self)
    for key in [Keys.id, .block, .element, .annotation] {
      if let reference = try container.decodeIfPresent(String.self, forKey: key) {
        self = .reference(reference.trimmingCharacters(in: .whitespaces))
        return
      }
    }
    if let text = try container.decodeIfPresent(String.self, forKey: .text) {
      self = .text(text)
      return
    }
    if let numbers = try container.decodeIfPresent([Double].self, forKey: .rect),
       numbers.count == 4, let target = Self.fromNumbers(numbers) {
      self = target
      return
    }
    if let numbers = try container.decodeIfPresent([Double].self, forKey: .point),
       numbers.count == 2, let target = Self.fromNumbers(numbers) {
      self = target
      return
    }
    if let x = try container.decodeIfPresent(Double.self, forKey: .x),
       let y = try container.decodeIfPresent(Double.self, forKey: .y) {
      let width = try container.decodeIfPresent(Double.self, forKey: .width)
      let height = try container.decodeIfPresent(Double.self, forKey: .height)
      if let width, let height {
        self = .rect(CGRect(x: x, y: y, width: width, height: height))
      } else {
        self = .point(CGPoint(x: x, y: y))
      }
      return
    }
    throw DecodingError.dataCorrupted(.init(
      codingPath: decoder.codingPath,
      debugDescription: "Target needs one of: text, id, rect [x,y,w,h], point [x,y]"
    ))
  }

  private static func fromString(_ string: String) -> AnnotateAgentTarget {
    isReference(string) ? .reference(string.trimmingCharacters(in: .whitespaces)) : .text(string)
  }

  private static func fromNumbers(_ numbers: [Double]) -> AnnotateAgentTarget? {
    guard numbers.allSatisfy(\.isFinite) else { return nil }
    switch numbers.count {
    case 2: return .point(CGPoint(x: numbers[0], y: numbers[1]))
    case 4: return .rect(CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
    default: return nil
    }
  }
}

// MARK: - Colors

nonisolated enum AnnotateAgentColor {
  static let names: [(String, NSColor)] = [
    ("red", .systemRed),
    ("orange", .systemOrange),
    ("yellow", .systemYellow),
    ("green", .systemGreen),
    ("mint", .systemMint),
    ("teal", .systemTeal),
    ("cyan", .systemCyan),
    ("blue", .systemBlue),
    ("indigo", .systemIndigo),
    ("purple", .systemPurple),
    ("pink", .systemPink),
    ("brown", .systemBrown),
    ("gray", .systemGray),
    ("black", .black),
    ("white", .white),
  ]

  static var validValuesDescription: String {
    names.map(\.0).joined(separator: ", ") + ", or #RRGGBB"
  }

  /// Named color (`red`, `grey`, `Blue`) or `#RRGGBB` / `#RRGGBBAA` / `RRGGBB`.
  static func parse(_ raw: String) -> Color? {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value == "grey" { value = "gray" }
    if let named = names.first(where: { $0.0 == value }) {
      return Color(nsColor: named.1)
    }
    if !value.hasPrefix("#"), value.count == 6 || value.count == 8, UInt64(value, radix: 16) != nil {
      value = "#" + value
    }
    return SnapzyConfigurationColor.color(from: value.uppercased()).map { Color(nsColor: $0) }
  }

  /// Closest name when the color is one of ours, else hex.
  static func describe(_ color: Color) -> String {
    let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
    if nsColor.alphaComponent < 0.01 { return "clear" }
    for (name, candidate) in names {
      guard let srgb = candidate.usingColorSpace(.sRGB) else { continue }
      if abs(srgb.redComponent - nsColor.redComponent) < 0.02,
         abs(srgb.greenComponent - nsColor.greenComponent) < 0.02,
         abs(srgb.blueComponent - nsColor.blueComponent) < 0.02 {
        return name
      }
    }
    return SnapzyConfigurationColor.hexString(from: nsColor)
  }
}

// MARK: - Results & errors

extension AgentToolResult {
  static func failure(_ error: AnnotateAgentToolError) -> AgentToolResult {
    .failure(message: error.message)
  }
}

/// Errors are written for the model: each says what to do instead.
nonisolated enum AnnotateAgentToolError: Error, Equatable {
  case unknownTool(String)
  case invalidArguments(String)
  case targetNotFound(String)
  case unavailable(String)
  case limitReached(Int)

  var message: String {
    switch self {
    case .unknownTool(let name):
      return "Unknown tool '\(name)'. Use one of: \(AnnotateAgentToolName.allCases.map(\.rawValue).joined(separator: ", "))."
    case .invalidArguments(let detail):
      return "Invalid arguments: \(detail)"
    case .targetNotFound(let detail):
      return "Target not found: \(detail). Call get_scene or find_text and use an id like t3, e2 or a5."
    case .unavailable(let detail):
      return detail
    case .limitReached(let limit):
      return "This request already made \(limit) changes, the limit for one request. Stop and summarize."
    }
  }
}

// MARK: - Events

/// Live feedback for the canvas overlay while a run is in flight (annotate space).
nonisolated enum AnnotateAgentToolboxEvent: Equatable {
  case targetResolved(CGRect)
  case annotationAdded(UUID)
  case annotationsUpdated([UUID])
  case annotationsRemoved([UUID])
  case canvasChanged
}
