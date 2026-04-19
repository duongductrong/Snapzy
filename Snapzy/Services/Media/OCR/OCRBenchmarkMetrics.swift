//
//  OCRBenchmarkMetrics.swift
//  Snapzy
//
//  Shared benchmark metrics for OCR tuning work.
//

import Foundation

struct OCRBenchmarkSample {
  let languageIdentifier: String
  let expectedText: String
  let recognizedText: String
  let confidence: Float
  let latencyMs: Double
}

struct OCRBenchmarkSummary {
  let languageIdentifier: String
  let sampleCount: Int
  let averageCharacterAccuracy: Double
  let exactMatchRate: Double
  let noOutputRate: Double
  let averageConfidence: Double
  let averageLatencyMs: Double
}

enum OCRBenchmarkMetrics {
  static func summarize(_ samples: [OCRBenchmarkSample]) -> [OCRBenchmarkSummary] {
    let grouped = Dictionary(grouping: samples, by: \.languageIdentifier)

    return grouped.keys.sorted().compactMap { languageIdentifier in
      guard let languageSamples = grouped[languageIdentifier], !languageSamples.isEmpty else { return nil }

      let characterAccuracy = languageSamples.map {
        normalizedAccuracy(expected: $0.expectedText, recognized: $0.recognizedText)
      }
      let exactMatches = languageSamples.filter {
        normalized($0.expectedText) == normalized($0.recognizedText)
      }.count
      let noOutputCount = languageSamples.filter {
        normalized($0.recognizedText).isEmpty
      }.count

      return OCRBenchmarkSummary(
        languageIdentifier: languageIdentifier,
        sampleCount: languageSamples.count,
        averageCharacterAccuracy: characterAccuracy.reduce(0, +) / Double(languageSamples.count),
        exactMatchRate: Double(exactMatches) / Double(languageSamples.count),
        noOutputRate: Double(noOutputCount) / Double(languageSamples.count),
        averageConfidence: languageSamples.map { Double($0.confidence) }.reduce(0, +) / Double(languageSamples.count),
        averageLatencyMs: languageSamples.map(\.latencyMs).reduce(0, +) / Double(languageSamples.count)
      )
    }
  }

  static func normalized(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func normalizedAccuracy(expected: String, recognized: String) -> Double {
    let expectedCharacters = Array(normalized(expected))
    let recognizedCharacters = Array(normalized(recognized))

    guard !expectedCharacters.isEmpty else {
      return recognizedCharacters.isEmpty ? 1 : 0
    }

    let distance = levenshtein(expectedCharacters, recognizedCharacters)
    return max(0, 1 - Double(distance) / Double(expectedCharacters.count))
  }

  private static func levenshtein<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
    if lhs.isEmpty { return rhs.count }
    if rhs.isEmpty { return lhs.count }

    var previous = Array(0...rhs.count)
    for (leftIndex, leftValue) in lhs.enumerated() {
      var current = Array(repeating: 0, count: rhs.count + 1)
      current[0] = leftIndex + 1
      for (rightIndex, rightValue) in rhs.enumerated() {
        let cost = leftValue == rightValue ? 0 : 1
        current[rightIndex + 1] = min(
          previous[rightIndex + 1] + 1,
          current[rightIndex] + 1,
          previous[rightIndex] + cost
        )
      }
      previous = current
    }

    return previous[rhs.count]
  }
}
