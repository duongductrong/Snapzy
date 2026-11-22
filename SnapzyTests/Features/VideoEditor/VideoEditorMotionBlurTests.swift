//
//  VideoEditorMotionBlurTests.swift
//  SnapzyTests
//
//  Unit tests for GPU camera pan/zoom motion blur and cursor velocity motion blur.
//

import CoreGraphics
import CoreImage
import XCTest
@testable import Snapzy

final class VideoEditorMotionBlurTests: XCTestCase {
  func testCameraMotion_isZeroWhenDisabledOrStationary() {
    let segment = ZoomSegment(
      startTime: 1.0,
      duration: 4.0,
      zoomLevel: 2.2,
      zoomCenter: CGPoint(x: 0.3, y: 0.3),
      zoomType: .manual
    )
    let frameSize = CGSize(width: 1920, height: 1080)

    // Disabled settings always yield zero motion.
    let disabled = VideoEditorMotionBlurEngine.cameraMotion(
      at: 1.2,
      frameDuration: 1.0 / 30.0,
      frameSize: frameSize,
      segments: [segment],
      autoFocusPaths: [:],
      transitionDuration: 0.4,
      settings: .disabled
    )
    XCTAssertFalse(disabled.isActive)
    XCTAssertEqual(disabled.panRadius, 0)
    XCTAssertEqual(disabled.zoomBlurAmount, 0)

    // Static hold in the middle of a manual zoom has zero velocity and zero blur.
    let holding = VideoEditorMotionBlurEngine.cameraMotion(
      at: 3.0,
      frameDuration: 1.0 / 30.0,
      frameSize: frameSize,
      segments: [segment],
      autoFocusPaths: [:],
      transitionDuration: 0.4,
      settings: .default
    )
    XCTAssertFalse(holding.isActive)
    XCTAssertEqual(holding.panRadius, 0)
    XCTAssertEqual(holding.zoomBlurAmount, 0)
  }

  func testCameraMotion_activeDuringFastZoomInAndPan() {
    let segment = ZoomSegment(
      startTime: 1.0,
      duration: 4.0,
      zoomLevel: 2.5,
      zoomCenter: CGPoint(x: 0.2, y: 0.2),
      zoomType: .manual
    )
    let frameSize = CGSize(width: 1920, height: 1080)

    // Mid-way through a 0.4s zoom-in transition to top-left: both pan and radial zoom blur engage.
    let motion = VideoEditorMotionBlurEngine.cameraMotion(
      at: 1.2,
      frameDuration: 1.0 / 30.0,
      frameSize: frameSize,
      segments: [segment],
      autoFocusPaths: [:],
      transitionDuration: 0.4,
      settings: .default
    )

    XCTAssertTrue(motion.isActive)
    XCTAssertGreaterThan(motion.panRadius, 0.5)
    XCTAssertGreaterThan(motion.zoomBlurAmount, 0.5)
  }

  func testCameraMotion_scalesWithShutterStrength() {
    let segment = ZoomSegment(
      startTime: 0.0,
      duration: 3.0,
      zoomLevel: 2.5,
      zoomCenter: CGPoint(x: 0.8, y: 0.75),
      zoomType: .manual
    )
    let frameSize = CGSize(width: 1920, height: 1080)
    let light = VideoEditorMotionBlurEngine.cameraMotion(
      at: 0.2,
      frameDuration: 1.0 / 30.0,
      frameSize: frameSize,
      segments: [segment],
      autoFocusPaths: [:],
      transitionDuration: 0.4,
      settings: VideoEditorMotionBlurSettings(isEnabled: true, shutterStrength: 0.3)
    )
    let strong = VideoEditorMotionBlurEngine.cameraMotion(
      at: 0.2,
      frameDuration: 1.0 / 30.0,
      frameSize: frameSize,
      segments: [segment],
      autoFocusPaths: [:],
      transitionDuration: 0.4,
      settings: VideoEditorMotionBlurSettings(isEnabled: true, shutterStrength: 1.0)
    )

    XCTAssertGreaterThan(strong.panRadius, light.panRadius)
    XCTAssertGreaterThan(strong.zoomBlurAmount, light.zoomBlurAmount)
  }

  func testApplyCameraMotionBlur_preservesSolidColorWithoutDarkEdgeFringes() {
    let extent = CGRect(x: 0, y: 0, width: 128, height: 128)
    let solidBlue = CIImage(color: CIColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1)).cropped(to: extent)
    let motion = VideoEditorMotionBlurEngine.CameraMotionVector(
      panVelocityPx: CGVector(dx: 24, dy: 8),
      panRadius: 10,
      panAngleRadians: 0.3,
      zoomBlurAmount: 6,
      zoomCenterCI: CGPoint(x: 64, y: 64)
    )

    let blurred = VideoEditorMotionBlurEngine.applyCameraMotionBlur(to: solidBlue, motion: motion)
    XCTAssertEqual(blurred.extent, extent)

    // Sample corner pixel (2, 2): clampedToExtent ensures full alpha and preserved blue color.
    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext().render(
      blurred,
      toBitmap: &pixel,
      rowBytes: 4,
      bounds: CGRect(x: 2, y: 2, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    XCTAssertGreaterThan(pixel[2], 210, "Corner pixel lost blue intensity: \(pixel)")
    XCTAssertEqual(pixel[3], 255, "Corner pixel must stay opaque without dark edge bleed: \(pixel)")
  }

  func testCursorMotion_returnsNilWhenSlowAndActiveWhenFlicking() {
    let frameSize = CGSize(width: 1920, height: 1080)

    let slow = VideoEditorMotionBlurEngine.cursorMotion(
      velocityNormalizedPerSec: CGVector(dx: 0.01, dy: 0.01),
      frameDuration: 1.0 / 30.0,
      frameSize: frameSize,
      settings: .default
    )
    XCTAssertNil(slow)

    let fast = VideoEditorMotionBlurEngine.cursorMotion(
      velocityNormalizedPerSec: CGVector(dx: 1.2, dy: 0),
      frameDuration: 1.0 / 30.0,
      frameSize: frameSize,
      settings: .default
    )
    XCTAssertNotNil(fast)
    XCTAssertGreaterThan(fast?.radius ?? 0, 1.0)
    XCTAssertEqual(Double(fast?.angleRadians ?? 99), 0.0, accuracy: 0.001)

    let cursorOff = VideoEditorMotionBlurEngine.cursorMotion(
      velocityNormalizedPerSec: CGVector(dx: 1.2, dy: 0),
      frameDuration: 1.0 / 30.0,
      frameSize: frameSize,
      settings: VideoEditorMotionBlurSettings(isEnabled: true, shutterStrength: 0.7, cursorBlurEnabled: false)
    )
    XCTAssertNil(cursorOff)
  }

  func testMotionBlurSettings_codableBackwardCompatibility() throws {
    let emptyPayload = Data("{}".utf8)
    let decoded = try JSONDecoder().decode(VideoEditorMotionBlurSettings.self, from: emptyPayload)
    XCTAssertEqual(decoded, .default)
  }

  func testShutterPlan_generatesNormalizedWeightedTapsAndRendersWithoutEdgeArtifacts() {
    let segment = ZoomSegment(
      startTime: 1.0,
      duration: 4.0,
      zoomLevel: 2.4,
      zoomCenter: CGPoint(x: 0.2, y: 0.25),
      zoomType: .manual
    )
    let frameSize = CGSize(width: 256, height: 144)

    let plan = VideoEditorMotionBlurEngine.shutterPlan(
      at: 1.22,
      frameDuration: 1.0 / 30.0,
      frameSize: frameSize,
      segments: [segment],
      autoFocusPaths: [:],
      transitionDuration: 0.5,
      settings: .default
    )

    XCTAssertTrue(plan.isActive)
    XCTAssertGreaterThanOrEqual(plan.taps.count, 7)
    let weightSum = plan.taps.reduce(Float(0)) { $0 + $1.weight }
    XCTAssertEqual(weightSum, 1.0, accuracy: 0.001)

    // Render solid blue through the single-pass Metal shutter compute shader and verify edge integrity.
    let extent = CGRect(origin: .zero, size: frameSize)
    let solidBlue = CIImage(color: CIColor(red: 0.1, green: 0.45, blue: 0.92, alpha: 1)).cropped(to: extent)
    let rendered = VideoEditorMotionBlurEngine.renderZoomedWithShutterMotionBlur(
      sourceImage: solidBlue,
      shutterPlan: plan
    )
    XCTAssertEqual(rendered.extent, extent)

    var pixel = [UInt8](repeating: 0, count: 4)
    CIContext().render(
      rendered,
      toBitmap: &pixel,
      rowBytes: 4,
      bounds: CGRect(x: 2, y: 2, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    XCTAssertGreaterThan(pixel[2], 215, "Metal shutter output must preserve blue channel at edges: \(pixel)")
    XCTAssertEqual(pixel[3], 255, "Metal shutter output must stay opaque at edges: \(pixel)")
  }

  func testShutterMetalKernel_preservesVerticalOrientationAndTileCoordinates() {
    // Top half (CIImage y: 64...128) is pure RED; bottom half (CIImage y: 0...64) is pure BLUE.
    let extent = CGRect(x: 0, y: 0, width: 128, height: 128)
    let topRed = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
      .cropped(to: CGRect(x: 0, y: 64, width: 128, height: 64))
    let bottomBlue = CIImage(color: CIColor(red: 0, green: 0, blue: 1, alpha: 1))
      .cropped(to: CGRect(x: 0, y: 0, width: 128, height: 64))
    let split = topRed.composited(over: bottomBlue).cropped(to: extent)

    // Zoom 2x centered on TOP half (top-left normalized y = 0.25 -> CIImage y = 64...128 = pure RED!).
    let crop = ZoomCalculator.calculateCropRect(
      center: CGPoint(x: 0.5, y: 0.25),
      zoomLevel: 2.0,
      frameSize: extent.size
    )
    let uvMinX = Float(crop.minX / extent.width)
    let uvSpanX = Float(crop.width / extent.width)
    let uvMinYTopLeft = Float(1.0 - (crop.maxY / extent.height))
    let uvSpanY = Float(crop.height / extent.height)

    // Two identical taps ensure `plan.isActive == true` so the Metal compute processor actually runs.
    let tap = VideoEditorMotionBlurEngine.ShutterTap(
      uvMinX: uvMinX,
      uvMinY: uvMinYTopLeft,
      uvSpanX: uvSpanX,
      uvSpanY: uvSpanY,
      weight: 0.5
    )
    let plan = VideoEditorMotionBlurEngine.ShutterPlan(
      taps: [tap, tap],
      maxCornerTravelPx: 12,
      panVelocityPx: .zero,
      panAngleRadians: 0,
      zoomDeltaRatio: 0.1,
      zoomCenterNormalized: CGPoint(x: 0.5, y: 0.25)
    )
    XCTAssertTrue(plan.isActive)

    let rendered = VideoEditorMotionBlurEngine.renderZoomedWithShutterMotionBlur(
      sourceImage: split,
      shutterPlan: plan
    )
    let context = CIContext()

    // Sample a sub-tile in the BOTTOM half of the output (`y = 10`): zooming into TOP RED must yield RED everywhere!
    var bottomTilePixel = [UInt8](repeating: 0, count: 4)
    context.render(
      rendered,
      toBitmap: &bottomTilePixel,
      rowBytes: 4,
      bounds: CGRect(x: 64, y: 10, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    XCTAssertGreaterThan(bottomTilePixel[0], 220, "Bottom tile of top-half zoom must be RED, got RGBA=\(bottomTilePixel)")
    XCTAssertLessThan(bottomTilePixel[2], 30, "Bottom tile of top-half zoom must NOT be BLUE, got RGBA=\(bottomTilePixel)")

    // Also verify a sub-tile in the TOP half (`y = 118`) matches RED.
    var topTilePixel = [UInt8](repeating: 0, count: 4)
    context.render(
      rendered,
      toBitmap: &topTilePixel,
      rowBytes: 4,
      bounds: CGRect(x: 64, y: 118, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )
    XCTAssertGreaterThan(topTilePixel[0], 220, "Top tile of top-half zoom must be RED, got RGBA=\(topTilePixel)")
    XCTAssertLessThan(topTilePixel[2], 30, "Top tile of top-half zoom must NOT be BLUE, got RGBA=\(topTilePixel)")
  }
}
