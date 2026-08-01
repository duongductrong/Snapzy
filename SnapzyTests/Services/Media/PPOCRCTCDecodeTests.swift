//
//  PPOCRCTCDecodeTests.swift
//  SnapzyTests
//
//  Synthetic-logit coverage for the greedy CTC decoder.
//

import XCTest
@testable import Snapzy

final class PPOCRCTCDecodeTests: XCTestCase {
  private let dictionary = ["h", "e", "l", "o", " "]

  /// Builds a [timeSteps × classCount] probability buffer with `winner`
  /// taking probability `peak` at each timestep (rest shares the remainder).
  private func logits(winners: [Int], classCount: Int, peak: Float = 0.9) -> [Float] {
    let rest = (1 - peak) / Float(classCount - 1)
    var logits = [Float](repeating: rest, count: winners.count * classCount)
    for (step, winner) in winners.enumerated() {
      logits[step * classCount + winner] = peak
    }
    return logits
  }

  func testRepeatedIndicesCollapseToSingleCharacter() {
    // classCount = dict 5 + blank; "h"=1, "e"=2, "l"=3, "o"=4
    let logits = logits(winners: [1, 1, 1, 2, 3, 3, 4], classCount: 6)
    let (text, _) = PPOCRCTCDecoder.decode(
      logits: logits, timeSteps: 7, classCount: 6, dictionary: dictionary
    )
    XCTAssertEqual(text, "helo")
  }

  func testBlankIndexZeroIsDroppedAndSeparatesRepeats() {
    // blank(0) between two "l"s must not collapse them: h e l _ l o → "hello"
    let logits = logits(winners: [1, 2, 3, 0, 3, 4], classCount: 6)
    let (text, _) = PPOCRCTCDecoder.decode(
      logits: logits, timeSteps: 6, classCount: 6, dictionary: dictionary
    )
    XCTAssertEqual(text, "hello")
  }

  func testConfidenceIsMeanOfKeptTimestepProbabilities() {
    // Two kept timesteps with peaks 0.8 and 0.4 → mean 0.6.
    var logits = [Float](repeating: 0.01, count: 2 * 6)
    logits[0 * 6 + 1] = 0.8
    logits[1 * 6 + 2] = 0.4
    let (_, confidence) = PPOCRCTCDecoder.decode(
      logits: logits, timeSteps: 2, classCount: 6, dictionary: dictionary
    )
    XCTAssertEqual(confidence, 0.6, accuracy: 0.001)
  }

  func testIndexBeyondDictionaryBoundsIsSkipped() {
    // Index 5 exists in classCount but dict has only 4 entries + blank.
    var logits = [Float](repeating: 0.01, count: 3 * 6)
    logits[0 * 6 + 5] = 0.9  // out of dictionary bounds → skipped
    logits[1 * 6 + 1] = 0.9  // "h"
    logits[2 * 6 + 0] = 0.9  // blank
    let (text, confidence) = PPOCRCTCDecoder.decode(
      logits: logits, timeSteps: 3, classCount: 6, dictionary: ["h"]
    )
    XCTAssertEqual(text, "h")
    XCTAssertEqual(confidence, 0.9, accuracy: 0.001)
  }

  func testAllBlankInputYieldsEmptyTextAndZeroConfidence() {
    let logits = logits(winners: [0, 0, 0], classCount: 6)
    let (text, confidence) = PPOCRCTCDecoder.decode(
      logits: logits, timeSteps: 3, classCount: 6, dictionary: dictionary
    )
    XCTAssertEqual(text, "")
    XCTAssertEqual(confidence, 0)
  }

  func testRawLogitsAreSoftmaxedBeforeDecoding() {
    // Negative/large values (outside [0,1]) trigger the defensive softmax;
    // argmax order is preserved, so decoding still works.
    var logits = [Float](repeating: -2, count: 2 * 6)
    logits[0 * 6 + 1] = 3.0
    logits[1 * 6 + 2] = 1.5
    let (text, confidence) = PPOCRCTCDecoder.decode(
      logits: logits, timeSteps: 2, classCount: 6, dictionary: dictionary
    )
    XCTAssertEqual(text, "he")
    XCTAssertGreaterThan(confidence, 0)
    XCTAssertLessThanOrEqual(confidence, 1)
  }

  func testDegenerateInputYieldsEmptyResult() {
    let (text, confidence) = PPOCRCTCDecoder.decode(
      logits: [], timeSteps: 0, classCount: 6, dictionary: dictionary
    )
    XCTAssertEqual(text, "")
    XCTAssertEqual(confidence, 0)
  }
}
