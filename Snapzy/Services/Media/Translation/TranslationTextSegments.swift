//
//  TranslationTextSegments.swift
//  Snapzy
//
//  Splits OCR text into translatable lines and rebuilds the translated text
//  with the original line/paragraph layout.
//

import Foundation

/// OCR text is already reflowed into paragraphs (`OCRService.formatText`):
/// paragraphs are separated by blank lines, and lines that were not reflowed
/// (lists, UI labels) stay on their own line. Translating each non-empty line
/// separately keeps that structure exactly in the output.
struct TranslationTextSegments: Equatable {
  /// Original lines, including empty ones.
  let lines: [String]

  init(text: String) {
    lines = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .components(separatedBy: "\n")
  }

  /// Indices into `lines` that carry text to translate.
  var translatableIndices: [Int] {
    lines.indices.filter { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
  }

  var translatableTexts: [String] {
    translatableIndices.map { lines[$0].trimmingCharacters(in: .whitespaces) }
  }

  var isEmpty: Bool {
    translatableIndices.isEmpty
  }

  /// Rebuilds the text, replacing each translatable line (in order) with its
  /// translation. Missing translations keep the original line.
  func rebuilt(with translations: [String]) -> String {
    var output = lines
    for (position, index) in translatableIndices.enumerated() where position < translations.count {
      output[index] = translations[position]
    }
    return output.joined(separator: "\n")
  }
}
