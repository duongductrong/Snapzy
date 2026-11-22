//
//  AnnotateAgentScene.swift
//  Snapzy
//
//  What the agent "sees": text blocks and UI elements found on the image, the
//  annotations already on the canvas, the selection and the canvas settings.
//
//  The image analysis (OCR + rectangles) is slow and depends only on the image, so it
//  runs once per image (`AnnotateAgentImageAnalysis`). The scene is rebuilt from it
//  plus live state on every request, because the user may edit between prompts.
//

import AppKit
import CoreGraphics
import Foundation
import Vision

// MARK: - Image analysis (annotate space)

nonisolated struct AnnotateAgentImageAnalysis: Equatable {
  struct TextBlock: Equatable {
    let text: String
    /// Annotate space (bottom-left).
    let bounds: CGRect
    /// One rect per visual row, annotate space.
    let rows: [CGRect]
  }

  var textBlocks: [TextBlock]
  /// Rectangular UI regions (buttons, cards, fields), annotate space.
  var elements: [CGRect]

  static let empty = AnnotateAgentImageAnalysis(textBlocks: [], elements: [])

  static let maximumElements = 24

  /// Runs Vision on the whole image. Never throws: a failed pass yields fewer facts, not an error.
  /// OCR and rectangle detection run off the main actor; only setup and results touch it.
  @MainActor
  static func analyze(image: NSImage, languageIdentifier: String?) async -> AnnotateAgentImageAnalysis {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .empty }
    let imageSize = image.size.width > 0 && image.size.height > 0
      ? image.size
      : CGSize(width: cgImage.width, height: cgImage.height)

    var blocks: [TextBlock] = []
    if let result = try? await OCRService.shared.recognizeLayout(
      OCRRequest(image: cgImage, preferredLanguageIdentifier: languageIdentifier, contentType: .interfaceText)
    ) {
      let prefersCJK = ["ja", "ko", "zh-Hans", "zh-Hant"]
        .contains(AppLanguageManager.normalizedLanguageIdentifier(from: languageIdentifier) ?? "")
      let formatter = OCRTextLayoutFormatter(
        imageSize: CGSize(width: cgImage.width, height: cgImage.height),
        prefersCJK: prefersCJK
      )
      blocks = textBlocks(from: formatter.blocks(result.lines), imageSize: imageSize)
    }

    let rectangles = await Task.detached(priority: .userInitiated) {
      detectRectangles(in: cgImage)
    }.value
    let elements = elements(
      fromVisionBoxes: rectangles,
      imageSize: imageSize,
      textBounds: blocks.map(\.bounds)
    )
    return AnnotateAgentImageAnalysis(textBlocks: blocks, elements: elements)
  }

  /// Vision blocks (normalized, bottom-left) → annotate space, in reading order.
  static func textBlocks(from blocks: [OCRTextBlock], imageSize: CGSize) -> [TextBlock] {
    blocks.compactMap { block in
      let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      let bounds = VisionImageGeometry.annotateRect(fromVisionBoundingBox: block.box, imageSize: imageSize)
      guard bounds.width >= 2, bounds.height >= 2 else { return nil }
      let rows = block.rowBoxes.map {
        VisionImageGeometry.annotateRect(fromVisionBoundingBox: $0, imageSize: imageSize)
      }
      return TextBlock(text: text, bounds: bounds, rows: rows.isEmpty ? [bounds] : rows)
    }
  }

  /// Keeps plausible UI regions: not tiny, not the whole image, not just a text box, no duplicates.
  static func elements(fromVisionBoxes boxes: [CGRect], imageSize: CGSize, textBounds: [CGRect]) -> [CGRect] {
    let imageArea = max(imageSize.width * imageSize.height, 1)
    var kept: [CGRect] = []
    let sorted = boxes
      .map { VisionImageGeometry.annotateRect(fromVisionBoundingBox: $0, imageSize: imageSize) }
      .sorted { $0.width * $0.height > $1.width * $1.height }
    for rect in sorted {
      let area = rect.width * rect.height
      guard rect.width >= 16, rect.height >= 12, area / imageArea < 0.85 else { continue }
      if textBounds.contains(where: { intersectionOverUnion($0, rect) > 0.6 }) { continue }
      if kept.contains(where: { intersectionOverUnion($0, rect) > 0.7 }) { continue }
      kept.append(rect)
      if kept.count == maximumElements { break }
    }
    // Reading order: top to bottom (annotate y grows upward), then left to right.
    return kept.sorted {
      abs($0.maxY - $1.maxY) > 8 ? $0.maxY > $1.maxY : $0.minX < $1.minX
    }
  }

  static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull else { return 0 }
    let inter = intersection.width * intersection.height
    let union = lhs.width * lhs.height + rhs.width * rhs.height - inter
    return union > 0 ? inter / union : 0
  }

  private static func detectRectangles(in image: CGImage) -> [CGRect] {
    let request = VNDetectRectanglesRequest()
    request.maximumObservations = 32
    request.minimumSize = 0.02
    request.minimumAspectRatio = 0.08
    request.maximumAspectRatio = 1
    request.quadratureTolerance = 12
    request.minimumConfidence = 0.5
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }
    return (request.results ?? []).map(\.boundingBox)
  }
}

// MARK: - Text matching

nonisolated enum AnnotateAgentTextMatcher {
  static func normalized(_ text: String) -> String {
    text
      .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
      // Đ/đ is its own letter in Unicode, not D + mark, so diacritic folding keeps it.
      .replacingOccurrences(of: "đ", with: "d")
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  /// Indices of matching blocks, best first. Exact > block contains query (shorter block wins)
  /// > query contains block.
  static func matches(_ query: String, in texts: [String]) -> [Int] {
    let needle = normalized(query)
    guard !needle.isEmpty else { return [] }
    var scored: [(index: Int, score: Int, length: Int)] = []
    for (index, text) in texts.enumerated() {
      let hay = normalized(text)
      guard !hay.isEmpty else { continue }
      if hay == needle {
        scored.append((index, 3, hay.count))
      } else if hay.contains(needle) {
        scored.append((index, 2, hay.count))
      } else if hay.count >= 3, needle.contains(hay) {
        scored.append((index, 1, -hay.count))
      }
    }
    return scored
      .sorted { $0.score != $1.score ? $0.score > $1.score : $0.length < $1.length }
      .map(\.index)
  }
}

// MARK: - Scene (agent space)

nonisolated struct AnnotateAgentScene: Equatable, Encodable {
  struct ImageSize: Equatable, Encodable {
    let width: Int
    let height: Int
  }

  struct Text: Equatable, Encodable {
    let id: String
    let text: String
    let rect: AnnotateAgentRect
  }

  struct Element: Equatable, Encodable {
    let id: String
    let rect: AnnotateAgentRect
  }

  struct Annotation: Equatable, Encodable {
    let id: String
    let type: String
    let rect: AnnotateAgentRect
    let color: String?
    let text: String?
  }

  struct Canvas: Equatable, Encodable {
    let background: String
    let padding: Int
    let inset: Int
    let shadow: Double
    let cornerRadius: Int
    let alignment: String
  }

  let coordinates = "image units, origin top-left, rect = [x, y, width, height]"
  let image: ImageSize
  var texts: [Text]
  var elements: [Element]
  var annotations: [Annotation]
  var selection: [String]
  var canvas: Canvas

  /// Keeps the scene inside a small context window: fewer blocks, shorter text.
  func compacted(maximumTexts: Int, maximumTextLength: Int) -> AnnotateAgentScene {
    var copy = self
    copy.texts = texts.prefix(maximumTexts).map {
      Text(id: $0.id, text: String($0.text.prefix(maximumTextLength)), rect: $0.rect)
    }
    copy.elements = Array(elements.prefix(max(maximumTexts / 3, 4)))
    return copy
  }

  private enum CodingKeys: String, CodingKey {
    case coordinates, image, texts, elements, annotations, selection, canvas
  }
}

extension AnnotationType {
  /// Stable snake_case name shown to agents.
  nonisolated var agentTypeName: String {
    switch self {
    case .path: "pencil"
    case .rectangle: "box"
    case .filledRectangle: "filled_box"
    case .oval: "oval"
    case .arrow: "arrow"
    case .line: "line"
    case .text: "text"
    case .highlight: "highlight"
    case .blur: "blur"
    case .counter: "counter"
    case .watermark: "watermark"
    case .embeddedImage: "image"
    case .spotlight: "spotlight"
    case .measurement: "measure"
    case .magnifier: "magnifier"
    case .translation: "translation"
    case .stamp: "stamp"
    }
  }
}
