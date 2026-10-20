//
//  GIFResizerTests.swift
//  SnapzyTests
//
//  Unit tests for resizing animated GIFs off the main actor.
//

import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Snapzy

@MainActor
final class GIFResizerTests: XCTestCase {

  private var directory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("GIFResizerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
    try super.tearDownWithError()
  }

  func testResize_preservesFramesDelaysAndLoopCount() async throws {
    let delays = [0.1, 0.2, 0.3]
    let sourceURL = try makeGIF(size: CGSize(width: 80, height: 40), delays: delays, loopCount: 2)
    let outputURL = directory.appendingPathComponent("out/resized.gif")

    try await GIFResizer.resize(
      sourceURL: sourceURL,
      targetSize: CGSize(width: 40, height: 20),
      outputURL: outputURL
    ) { _ in }

    let source = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
    XCTAssertEqual(CGImageSourceGetCount(source), delays.count)

    let firstFrame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(firstFrame.width, 40)
    XCTAssertEqual(firstFrame.height, 20)

    for (index, expectedDelay) in delays.enumerated() {
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
      let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
      let delay = try XCTUnwrap(gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
      XCTAssertEqual(delay, expectedDelay, accuracy: 0.001)
    }

    let fileProperties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
    let gif = fileProperties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    XCTAssertEqual(gif?[kCGImagePropertyGIFLoopCount] as? Int, 2)
  }

  func testResize_runsFrameWorkOffTheMainThread() async throws {
    let sourceURL = try makeGIF(size: CGSize(width: 20, height: 20), delays: [0.1, 0.1], loopCount: 0)
    let progressThreads = ProgressRecorder()

    try await GIFResizer.resize(
      sourceURL: sourceURL,
      targetSize: CGSize(width: 10, height: 10),
      outputURL: directory.appendingPathComponent("resized.gif")
    ) { progress in
      progressThreads.record(progress: progress, isMainThread: Thread.isMainThread)
    }

    let samples = progressThreads.samples
    XCTAssertFalse(samples.isEmpty)
    XCTAssertTrue(samples.allSatisfy { !$0.isMainThread })
    XCTAssertEqual(samples.last?.progress, 1.0)
  }

  func testResize_missingSourceThrows() async {
    do {
      try await GIFResizer.resize(
        sourceURL: directory.appendingPathComponent("missing.gif"),
        targetSize: CGSize(width: 10, height: 10),
        outputURL: directory.appendingPathComponent("resized.gif")
      ) { _ in }
      XCTFail("Expected cannotReadSource")
    } catch {
      XCTAssertEqual(error as? GIFResizeError, .cannotReadSource)
    }
  }

  // MARK: - Helpers

  private func makeGIF(size: CGSize, delays: [Double], loopCount: Int) throws -> URL {
    let url = directory.appendingPathComponent("source-\(UUID().uuidString).gif")
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, delays.count, nil)
    )
    CGImageDestinationSetProperties(destination, [
      kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount],
    ] as CFDictionary)

    for (index, delay) in delays.enumerated() {
      let context = try XCTUnwrap(CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
      context.setFillColor(CGColor(red: CGFloat(index) / CGFloat(delays.count), green: 0.5, blue: 0.2, alpha: 1))
      context.fill(CGRect(origin: .zero, size: size))
      let image = try XCTUnwrap(context.makeImage())
      CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyGIFDictionary: [
          kCGImagePropertyGIFDelayTime: delay,
          kCGImagePropertyGIFUnclampedDelayTime: delay,
        ],
      ] as CFDictionary)
    }
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
  }
}

private nonisolated final class ProgressRecorder: @unchecked Sendable {
  struct Sample {
    let progress: Double
    let isMainThread: Bool
  }

  private let lock = NSLock()
  private var _samples: [Sample] = []

  var samples: [Sample] {
    lock.withLock { _samples }
  }

  func record(progress: Double, isMainThread: Bool) {
    lock.withLock { _samples.append(Sample(progress: progress, isMainThread: isMainThread)) }
  }
}
