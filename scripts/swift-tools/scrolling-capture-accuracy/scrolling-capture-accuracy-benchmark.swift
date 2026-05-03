//
//  scrolling-capture-accuracy-benchmark.swift
//  Snapzy
//
//  Run from repository root:
//  ./scripts/run-scrolling-capture-accuracy-benchmark.sh
//

import Darwin
import Foundation

@main
private enum ScrollingCaptureAccuracyBenchmark {
  static func main() {
    let strict = ProcessInfo.processInfo.arguments.contains("--strict")
    let results = corpus().map(run)
    printReport(results)

    if strict, results.contains(where: { !$0.passed }) {
      exit(1)
    }
  }

  private static func corpus() -> [ScrollAccuracyBenchmarkCase] {
    [
      ScrollAccuracyBenchmarkCase(
        name: "clean-regular-delta",
        width: 280,
        viewportHeight: 360,
        contentHeight: 960,
        headerHeight: 0,
        footerHeight: 0,
        offsets: [0, 72, 144, 216, 288, 360, 432, 504],
        minimumOverallAccuracy: 0.999
      ),
      ScrollAccuracyBenchmarkCase(
        name: "clean-variable-delta",
        width: 320,
        viewportHeight: 420,
        contentHeight: 1_160,
        headerHeight: 0,
        footerHeight: 0,
        offsets: [0, 48, 112, 184, 260, 340, 420, 512],
        minimumOverallAccuracy: 0.999
      ),
      ScrollAccuracyBenchmarkCase(
        name: "sticky-header-footer",
        width: 340,
        viewportHeight: 430,
        contentHeight: 1_080,
        headerHeight: 48,
        footerHeight: 36,
        offsets: [0, 64, 128, 192, 256, 320, 384, 448],
        minimumOverallAccuracy: 0.995
      ),
      ScrollAccuracyBenchmarkCase(
        name: "small-steady-delta",
        width: 260,
        viewportHeight: 340,
        contentHeight: 800,
        headerHeight: 0,
        footerHeight: 0,
        offsets: [0, 24, 48, 72, 96, 120, 144, 168, 192],
        minimumOverallAccuracy: 0.999
      )
    ]
  }

  private static func run(_ benchmark: ScrollAccuracyBenchmarkCase) -> ScrollAccuracyBenchmarkResult {
    let stitcher = ScrollingCaptureStitcher()
    let frames = benchmark.offsets.compactMap { ScrollAccuracyFixture.frame(for: benchmark, offset: $0) }
    guard let first = frames.first, frames.count == benchmark.offsets.count else {
      return emptyFailure(for: benchmark)
    }

    _ = stitcher.start(with: first)
    var appendedCount = 0
    var failedCount = 0
    var confidenceTotal = 0.0
    var confidenceCount = 0
    var lastAcceptedOffset = benchmark.offsets[0]

    for index in 1..<frames.count {
      let expectedDelta = benchmark.offsets[index] - lastAcceptedOffset
      guard let update = stitcher.append(
        frames[index],
        maxOutputHeight: 32_768,
        expectedSignedDeltaPixels: expectedDelta,
        renderMergedImage: false
      ) else {
        failedCount += 1
        continue
      }

      if case .appended = update.outcome {
        appendedCount += 1
        lastAcceptedOffset = benchmark.offsets[index]
      }
      if case .ignoredAlignmentFailed = update.outcome { failedCount += 1 }
      if let confidence = update.alignmentDebug?.confidence {
        confidenceTotal += confidence
        confidenceCount += 1
      }
    }

    guard
      let merged = stitcher.mergedImage(),
      let expected = ScrollAccuracyFixture.expectedImage(for: benchmark),
      let outputRaster = ScrollAccuracyRGBA(cgImage: merged),
      let expectedRaster = ScrollAccuracyRGBA(cgImage: expected)
    else {
      return emptyFailure(for: benchmark)
    }

    let metrics = scrollAccuracyCompare(
      output: outputRaster,
      expected: expectedRaster,
      seamRows: ScrollAccuracyFixture.seamRows(for: benchmark)
    )
    let averageConfidence = confidenceCount > 0 ? confidenceTotal / Double(confidenceCount) : 0
    let passed = metrics.overallAccuracy >= benchmark.minimumOverallAccuracy
      && outputRaster.height == expectedRaster.height
      && failedCount == 0

    return ScrollAccuracyBenchmarkResult(
      name: benchmark.name,
      frameCount: frames.count,
      appendedCount: appendedCount,
      failedCount: failedCount,
      outputHeight: outputRaster.height,
      expectedHeight: expectedRaster.height,
      metrics: metrics,
      averageConfidence: averageConfidence,
      passed: passed
    )
  }

  private static func printReport(_ results: [ScrollAccuracyBenchmarkResult]) {
    print("Scroll Capture Accuracy Benchmark")
    print("| Case | Frames | Appended | Failures | Height | Exact | Overall | MAE | Seam MAE | Confidence | Status |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |")

    for result in results {
      print("| \(result.name) | \(result.frameCount) | \(result.appendedCount) | \(result.failedCount) | \(result.outputHeight)/\(result.expectedHeight) | \(percent(result.metrics.exactAccuracy)) | \(percent(result.metrics.overallAccuracy)) | \(number(result.metrics.meanAbsoluteError)) | \(number(result.metrics.maxSeamError)) | \(percent(result.averageConfidence)) | \(result.passed ? "pass" : "fail") |")
    }
  }
}
