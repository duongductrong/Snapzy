//
//  OCRTextLayoutFormatter.swift
//  Snapzy
//
//  Rebuilds readable text from Vision's line observations while keeping the
//  source layout: paragraphs, list items, and intentional line breaks.
//

import CoreGraphics
import Foundation

/// Turns ordered OCR lines (Vision normalized boxes, origin bottom-left) into text.
///
/// Steps:
/// 1. Drop cut-off glyphs at the right edge of the selection.
/// 2. Merge observations on the same visual row.
/// 3. Split rows into paragraphs by vertical gap.
/// 4. Inside a paragraph, keep each list item (`•`, `-`, `1.`, …) on its own
///    line and join its wrapped continuation rows; reflow plain prose but keep
///    a hard break after a short row that ends a sentence.
nonisolated struct OCRTextLayoutFormatter {
  /// Image width / height. Converts normalized x into height units so
  /// horizontal thresholds can be compared with row heights.
  let aspectRatio: CGFloat
  /// The user's OCR language is CJK (joins wrapped rows without spaces).
  let prefersCJK: Bool

  init(imageSize: CGSize, prefersCJK: Bool) {
    aspectRatio = imageSize.height > 0 ? imageSize.width / imageSize.height : 1
    self.prefersCJK = prefersCJK
  }

  func format(_ lines: [OCRTextLine]) -> String {
    let rows = mergeRows(droppingEdgeFragments(from: lines))
    return groupParagraphs(rows)
      .map(formatParagraph)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
  }

  // MARK: - Rows

  struct Row {
    var text: String
    var box: CGRect
  }

  /// A one-glyph observation touching the right edge, sharing a row with real
  /// text, is a character clipped by the selection (e.g. "P" from "picker").
  private func droppingEdgeFragments(from lines: [OCRTextLine]) -> [OCRTextLine] {
    guard lines.count > 1 else { return lines }
    return lines.filter { line in
      let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard text.count <= 1, line.boundingBox.minX >= 0.95 else { return true }
      let sharesRow = lines.contains { other in
        other.boundingBox != line.boundingBox
          && other.boundingBox.maxX < line.boundingBox.minX
          && Self.isSameRow(other.boundingBox, line.boundingBox)
      }
      return !sharesRow
    }
  }

  /// Lines arrive in reading order (row by row, left to right).
  private func mergeRows(_ lines: [OCRTextLine]) -> [Row] {
    var rows: [Row] = []
    for line in lines {
      let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      if var last = rows.last, Self.isSameRow(last.box, line.boundingBox) {
        last.text = join(last.text, text)
        last.box = last.box.union(line.boundingBox)
        rows[rows.count - 1] = last
      } else {
        rows.append(Row(text: text, box: line.boundingBox))
      }
    }
    return rows
  }

  private static func isSameRow(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.midY - rhs.midY) <= max(lhs.height, rhs.height) * 0.6
  }

  // MARK: - Paragraphs

  private func groupParagraphs(_ rows: [Row]) -> [[Row]] {
    guard let first = rows.first else { return [] }

    let averageHeight = rows.map(\.box.height).reduce(0, +) / CGFloat(rows.count)
    var paragraphs: [[Row]] = []
    var current = [first]

    for row in rows.dropFirst() {
      guard let previous = current.last else { continue }
      let gap = previous.box.minY - row.box.maxY
      let threshold = max(averageHeight * 0.75, max(previous.box.height, row.box.height) * 0.68)
      if gap > threshold {
        paragraphs.append(current)
        current = [row]
      } else {
        current.append(row)
      }
    }
    paragraphs.append(current)
    return paragraphs
  }

  private enum BlockKind {
    case listItem
    case prose
  }

  private struct Block {
    let kind: BlockKind
    var rows: [Row]
  }

  private func formatParagraph(_ rows: [Row]) -> String {
    let blocks = splitBlocks(rows)
    let hasList = blocks.contains { $0.kind == .listItem }
    let paragraphMaxX = rows.map(\.box.maxX).max() ?? 0
    let paragraphMinX = rows.map(\.box.minX).min() ?? 0

    return blocks.map { block -> String in
      switch block.kind {
      case .listItem:
        return Self.normalizingBulletMarker(reflow(block.rows))
      case .prose:
        // Labels and short stacked lines (menus, UI) keep one row per line.
        guard hasList || shouldReflowProse(block.rows) else {
          return block.rows.map(\.text).joined(separator: "\n")
        }
        return reflowKeepingHardBreaks(
          block.rows,
          paragraphMinX: paragraphMinX,
          paragraphMaxX: paragraphMaxX
        )
      }
    }
    .joined(separator: "\n")
  }

  /// A list marker starts a new item. Rows after an item belong to it while
  /// they are indented past the item's left edge (a hanging indent).
  private func splitBlocks(_ rows: [Row]) -> [Block] {
    var blocks: [Block] = []
    for row in rows {
      if Self.startsWithListMarker(row.text) {
        blocks.append(Block(kind: .listItem, rows: [row]))
        continue
      }

      if var last = blocks.last {
        let continues: Bool
        switch last.kind {
        case .listItem:
          let indent = (row.box.minX - last.rows[0].box.minX) * aspectRatio
          continues = indent > row.box.height * 0.35
        case .prose:
          continues = true
        }
        if continues {
          last.rows.append(row)
          blocks[blocks.count - 1] = last
          continue
        }
      }
      blocks.append(Block(kind: .prose, rows: [row]))
    }
    return blocks
  }

  private func shouldReflowProse(_ rows: [Row]) -> Bool {
    guard rows.count > 1 else { return false }

    let averageWidth = rows.map(\.box.width).reduce(0, +) / CGFloat(rows.count)
    let text = rows.map(\.text).joined()
    if isLikelyCJK(text) {
      return averageWidth >= 0.24 || rows.count >= 3
    }
    let longestRow = rows.map { Self.meaningfulCharacterCount(in: $0.text) }.max() ?? 0
    return averageWidth >= 0.36 || longestRow >= 28 || rows.count >= 4
  }

  /// Joins wrapped rows, but keeps a line break after a row that ends a
  /// sentence well before the paragraph's right edge (ragged, intentional break).
  private func reflowKeepingHardBreaks(
    _ rows: [Row],
    paragraphMinX: CGFloat,
    paragraphMaxX: CGFloat
  ) -> String {
    let width = paragraphMaxX - paragraphMinX
    var lines: [[Row]] = []
    for row in rows {
      if let previous = lines.last?.last,
         Self.endsSentence(previous.text),
         previous.box.maxX < paragraphMaxX - width * 0.15 {
        lines.append([row])
      } else if lines.isEmpty {
        lines.append([row])
      } else {
        lines[lines.count - 1].append(row)
      }
    }
    return lines.map(reflow).joined(separator: "\n")
  }

  private func reflow(_ rows: [Row]) -> String {
    let isCJK = isLikelyCJK(rows.map(\.text).joined())
    return rows.reduce(into: "") { text, row in
      text = text.isEmpty ? row.text : join(text, row.text, cjk: isCJK)
    }
  }

  private func join(_ lhs: String, _ rhs: String, cjk: Bool? = nil) -> String {
    if cjk ?? isLikelyCJK(lhs + rhs) {
      return lhs + rhs
    }
    if lhs.hasSuffix("-"), let next = rhs.first, next.isLowercase {
      return String(lhs.dropLast()) + rhs
    }
    if let first = rhs.unicodeScalars.first, Self.leadingInlinePunctuation.contains(first) {
      return lhs + rhs
    }
    return lhs + " " + rhs
  }

  // MARK: - Text classification

  private static let leadingInlinePunctuation = CharacterSet(charactersIn: ",.;:!?)]}%")
  private static let sentenceTerminators: Set<Character> = [".", "!", "?", ":", "。", "！", "？", "：", "…"]

  private static let listMarkerPattern = try? NSRegularExpression(
    pattern: #"^\s*(?:[•·▪▫◦‣●○■□➢➤►▶✓✔☐☑]\s*|[-–—*+]\s+|\(?\d{1,3}[.)]\s+|\(?[a-z][.)]\s+|[①-⑳])"#
  )

  static func startsWithListMarker(_ text: String) -> Bool {
    guard let pattern = listMarkerPattern else { return false }
    let range = NSRange(text.startIndex..., in: text)
    return pattern.firstMatch(in: text, range: range) != nil
  }

  /// Symbol bullets (round, square, arrows, checks, dashes) whose OCR'd glyph
  /// rarely matches the source font. Numbered markers are kept as-is.
  private static let symbolBulletPattern = try? NSRegularExpression(
    pattern: #"^\s*(?:[•·▪▫◦‣●○■□➢➤►▶✓✔☐☑]\s*|[-–—*+]\s+)"#
  )

  /// Rewrites a leading symbol bullet as a Markdown-style "- ".
  static func normalizingBulletMarker(_ text: String) -> String {
    guard let pattern = symbolBulletPattern else { return text }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = pattern.firstMatch(in: text, range: range),
          let markerRange = Range(match.range, in: text) else { return text }
    return "- " + text[markerRange.upperBound...]
  }

  private static func endsSentence(_ text: String) -> Bool {
    guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
    return sentenceTerminators.contains(last)
  }

  private func isLikelyCJK(_ text: String) -> Bool {
    prefersCJK || Self.cjkCharacterCount(in: text) >= max(6, Self.meaningfulCharacterCount(in: text) / 3)
  }

  private static func meaningfulCharacterCount(in text: String) -> Int {
    text.unicodeScalars.reduce(into: 0) { count, scalar in
      if CharacterSet.alphanumerics.contains(scalar) || isCJKScalar(scalar) {
        count += 1
      }
    }
  }

  private static func cjkCharacterCount(in text: String) -> Int {
    text.unicodeScalars.reduce(into: 0) { count, scalar in
      if isCJKScalar(scalar) { count += 1 }
    }
  }

  /// Han, Kana and Hangul.
  private static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
         0x3040...0x309F, 0x30A0...0x30FF,
         0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
      return true
    default:
      return false
    }
  }
}

// MARK: - Layout blocks

/// A run of text that belongs together on screen (a paragraph, a list item or a
/// single label), with its position. Boxes are Vision-normalized (bottom-left origin).
nonisolated struct OCRTextBlock: Equatable {
  let text: String
  let box: CGRect
  let rowBoxes: [CGRect]

  /// Average height of one visual row, normalized.
  var rowHeight: CGFloat {
    guard !rowBoxes.isEmpty else { return box.height }
    return rowBoxes.map(\.height).reduce(0, +) / CGFloat(rowBoxes.count)
  }
}

extension OCRTextLayoutFormatter {
  /// Groups ordered OCR lines into positioned blocks for overlay use (Annotate Auto
  /// Translate). Unlike `format(_:)`, it never joins text across columns or across
  /// horizontally separated labels, so each block covers only its own text.
  /// `format(_:)` is untouched; this is a separate path.
  func blocks(_ lines: [OCRTextLine]) -> [OCRTextBlock] {
    let rows = mergeLayoutRows(droppingEdgeFragments(from: lines))
    return groupLayoutParagraphs(rows).flatMap(layoutBlocks(in:))
  }

  /// Same-row observations merge only when they are close horizontally
  /// (a tab bar's labels stay apart).
  private func mergeLayoutRows(_ lines: [OCRTextLine]) -> [Row] {
    var rows: [Row] = []
    for line in lines {
      let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      if var last = rows.last, Self.isSameRow(last.box, line.boundingBox) {
        let gap = (line.boundingBox.minX - last.box.maxX) * aspectRatio
        let height = max(last.box.height, line.boundingBox.height)
        if gap <= height * 1.2 {
          last.text = join(last.text, text)
          last.box = last.box.union(line.boundingBox)
          rows[rows.count - 1] = last
          continue
        }
      }
      rows.append(Row(text: text, box: line.boundingBox))
    }
    return rows
  }

  /// A row joins the paragraph whose last row sits right above it, overlaps it
  /// horizontally and has a similar height (headings and other columns stay apart).
  private func groupLayoutParagraphs(_ rows: [Row]) -> [[Row]] {
    var paragraphs: [[Row]] = []
    for row in rows {
      let index = paragraphs.lastIndex { paragraph in
        guard let previous = paragraph.last else { return false }
        let height = max(previous.box.height, row.box.height)
        let gap = previous.box.minY - row.box.maxY
        guard gap >= -height * 0.3, gap <= height * 0.75 else { return false }
        let ratio = max(previous.box.height, row.box.height) / max(min(previous.box.height, row.box.height), .ulpOfOne)
        guard ratio <= 1.4 else { return false }
        let overlap = min(previous.box.maxX, row.box.maxX) - max(previous.box.minX, row.box.minX)
        let leftAligned = abs(previous.box.minX - row.box.minX) * aspectRatio <= height * 1.5
        return overlap > 0 && (leftAligned || overlap >= min(previous.box.width, row.box.width) * 0.6)
      }
      if let index {
        paragraphs[index].append(row)
      } else {
        paragraphs.append([row])
      }
    }
    return paragraphs
  }

  private func layoutBlocks(in rows: [Row]) -> [OCRTextBlock] {
    let blocks = splitBlocks(rows)
    let hasList = blocks.contains { $0.kind == .listItem }
    let paragraphMinX = rows.map(\.box.minX).min() ?? 0
    let paragraphMaxX = rows.map(\.box.maxX).max() ?? 0

    return blocks.flatMap { block -> [OCRTextBlock] in
      switch block.kind {
      case .listItem:
        return [Self.makeBlock(text: reflow(block.rows), rows: block.rows)]
      case .prose:
        guard hasList || shouldReflowProse(block.rows) else {
          return block.rows.map { Self.makeBlock(text: $0.text, rows: [$0]) }
        }
        let text = reflowKeepingHardBreaks(
          block.rows,
          paragraphMinX: paragraphMinX,
          paragraphMaxX: paragraphMaxX
        )
        return [Self.makeBlock(text: text, rows: block.rows)]
      }
    }
  }

  private static func makeBlock(text: String, rows: [Row]) -> OCRTextBlock {
    let box = rows.reduce(CGRect.null) { $0.union($1.box) }
    return OCRTextBlock(text: text, box: box, rowBoxes: rows.map(\.box))
  }
}
