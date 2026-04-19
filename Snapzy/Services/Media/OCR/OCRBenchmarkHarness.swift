//
//  OCRBenchmarkHarness.swift
//  Snapzy
//
//  Internal benchmark runner for Vision tuning and future hybrid evaluation.
//

import Foundation

struct OCRBenchmarkCase {
  let languageIdentifier: String
  let expectedText: String
  let request: OCRRequest
}

@MainActor
enum OCRBenchmarkHarness {
  typealias Recognizer = (OCRRequest) async throws -> OCRResult

  static func run(
    cases: [OCRBenchmarkCase],
    recognizer: Recognizer
  ) async -> [OCRBenchmarkSummary] {
    var samples: [OCRBenchmarkSample] = []

    for benchmarkCase in cases {
      let start = CFAbsoluteTimeGetCurrent()

      do {
        let result = try await recognizer(benchmarkCase.request)
        let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        samples.append(
          OCRBenchmarkSample(
            languageIdentifier: benchmarkCase.languageIdentifier,
            expectedText: benchmarkCase.expectedText,
            recognizedText: result.text,
            confidence: result.averageConfidence,
            latencyMs: latencyMs
          )
        )
      } catch {
        let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        samples.append(
          OCRBenchmarkSample(
            languageIdentifier: benchmarkCase.languageIdentifier,
            expectedText: benchmarkCase.expectedText,
            recognizedText: "",
            confidence: 0,
            latencyMs: latencyMs
          )
        )
      }
    }

    return OCRBenchmarkMetrics.summarize(samples)
  }
}
