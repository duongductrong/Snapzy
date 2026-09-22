//
//  RecordingVideoCompatibilityLimiterTests.swift
//  SnapzyTests
//

import XCTest
@testable import Snapzy

final class RecordingVideoCompatibilityLimiterTests: XCTestCase {

  func testNative_returnsOddInputUnchangedAtEveryFPS() {
    for fps in [1, 24, 30, 60, 120] {
      assertOutputEqual(
        RecordingVideoCompatibilityLimiter.clampedOutputSize(
          width: 5121, height: 2881, resolution: .native, fps: fps
        ),
        (5121, 2881)
      )
    }
  }

  func testInsideBox_returnsOddInputUnchanged() {
    assertOutputEqual(
      RecordingVideoCompatibilityLimiter.clampedOutputSize(
        width: 1919, height: 1079, resolution: .fhd1080, fps: 60
      ),
      (1919, 1079)
    )
  }

  func testAuto_keepsMoreSpaceMacBookProUnchangedAt60FPS() {
    assertOutputEqual(clamp(3600, 2338, .auto, 60), (3600, 2338))
  }

  func testAuto_keepsDefault16InchMacBookProUnchangedAt60FPS() {
    assertOutputEqual(clamp(3456, 2234, .auto, 60), (3456, 2234))
  }

  func testAuto_clamps5120By2880At60FPS() {
    assertOutputEqual(clamp(5120, 2880, .auto, 60), (3840, 2160))
  }

  func testAuto_clampsPortraitByTransposing4KBox() {
    assertOutputEqual(clamp(2880, 5120, .auto, 60), (2160, 3840))
  }

  func testAuto_engagesFPSTermAt120FPS() {
    let output = clamp(3024, 1964, .auto, 120)
    XCTAssertNotEqual(output.width, 3024)
    XCTAssertNotEqual(output.height, 1964)
  }

  func test4K_5120By2880At60FPS() {
    assertOutputEqual(clamp(5120, 2880, .uhd4k, 60), (3840, 2160))
  }

  func test4K_16By10Regression() {
    assertOutputEqual(clamp(3840, 2400, .uhd4k, 60), (3456, 2160))
  }

  func test4K_MacBookMoreSpace() {
    assertOutputEqual(clamp(4112, 2658, .uhd4k, 60), (3340, 2160))
  }

  func test4K_portraitTransposesBox() {
    assertOutputEqual(clamp(2880, 5120, .uhd4k, 60), (2160, 3840))
  }

  func test4K_squareInput() {
    assertOutputEqual(clamp(3840, 3840, .uhd4k, 60), (2160, 2160))
  }

  func testDegenerateDimensions() {
    XCTAssertEqual(clamp(3000, 1, .fhd1080, 60).height, 2)
    assertOutputEqual(clamp(1, 1, .sd480, 60), (1, 1))
  }

  func testDoesNotUpscale() {
    assertOutputEqual(clamp(640, 480, .uhd4k, 60), (640, 480))
  }

  func testClampProducesEvenDimensions() {
    for (width, height, resolution) in [
      (5121, 2881, RecordingMaxResolution.uhd4k),
      (3001, 501, .fhd1080),
      (501, 3001, .sd480),
    ] {
      let output = clamp(width, height, resolution, 60)
      XCTAssertEqual(output.width % 2, 0)
      XCTAssertEqual(output.height % 2, 0)
    }
  }

  func testFPSTermFurtherRestricts4K() {
    let output = clamp(5120, 2880, .uhd4k, 120)
    XCTAssertLessThan(output.width, 3840)
    XCTAssertLessThan(output.height, 2160)
    assertOutputEqual(output, (2786, 1566))
  }

  func testAllNonNativePresetsMeetLevel52Limits() {
    let resolutions: [RecordingMaxResolution] = [.auto, .uhd4k, .qhd1440, .fhd1080, .hd720, .sd480]
    let aspectRatios = [(16, 9), (16, 10), (4, 3), (1, 1), (21, 9), (6, 1)]

    for resolution in resolutions {
      for fps in [24, 30, 60, 120] {
        for (ratioWidth, ratioHeight) in aspectRatios {
          for multiplier in [640, 1280, 1920, 2560, 3840, 5120, 7680, 11520] {
            for (width, height) in [
              (ratioWidth * multiplier, ratioHeight * multiplier),
              (ratioHeight * multiplier, ratioWidth * multiplier),
            ] {
              let output = clamp(width, height, resolution, fps)
              let macroblocks = macroblockCount(output.width, output.height)
              XCTAssertLessThanOrEqual(macroblocks, 36_864, "\(resolution), \(fps) fps, \(width)x\(height)")
              XCTAssertLessThanOrEqual(macroblocks * fps, 2_073_600, "\(resolution), \(fps) fps, \(width)x\(height)")
              XCTAssertLessThanOrEqual(output.width, max(width, 2), "\(resolution), \(fps) fps, \(width)x\(height)")
              XCTAssertLessThanOrEqual(output.height, max(height, 2), "\(resolution), \(fps) fps, \(width)x\(height)")
            }
          }
        }
      }
    }
  }

  func testClampKeepsAspectWithinToleranceOrSmallerDimensionNearExact() {
    for (width, height, resolution, fps) in [
      (5120, 2880, RecordingMaxResolution.uhd4k, 60),
      (100, 3200, .sd480, 60),
      (3000, 500, .fhd1080, 60),
      (500, 3000, .fhd1080, 60),
      (5120, 2880, .uhd4k, 120),
    ] {
      let output = clamp(width, height, resolution, fps)
      let inputAspect = Double(width) / Double(height)
      let outputAspect = Double(output.width) / Double(output.height)
      let aspectDrift = abs(outputAspect / inputAspect - 1)
      let exactSmallerDimension = min(
        Double(width) * exactScale(width: width, height: height, resolution: resolution, fps: fps),
        Double(height) * exactScale(width: width, height: height, resolution: resolution, fps: fps)
      )
      XCTAssertTrue(
        aspectDrift < 0.01 || abs(Double(min(output.width, output.height)) - exactSmallerDimension) <= 2,
        "\(width)x\(height) produced \(output.width)x\(output.height)"
      )
    }
  }

  private func clamp(
    _ width: Int,
    _ height: Int,
    _ resolution: RecordingMaxResolution,
    _ fps: Int
  ) -> (width: Int, height: Int) {
    RecordingVideoCompatibilityLimiter.clampedOutputSize(
      width: width, height: height, resolution: resolution, fps: fps
    )
  }

  private func assertOutputEqual(
    _ actual: (width: Int, height: Int),
    _ expected: (width: Int, height: Int),
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(actual.width, expected.width, file: file, line: line)
    XCTAssertEqual(actual.height, expected.height, file: file, line: line)
  }

  private func macroblockCount(_ width: Int, _ height: Int) -> Int {
    ((width + 15) / 16) * ((height + 15) / 16)
  }

  private func exactScale(width: Int, height: Int, resolution: RecordingMaxResolution, fps: Int) -> Double {
    var box = resolution.box!
    if height > width {
      box = (box.height, box.width)
    }
    var scale = min(1, Double(box.width) / Double(width), Double(box.height) / Double(height))
    let maxMacroblocks = min(36_864, 2_073_600 / max(fps, 1))

    for _ in 0..<8 {
      let scaledWidth = Int(floor(Double(width) * scale))
      let scaledHeight = Int(floor(Double(height) * scale))
      let macroblocks = macroblockCount(scaledWidth, scaledHeight)
      guard macroblocks > maxMacroblocks else { break }
      scale *= sqrt(Double(maxMacroblocks) / Double(macroblocks)) * 0.999
    }

    return scale
  }
}
