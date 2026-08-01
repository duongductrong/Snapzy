//
//  ScreenCaptureAreaCropTests.swift
//  SnapzyTests
//
//  Unit tests for the live area-capture reconcile-and-crop math (issue #308).
//  Covers scale-mismatch (actual pixels ≠ assumed), region correctness via
//  pixel sampling, mixed-scale promotion, native-Retina pass-through, rotated
//  display dims, and the straddle-display pick.
//

import CoreGraphics
import XCTest
@testable import Snapzy

@MainActor
final class ScreenCaptureAreaCropTests: XCTestCase {

  // MARK: - reconciledPixelCrop: scale mismatch (the #308 bug)

  /// Pre-fix behaviour cropped against `screenFrame × assumedScale` (2.0). On a
  /// scaled HiDPI / non-2x display the real image is smaller than that, so the
  /// crop got clamped to upper-left. The reconciliation must derive the actual
  /// scale from the returned image dims and rebuild the crop in those pixels.
  func test_reconcile_actualSmallerThanAssumed_rebuildsCropFromActualPixels() {
    // Logical screen: 1000 × 600 pts; assumed scale 2.0 → assumed full 2000×1200.
    // ScreenCaptureKit returned a 1000×600 image (actual scale 1.0).
    let screenFrame = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let logicalSourceRect = CGRect(x: 600, y: 200, width: 300, height: 200)
    let logicalCropSize = CGSize(width: 300, height: 200)

    let result = ScreenCaptureManager.reconciledPixelCrop(
      fullImagePixelWidth: 1000,
      fullImagePixelHeight: 600,
      screenFrame: screenFrame,
      logicalSourceRect: logicalSourceRect,
      logicalCropSize: logicalCropSize,
      fallbackScale: 2.0
    )

    XCTAssertEqual(result.actualScale, 1.0, accuracy: 0.001,
                   "actualScale must derive from real image, not the inflated assumption")
    XCTAssertEqual(result.pixelCrop, CGRect(x: 600, y: 200, width: 300, height: 200),
                   "crop must rebuild at 1× from the actual image (not clamped to upper-left)")
  }

  /// The pre-fix smoking-gun: if we DID trust the assumed 2× crop against a 1×
  /// image, `CGImage.cropping(to:)` clamps to image bounds and we get the upper
  /// fragment. Verify that the rebuilt crop is NOT that clamped fragment.
  func test_reconcile_doesNotClampToUpperLeft() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1000, height: 600)
    // Right-side selection — the part the user couldn't reach before the fix.
    let logicalSourceRect = CGRect(x: 700, y: 400, width: 250, height: 150)
    let logicalCropSize = CGSize(width: 250, height: 150)

    let result = ScreenCaptureManager.reconciledPixelCrop(
      fullImagePixelWidth: 1000,
      fullImagePixelHeight: 600,
      screenFrame: screenFrame,
      logicalSourceRect: logicalSourceRect,
      logicalCropSize: logicalCropSize,
      fallbackScale: 2.0
    )

    XCTAssertFalse(result.pixelCrop.isEmpty, "rebuilt crop must not be empty")
    XCTAssertEqual(result.pixelCrop.origin.x, 700, accuracy: 1,
                   "crop origin must follow the actual scale (1×), not stay anchored upper-left")
    XCTAssertEqual(result.pixelCrop.origin.y, 400, accuracy: 1)
    XCTAssertEqual(result.pixelCrop.width, 250, accuracy: 1)
    XCTAssertEqual(result.pixelCrop.height, 150, accuracy: 1)
  }

  // MARK: - reconciledPixelCrop: region correctness (pixel sampling)

  /// Prove the crop offset is geometrically right, not only the size: a vertical
  /// edge image with bright pixels on the right half — selecting the right half
  /// must yield a bright-only cropped region after applying the rebuilt crop.
  func test_reconcile_correctRegionByPixelSampling_rightHalfIsBright() throws {
    // 400 × 200 pixel edge image (left=black, right=white at x=200).
    let fullImage = try XCTUnwrap(
      TestImageFactory.verticalEdge(width: 400, height: 200, edgeX: 200,
                                    leftGray: 0, rightGray: 255)
    )

    // Logical screen treated as 400×200 pts (actual scale 1.0). Select right half.
    let screenFrame = CGRect(x: 0, y: 0, width: 400, height: 200)
    let logicalSourceRect = CGRect(x: 200, y: 0, width: 200, height: 200)
    let logicalCropSize = CGSize(width: 200, height: 200)

    let result = ScreenCaptureManager.reconciledPixelCrop(
      fullImagePixelWidth: fullImage.width,
      fullImagePixelHeight: fullImage.height,
      screenFrame: screenFrame,
      logicalSourceRect: logicalSourceRect,
      logicalCropSize: logicalCropSize,
      fallbackScale: 2.0
    )

    let cropped = try XCTUnwrap(fullImage.cropping(to: result.pixelCrop))
    XCTAssertEqual(cropped.width, 200)
    XCTAssertEqual(cropped.height, 200)
    XCTAssertEqual(averageGray(cropped), 255, accuracy: 1,
                   "crop of the right (bright) half must be bright; if it were clamped to upper-left, it would be dark")
  }

  // MARK: - reconciledPixelCrop: rotated display (portrait dims)

  func test_reconcile_rotatedDisplay_dimsConsistent() {
    // Portrait display (rotated): 600 × 1000 points; native 2× returns 1200 × 2000.
    let screenFrame = CGRect(x: 0, y: 0, width: 600, height: 1000)
    let logicalSourceRect = CGRect(x: 100, y: 400, width: 400, height: 500)
    let logicalCropSize = CGSize(width: 400, height: 500)

    let result = ScreenCaptureManager.reconciledPixelCrop(
      fullImagePixelWidth: 1200,
      fullImagePixelHeight: 2000,
      screenFrame: screenFrame,
      logicalSourceRect: logicalSourceRect,
      logicalCropSize: logicalCropSize,
      fallbackScale: 2.0
    )

    XCTAssertEqual(result.actualScale, 2.0, accuracy: 0.001)
    XCTAssertEqual(result.pixelCrop, CGRect(x: 200, y: 800, width: 800, height: 1000))
  }

  // MARK: - reconciledPixelCrop: native 2× pass-through

  func test_reconcile_nativeRetinaTwoX_scaleAndCropMatch() {
    // 2× display: 1000 pt × 2 = 2000 px.
    let screenFrame = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let logicalSourceRect = CGRect(x: 100, y: 50, width: 200, height: 150)
    let logicalCropSize = CGSize(width: 200, height: 150)

    let result = ScreenCaptureManager.reconciledPixelCrop(
      fullImagePixelWidth: 2000,
      fullImagePixelHeight: 1200,
      screenFrame: screenFrame,
      logicalSourceRect: logicalSourceRect,
      logicalCropSize: logicalCropSize,
      fallbackScale: 2.0
    )

    XCTAssertEqual(result.actualScale, 2.0, accuracy: 0.001)
    XCTAssertEqual(result.pixelCrop, CGRect(x: 200, y: 100, width: 400, height: 300))
  }

  // MARK: - reconciledPixelCrop: out-of-bounds selection clamps

  func test_reconcile_outOfBoundsSelection_clampsToImageBounds() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1000, height: 600)
    // Selection extends past the right edge.
    let logicalSourceRect = CGRect(x: 800, y: 400, width: 400, height: 300)
    let logicalCropSize = CGSize(width: 400, height: 300)

    let result = ScreenCaptureManager.reconciledPixelCrop(
      fullImagePixelWidth: 1000,
      fullImagePixelHeight: 600,
      screenFrame: screenFrame,
      logicalSourceRect: logicalSourceRect,
      logicalCropSize: logicalCropSize,
      fallbackScale: 2.0
    )

    XCTAssertLessThanOrEqual(result.pixelCrop.maxX, 1000)
    XCTAssertLessThanOrEqual(result.pixelCrop.maxY, 600)
    XCTAssertFalse(result.pixelCrop.isEmpty)
  }

  // MARK: - Promotion: native density pass-through; explicit higher min still promotes

  func test_promotion_native1xPassesThroughWhenMinimumIs1x() throws {
    let cropped = try XCTUnwrap(
      TestImageFactory.solidColor(width: 200, height: 150, red: 50, green: 100, blue: 200)
    )
    let promoted = FrozenAreaCaptureSession.imageByPromotingScaleIfNeeded(
      cropped,
      logicalSize: CGSize(width: 200, height: 150),
      sourceScaleFactor: 1.0,
      minimumOutputScaleFactor: 1.0,
      colorSpaceName: nil
    )

    XCTAssertEqual(promoted.scaleFactor, 1.0, accuracy: 0.001,
                   "non-Retina captures must keep native 1× output (issue #414)")
    XCTAssertEqual(promoted.image.width, 200)
    XCTAssertEqual(promoted.image.height, 150)
  }

  func test_promotion_promotesWhenCallerRequestsHigherOutputScale() throws {
    let cropped = try XCTUnwrap(
      TestImageFactory.solidColor(width: 200, height: 150, red: 50, green: 100, blue: 200)
    )
    let promoted = FrozenAreaCaptureSession.imageByPromotingScaleIfNeeded(
      cropped,
      logicalSize: CGSize(width: 200, height: 150),
      sourceScaleFactor: 1.0,
      minimumOutputScaleFactor: 2.0,
      colorSpaceName: nil
    )

    XCTAssertEqual(promoted.scaleFactor, 2.0, accuracy: 0.001)
    XCTAssertEqual(promoted.image.width, 400)
    XCTAssertEqual(promoted.image.height, 300)
  }

  func test_promotion_nativeRetinaNotResampled() throws {
    let native = try XCTUnwrap(
      TestImageFactory.solidColor(width: 400, height: 300, red: 50, green: 100, blue: 200)
    )
    let promoted = FrozenAreaCaptureSession.imageByPromotingScaleIfNeeded(
      native,
      logicalSize: CGSize(width: 200, height: 150),
      sourceScaleFactor: 2.0,
      minimumOutputScaleFactor: 1.0,
      colorSpaceName: nil
    )

    XCTAssertEqual(promoted.scaleFactor, 2.0, accuracy: 0.001)
    XCTAssertEqual(promoted.image.width, 400, "no upscaling expected for native 2×")
    XCTAssertEqual(promoted.image.height, 300)
  }

  // MARK: - Straddle: largest-intersection pick (phase-03)

  func test_straddle_picksDisplayWithLargestOverlap() {
    // Display A at (0,0,1000,600); Display B at (1000,0,1000,600).
    let displays: [CGRect] = [
      CGRect(x: 0, y: 0, width: 1000, height: 600),
      CGRect(x: 1000, y: 0, width: 1000, height: 600),
    ]
    // Selection: 800–1600 wide, 100–500 tall. 200 px on A, 600 px on B.
    let selection = CGRect(x: 800, y: 100, width: 800, height: 400)

    let bestIndex = ScreenCaptureManager.indexOfLargestIntersectingFrame(
      frames: displays,
      rect: selection
    )
    XCTAssertEqual(bestIndex, 1, "B has the larger overlap (600×400) and must win")
  }

  func test_straddle_singleDisplayContainment_picksThatDisplay() {
    let displays: [CGRect] = [
      CGRect(x: 0, y: 0, width: 1000, height: 600),
      CGRect(x: 1000, y: 0, width: 1000, height: 600),
    ]
    let selection = CGRect(x: 1200, y: 100, width: 400, height: 400)

    XCTAssertEqual(
      ScreenCaptureManager.indexOfLargestIntersectingFrame(frames: displays, rect: selection),
      1
    )
  }

  func test_straddle_noIntersection_returnsNil() {
    let displays: [CGRect] = [
      CGRect(x: 0, y: 0, width: 1000, height: 600),
    ]
    // Selection off-screen
    let selection = CGRect(x: 2000, y: 2000, width: 100, height: 100)

    XCTAssertNil(
      ScreenCaptureManager.indexOfLargestIntersectingFrame(frames: displays, rect: selection)
    )
  }

  func test_straddle_orderIndependent_largestStillWinsRegardlessOfArrayOrder() {
    // Reverse the array — the result must still pick the larger-overlap display,
    // not the first intersecting one (the pre-fix behaviour at #308).
    let displays: [CGRect] = [
      CGRect(x: 1000, y: 0, width: 1000, height: 600),  // B first now
      CGRect(x: 0, y: 0, width: 1000, height: 600),     // A second
    ]
    // Selection x: 800–1600.
    //   displays[0] (B) x: 1000–2000.   ∩ = 1000–1600 ⇒ width 600 (overlap area = 600 × 400).
    //   displays[1] (A) x: 0–1000.      ∩ = 800–1000  ⇒ width 200 (overlap area = 200 × 400).
    // → B (index 0) wins because it has the larger overlap, even though it appears first.
    let selection = CGRect(x: 800, y: 100, width: 800, height: 400)

    let bestIndex = ScreenCaptureManager.indexOfLargestIntersectingFrame(
      frames: displays,
      rect: selection
    )
    XCTAssertEqual(bestIndex, 0)
  }

  // MARK: - Native Scale SCK Config & Promotion

  func test_reconcile_nativeScaleConfig_producesCorrectCropWithoutPadding() {
    // 1x display: 2560 × 1440 points.
    // Selection: (100, 100, 800, 600) points.
    // Under native scale config, the captured image will be native: 2560 × 1440 pixels.
    let screenFrame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let logicalSourceRect = CGRect(x: 100, y: 100, width: 800, height: 600)
    let logicalCropSize = CGSize(width: 800, height: 600)

    let result = ScreenCaptureManager.reconciledPixelCrop(
      fullImagePixelWidth: 2560,
      fullImagePixelHeight: 1440,
      screenFrame: screenFrame,
      logicalSourceRect: logicalSourceRect,
      logicalCropSize: logicalCropSize,
      fallbackScale: 1.0
    )

    XCTAssertEqual(result.actualScale, 1.0, accuracy: 0.001)
    XCTAssertEqual(result.pixelCrop, CGRect(x: 100, y: 100, width: 800, height: 600))
  }

  func test_reconcile_nativeScaleConfig_keepsNativeOutputScale() throws {
    // Cropped native image at 1x: 800 × 600 pixels.
    let cropped = try XCTUnwrap(
      TestImageFactory.solidColor(width: 800, height: 600, red: 50, green: 100, blue: 200)
    )

    let promoted = FrozenAreaCaptureSession.imageByPromotingScaleIfNeeded(
      cropped,
      logicalSize: CGSize(width: 800, height: 600),
      sourceScaleFactor: 1.0,
      minimumOutputScaleFactor: 1.0,
      colorSpaceName: nil
    )

    XCTAssertEqual(promoted.scaleFactor, 1.0, accuracy: 0.001)
    XCTAssertEqual(promoted.image.width, 800)
    XCTAssertEqual(promoted.image.height, 600)
  }

  // MARK: - Helpers

  /// Average grayscale value across all pixels in a CGImage (assumes
  /// premultipliedLast RGBA produced by `TestImageFactory`).
  private func averageGray(_ image: CGImage) -> Int {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)

    guard let context = CGContext(
      data: &bytes,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return -1
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var total: Int = 0
    for y in 0..<height {
      for x in 0..<width {
        let offset = y * bytesPerRow + x * 4
        let r = Int(bytes[offset])
        let g = Int(bytes[offset + 1])
        let b = Int(bytes[offset + 2])
        total += (r + g + b) / 3
      }
    }
    return total / (width * height)
  }

  // MARK: - Cross-Display Composite (live multi-display area capture)

  func test_straddle_multiDisplayDetection_singleDisplayRectReturnsSingleID() {
    // Simulates the logic that displayIDsIntersecting would use:
    // rect fully inside display A → only 1 display intersects.
    let displays: [CGRect] = [
      CGRect(x: 0, y: 0, width: 1440, height: 900),    // A
      CGRect(x: 1440, y: 0, width: 2560, height: 1440), // B
    ]
    let selection = CGRect(x: 100, y: 100, width: 400, height: 300)

    let intersecting = displays.filter { $0.intersects(selection) }
    XCTAssertEqual(intersecting.count, 1, "Selection fully inside display A → only 1 display")
  }

  func test_straddle_multiDisplayDetection_crossDisplayRectReturnsMultipleIDs() {
    // rect spanning A and B → 2 displays intersect.
    let displays: [CGRect] = [
      CGRect(x: 0, y: 0, width: 1440, height: 900),    // A
      CGRect(x: 1440, y: 0, width: 2560, height: 1440), // B
    ]
    let selection = CGRect(x: 1200, y: 100, width: 500, height: 300)

    let intersecting = displays.filter { $0.intersects(selection) }
    XCTAssertEqual(intersecting.count, 2, "Selection spanning A and B → 2 displays")
  }

  func test_straddle_multiDisplayDetection_noIntersectionReturnsEmpty() {
    let displays: [CGRect] = [
      CGRect(x: 0, y: 0, width: 1440, height: 900),
    ]
    let selection = CGRect(x: 5000, y: 5000, width: 100, height: 100)

    let intersecting = displays.filter { $0.intersects(selection) }
    XCTAssertTrue(intersecting.isEmpty, "Selection outside all displays → empty")
  }

  func test_straddle_multiDisplayComposite_selectionResultConstructedCorrectly() {
    // Verify AreaSelectionResult constructed for composite path has correct properties.
    let rect = CGRect(x: 1200, y: 100, width: 500, height: 300)
    let displayIDs: Set<CGDirectDisplayID> = [1, 2]
    let primaryDisplayID: CGDirectDisplayID = 1

    let result = AreaSelectionResult(
      target: .rect(rect),
      displayID: primaryDisplayID,
      mode: .screenshot,
      displayIDs: displayIDs
    )

    XCTAssertEqual(result.rect, rect)
    XCTAssertEqual(result.displayID, primaryDisplayID)
    XCTAssertTrue(result.spansMultipleDisplays, "displayIDs count > 1 → spans multiple")
    XCTAssertEqual(result.displayIDs, displayIDs)
  }

  func test_straddle_multiDisplayComposite_singleDisplaySelectionResultDoesNotSpan() {
    let rect = CGRect(x: 100, y: 100, width: 400, height: 300)
    let displayIDs: Set<CGDirectDisplayID> = [1]

    let result = AreaSelectionResult(
      target: .rect(rect),
      displayID: 1,
      mode: .screenshot,
      displayIDs: displayIDs
    )

    XCTAssertFalse(result.spansMultipleDisplays, "Single display → does not span")
  }

  func test_straddle_primaryDisplayPick_matchesLargestIntersection() {
    // For composite path, primary display must be the one with largest overlap.
    let displays: [CGRect] = [
      CGRect(x: 0, y: 0, width: 1440, height: 900),    // A
      CGRect(x: 1440, y: 0, width: 2560, height: 1440), // B
    ]
    // Selection: x 1200–1700. A intersection: 1200–1440 = 240px. B intersection: 1440–1700 = 260px.
    let selection = CGRect(x: 1200, y: 100, width: 500, height: 300)

    let bestIndex = ScreenCaptureManager.indexOfLargestIntersectingFrame(
      frames: displays,
      rect: selection
    )
    XCTAssertEqual(bestIndex, 1, "B has larger overlap (260×300 vs 240×300)")
  }

  func test_straddle_branchingCondition_countsIntersectingDisplaysCorrectly() {
    // Simulate 3-display setup with selection spanning first two.
    let displays: [CGRect] = [
      CGRect(x: 0, y: 0, width: 1440, height: 900),
      CGRect(x: 1440, y: 0, width: 2560, height: 1440),
      CGRect(x: 4000, y: 0, width: 1920, height: 1080),
    ]
    let selection = CGRect(x: 1200, y: 100, width: 500, height: 300)

    let intersecting = displays.filter { $0.intersects(selection) }
    XCTAssertEqual(intersecting.count, 2, "Selection only spans first two displays")
    XCTAssertTrue(intersecting.count > 1, "Composite path should activate")
  }
}
