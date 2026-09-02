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
        minimumOverallAccuracy: 0.90,
        allowIgnoredFrames: true
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
      ),
      ScrollAccuracyBenchmarkCase(
        name: "repeated-content-known-step",
        width: 280,
        viewportHeight: 360,
        contentHeight: 1_200,
        headerHeight: 0,
        footerHeight: 0,
        offsets: [0, 80, 160, 240, 320],
        minimumOverallAccuracy: 0.995,
        pattern: .repeatedBands,
        verifyEncodedRows: true
      ),
      ScrollAccuracyBenchmarkCase(
        name: "repeated-content-with-intermediate-frame",
        width: 280,
        viewportHeight: 360,
        contentHeight: 1_200,
        headerHeight: 0,
        footerHeight: 0,
        offsets: [0, 12, 80],
        minimumOverallAccuracy: 0.995,
        pattern: .repeatedBands,
        frameExpectations: [.append, .ignore, .append],
        expectedDeltas: [nil, 80, 80],
        verifyEncodedRows: true
      ),
      ScrollAccuracyBenchmarkCase(
        name: "skipped-band-regression",
        width: 280,
        viewportHeight: 360,
        contentHeight: 1_200,
        headerHeight: 0,
        footerHeight: 0,
        offsets: [0, 240],
        minimumOverallAccuracy: 0.995,
        pattern: .repeatedBands,
        frameExpectations: [.append, .ignore],
        expectedDeltas: [nil, 80],
        verifyEncodedRows: true
      ),
      ScrollAccuracyBenchmarkCase(
        name: "duplicate-section-regression",
        width: 280,
        viewportHeight: 360,
        contentHeight: 1_200,
        headerHeight: 0,
        footerHeight: 0,
        offsets: [0, 12],
        minimumOverallAccuracy: 0.995,
        pattern: .repeatedBands,
        frameExpectations: [.append, .ignore],
        expectedDeltas: [nil, 80],
        verifyEncodedRows: true
      ),
      ScrollAccuracyBenchmarkCase(
        name: "final-small-step-at-boundary",
        width: 280,
        viewportHeight: 360,
        contentHeight: 620,
        headerHeight: 0,
        footerHeight: 0,
        offsets: [0, 80, 160, 220],
        minimumOverallAccuracy: 0.995,
        pattern: .repeatedBands,
        verifyEncodedRows: true
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
    var unsafeAppendCount = 0
    var confidenceTotal = 0.0
    var confidenceCount = 0
    var lastAcceptedOffset = benchmark.offsets[0]
    let expectations = benchmark.frameExpectations

    for index in 1..<frames.count {
      let expectedDelta = benchmark.expectedDeltas?[index]
        ?? (benchmark.offsets[index] - lastAcceptedOffset)
      let expectation = expectations?[index] ?? .append
      guard let update = stitcher.append(
        frames[index],
        maxOutputHeight: 32_768,
        expectedSignedDeltaPixels: expectedDelta,
        renderMergedImage: false
      ) else {
        if case .append = expectation {
          failedCount += 1
        }
        continue
      }

      if case .appended = update.outcome {
        appendedCount += 1
        lastAcceptedOffset = benchmark.offsets[index]
        if case .ignore = expectation {
          unsafeAppendCount += 1
        }
      } else if case .append = expectation {
        failedCount += 1
      }
      if let confidence = update.alignmentDebug?.confidence {
        confidenceTotal += confidence
        confidenceCount += 1
      }
    }

    let expectedFinalOffset: Int
    if let expectations, case .ignore = expectations.last {
      expectedFinalOffset = lastAcceptedOffset
    } else {
      expectedFinalOffset = benchmark.offsets.last ?? lastAcceptedOffset
    }

    guard
      let merged = stitcher.mergedImage(),
      let expected = ScrollAccuracyFixture.expectedImage(for: benchmark, finalOffset: expectedFinalOffset),
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
    let encodedRowsOK = !benchmark.verifyEncodedRows || encodedRowsAreMonotonic(outputRaster)
    let averageConfidence = confidenceCount > 0 ? confidenceTotal / Double(confidenceCount) : 0
    let passed = metrics.overallAccuracy >= benchmark.minimumOverallAccuracy
      && unsafeAppendCount == 0
      && encodedRowsOK
      && (benchmark.allowIgnoredFrames || failedCount == 0)
      && (benchmark.allowIgnoredFrames || outputRaster.height == expectedRaster.height)

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

  private static func encodedRowsAreMonotonic(_ raster: ScrollAccuracyRGBA) -> Bool {
    var last = -1
    var decodedCount = 0
    let step = max(1, raster.height / 80)
    for row in stride(from: 0, to: raster.height, by: step) {
      guard let logicalY = ScrollAccuracyFixture.encodedLogicalY(from: raster, row: row) else {
        return false
      }
      if logicalY < last {
        return false
      }
      last = logicalY
      decodedCount += 1
    }
    return decodedCount > 0
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
