//
//  GIFConverterTests.swift
//  SnapzyTests
//
//  Unit tests for GIF frame sequencing and video-to-GIF conversion.
//

import AVFoundation
import ImageIO
import XCTest
@testable import Snapzy

final class GIFFrameSequencerTests: XCTestCase {

  private typealias Sequencer = GIFFrameSequencer<Int>

  private func frames(_ outputs: [Sequencer.Output]) -> [Int] {
    outputs.map(\.frame)
  }

  private func delays(_ outputs: [Sequencer.Output]) -> [Double] {
    outputs.map(\.delay)
  }

  func testInOrderFrames_areEmittedOneBehind() {
    var sequencer = Sequencer(frameDelay: 0.1)
    XCTAssertTrue(sequencer.resolve(index: 0, frame: 0).isEmpty, "held until next result is known")
    XCTAssertEqual(frames(sequencer.resolve(index: 1, frame: 1)), [0])
    XCTAssertEqual(frames(sequencer.finish(frameCount: 2)), [1])
  }

  func testOutOfOrderFrames_areEmittedInOrder() {
    var sequencer = Sequencer(frameDelay: 0.1)
    XCTAssertTrue(sequencer.resolve(index: 2, frame: 2).isEmpty)
    XCTAssertTrue(sequencer.resolve(index: 1, frame: 1).isEmpty)
    var output = sequencer.resolve(index: 0, frame: 0)
    output += sequencer.finish(frameCount: 3)
    XCTAssertEqual(frames(output), [0, 1, 2])
    XCTAssertEqual(delays(output), [0.1, 0.1, 0.1])
  }

  func testFailedFrame_foldsItsTimeIntoPreviousFrame() {
    var sequencer = Sequencer(frameDelay: 0.1)
    var output = sequencer.resolve(index: 0, frame: 0)
    output += sequencer.resolve(index: 1, frame: nil)
    output += sequencer.resolve(index: 2, frame: nil)
    output += sequencer.resolve(index: 3, frame: 3)
    output += sequencer.finish(frameCount: 4)

    XCTAssertEqual(frames(output), [0, 3])
    XCTAssertEqual(delays(output)[0], 0.3, accuracy: 1e-9)
    XCTAssertEqual(delays(output)[1], 0.1, accuracy: 1e-9)
    XCTAssertEqual(delays(output).reduce(0, +), 0.4, accuracy: 1e-9, "total duration preserved")
  }

  func testLeadingFailures_stretchFirstFrame() {
    var sequencer = Sequencer(frameDelay: 0.1)
    var output = sequencer.resolve(index: 0, frame: nil)
    output += sequencer.resolve(index: 1, frame: 1)
    output += sequencer.finish(frameCount: 2)

    XCTAssertEqual(frames(output), [1])
    XCTAssertEqual(delays(output)[0], 0.2, accuracy: 1e-9)
  }

  func testFinish_treatsUnresolvedTrailingFramesAsMissing() {
    var sequencer = Sequencer(frameDelay: 0.1)
    var output = sequencer.resolve(index: 0, frame: 0)
    output += sequencer.finish(frameCount: 3)

    XCTAssertEqual(frames(output), [0])
    XCTAssertEqual(delays(output)[0], 0.3, accuracy: 1e-9)
  }

  func testDuplicateAndStaleIndices_areIgnored() {
    var sequencer = Sequencer(frameDelay: 0.1)
    var output = sequencer.resolve(index: 0, frame: 0)
    output += sequencer.resolve(index: 0, frame: 99)
    output += sequencer.resolve(index: 1, frame: 1)
    output += sequencer.resolve(index: 1, frame: 98)
    output += sequencer.finish(frameCount: 2)
    XCTAssertEqual(frames(output), [0, 1])
  }

  func testAllFramesFailed_emitsNothing() {
    var sequencer = Sequencer(frameDelay: 0.1)
    var output = sequencer.resolve(index: 0, frame: nil)
    output += sequencer.resolve(index: 1, frame: nil)
    output += sequencer.finish(frameCount: 2)
    XCTAssertTrue(output.isEmpty)
  }
}

@MainActor
final class GIFConverterTests: XCTestCase {

  private var directory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("GIFConverterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    directory = nil
    try super.tearDownWithError()
  }

  func testConvert_writesFramesInOrderWithFullDuration() async throws {
    let videoURL = try await makeVideo(duration: 1)

    var options = GIFConverter.Options()
    options.fps = 10
    let gifURL = try await GIFConverter.convert(videoURL: videoURL, options: options) { _ in }

    let source = try XCTUnwrap(CGImageSourceCreateWithURL(gifURL as CFURL, nil))
    let frameCount = CGImageSourceGetCount(source)
    XCTAssertGreaterThan(frameCount, 0)

    var totalDelay = 0.0
    for index in 0 ..< frameCount {
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
      let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
      totalDelay += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? 0
    }
    XCTAssertEqual(totalDelay, 1.0, accuracy: 0.05)
  }

  private func makeVideo(duration: TimeInterval) async throws -> URL {
    let url = directory.appendingPathComponent("source.mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64,
        AVVideoHeightKey: 64,
      ]
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: 64,
        kCVPixelBufferHeightKey as String: 64,
      ]
    )
    writer.add(input)
    guard writer.startWriting() else {
      throw writer.error ?? NSError(domain: "GIFConverterTests", code: 1)
    }
    writer.startSession(atSourceTime: .zero)

    let frameRate: Int32 = 30
    let frameCount = Int(duration * Double(frameRate))
    for index in 0 ..< frameCount {
      while !input.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 1_000_000)
      }
      var pixelBuffer: CVPixelBuffer?
      let status = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
      guard status == kCVReturnSuccess, let pixelBuffer else {
        throw NSError(domain: "GIFConverterTests", code: 2)
      }
      CVPixelBufferLockBaseAddress(pixelBuffer, [])
      if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
        memset(base, Int32(index * 8 % 256), CVPixelBufferGetDataSize(pixelBuffer))
      }
      CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
      guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: frameRate)) else {
        throw writer.error ?? NSError(domain: "GIFConverterTests", code: 3)
      }
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: frameRate))
    await writer.finishWriting()
    if let error = writer.error { throw error }
    return url
  }
}
