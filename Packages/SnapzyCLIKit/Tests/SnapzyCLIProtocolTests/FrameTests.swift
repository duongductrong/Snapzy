//
//  FrameTests.swift
//  SnapzyCLIProtocolTests
//

@testable import SnapzyCLIProtocol
import XCTest

final class FrameTests: XCTestCase {
  func testEncode_prefixesBigEndianLength() throws {
    let frame = try Frame.encode(Data("{}".utf8))

    XCTAssertEqual(Array(frame.prefix(4)), [0, 0, 0, 2])
    XCTAssertEqual(Data(frame.dropFirst(4)), Data("{}".utf8))
  }

  func testEncode_rejectsEmptyAndOversizePayloads() {
    XCTAssertThrowsError(try Frame.encode(Data())) { error in
      XCTAssertEqual(error as? FrameError, .emptyPayload)
    }

    let oversize = Data(count: Frame.maxPayloadByteCount + 1)
    XCTAssertThrowsError(try Frame.encode(oversize)) { error in
      XCTAssertEqual(error as? FrameError, .payloadTooLarge(Frame.maxPayloadByteCount + 1))
    }
  }

  func testDecoder_reassemblesByteByByteReads() throws {
    let payload = Data(#"{"id":1,"method":"hello"}"#.utf8)
    let frame = try Frame.encode(payload)
    var decoder = FrameDecoder()

    for byte in frame.dropLast() {
      decoder.append(Data([byte]))
      XCTAssertNil(try decoder.nextPayload())
    }
    try decoder.append(Data([XCTUnwrap(frame.last)]))

    XCTAssertEqual(try decoder.nextPayload(), payload)
    XCTAssertEqual(decoder.bufferedByteCount, 0)
  }

  func testDecoder_splitsTwoFramesFromOneRead() throws {
    let first = Data("first".utf8)
    let second = Data("second".utf8)
    var decoder = FrameDecoder()
    try decoder.append(Frame.encode(first) + Frame.encode(second))

    XCTAssertEqual(try decoder.nextPayload(), first)
    XCTAssertEqual(try decoder.nextPayload(), second)
    XCTAssertNil(try decoder.nextPayload())
  }

  func testDecoder_rejectsOversizeHeaderBeforeBufferingPayload() {
    var decoder = FrameDecoder()
    var length = UInt32(Frame.maxPayloadByteCount + 1).bigEndian
    decoder.append(Data(bytes: &length, count: 4))

    XCTAssertThrowsError(try decoder.nextPayload()) { error in
      XCTAssertEqual(error as? FrameError, .payloadTooLarge(Frame.maxPayloadByteCount + 1))
    }
  }

  func testDecoder_rejectsZeroLengthFrame() {
    var decoder = FrameDecoder()
    decoder.append(Data([0, 0, 0, 0]))

    XCTAssertThrowsError(try decoder.nextPayload()) { error in
      XCTAssertEqual(error as? FrameError, .emptyPayload)
    }
  }
}
