//
//  ForegroundCutoutServiceTests.swift
//  SnapzyTests
//
//  Capture Subject keeps locked pixels when Vision finds no subject.
//  Annotate Remove Background still surfaces that failure.
//

import XCTest
@testable import Snapzy

@MainActor
final class ForegroundCutoutServiceTests: XCTestCase {
  func testFallbackKeepsOriginalWhenNoSubjectDetected() async throws {
    guard #available(macOS 14.0, *) else {
      throw XCTSkip("Foreground cutout requires macOS 14+")
    }

    let image = try XCTUnwrap(TestImageFactory.solidColor(width: 48, height: 48, red: 240, green: 240, blue: 240))
    let result = try await ForegroundCutoutService.shared.extractForegroundResult(
      from: image,
      fallbackToOriginalWhenNoSubject: true
    )

    XCTAssertEqual(result.autoCropDecision, .skippedNoSubjectFallback)
    XCTAssertNil(result.suggestedAutoCropRect)
    XCTAssertTrue(result.fullCanvasImage === image)
  }

  func testDefaultPathStillThrowsWhenNoSubjectDetected() async throws {
    guard #available(macOS 14.0, *) else {
      throw XCTSkip("Foreground cutout requires macOS 14+")
    }

    let image = try XCTUnwrap(TestImageFactory.solidColor(width: 48, height: 48, red: 240, green: 240, blue: 240))

    do {
      _ = try await ForegroundCutoutService.shared.extractForegroundResult(from: image)
      XCTFail("Expected noSubjectDetected when fallback is disabled")
    } catch let error as ForegroundCutoutError {
      guard case .noSubjectDetected = error else {
        XCTFail("Expected noSubjectDetected, got \(error)")
        return
      }
    } catch {
      XCTFail("Expected ForegroundCutoutError, got \(error)")
    }
  }
}
