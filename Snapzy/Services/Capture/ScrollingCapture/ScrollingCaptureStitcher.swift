//
//  ScrollingCaptureStitcher.swift
//  Snapzy
//
//  Vertical stitcher for scrolling capture sessions.
//

import AppKit
import Foundation
import Vision

nonisolated enum ScrollingCaptureMergeDirection {
  case unresolved
  case appendFromBottom
  case appendFromTop
}

nonisolated enum ScrollingCaptureStitchOutcome {
  case initialized
  case appended(deltaY: Int)
  case ignoredNoMovement
  case ignoredAlignmentFailed
  case reachedHeightLimit
}

nonisolated enum ScrollingCaptureStitchSafety: Equatable {
  case confirmed
  case tentative(reason: String)
  case unsafe(reason: String)

  var isUnsafe: Bool {
    if case .unsafe = self {
      return true
    }
    return false
  }
}

nonisolated enum ScrollingCaptureAlignmentPath: String {
  case initialFrame = "initial-frame"
  case fastGuided = "fast-guided"
  case guidedVision = "guided-vision"
  case recoveryVision = "recovery-vision"
  case noMovement = "no-movement"
  case duplicateBoundary = "duplicate-boundary"
  case alignmentFailed = "alignment-failed"
  case heightLimit = "height-limit"
}

nonisolated struct ScrollingCaptureAlignmentDebugInfo {
  let path: ScrollingCaptureAlignmentPath
  let usedVisionEstimate: Bool
  let confidence: Double
  let pixelScore: Double?
  let totalScore: Double?
  let appendDeltaY: Int?
  let visionAgreementCount: Int
}

nonisolated struct ScrollingCaptureStitchUpdate {
  let outcome: ScrollingCaptureStitchOutcome
  let mergedImage: CGImage?
  let acceptedFrameCount: Int
  let outputHeight: Int
  let matchFailureCount: Int
  let mergeDirection: ScrollingCaptureMergeDirection
  let likelyReachedBoundary: Bool
  let safety: ScrollingCaptureStitchSafety
  let alignmentDebug: ScrollingCaptureAlignmentDebugInfo?
}

// Instances are confined to the coordinator's serial processing queue during capture.
nonisolated final class ScrollingCaptureStitcher: @unchecked Sendable {
  private enum MatchSearchMode {
    case guided
    case recovery
  }

  private struct RasterImage {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: [UInt8]

    init?(cgImage: CGImage) {
      let width = cgImage.width
      let height = cgImage.height
      let bytesPerRow = width * 4
      var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

      let drew = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
        guard let baseAddress = rawBuffer.baseAddress else { return false }
        guard
          let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
          )
        else {
          return false
        }

        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
      }

      guard drew else { return nil }

      self.width = width
      self.height = height
      self.bytesPerRow = bytesPerRow
      self.pixels = pixels
    }

    func blockDifference(
      comparedTo other: RasterImage,
      startRow: Int,
      otherStartRow: Int,
      rowCount: Int,
      xStart: Int,
      xEnd: Int,
      columnStride: Int,
      rowStride: Int
    ) -> Double {
      guard rowCount > 0 else { return 255 }
      guard startRow >= 0, otherStartRow >= 0 else { return 255 }
      guard startRow + rowCount <= height, otherStartRow + rowCount <= other.height else { return 255 }

      let safeStart = max(0, xStart)
      let safeEnd = min(min(width, other.width), xEnd)
      guard safeStart < safeEnd else { return 255 }

      let safeColumnStride = max(1, columnStride)
      let safeRowStride = max(1, rowStride)
      var total = 0.0
      var count = 0

      for rowOffset in stride(from: 0, to: rowCount, by: safeRowStride) {
        let lhsOffset = (startRow + rowOffset) * bytesPerRow
        let rhsOffset = (otherStartRow + rowOffset) * other.bytesPerRow

        for x in stride(from: safeStart, to: safeEnd, by: safeColumnStride) {
          let lhsIndex = lhsOffset + x * 4
          let rhsIndex = rhsOffset + x * 4
          total += colorDifference(comparedTo: other, lhsIndex: lhsIndex, rhsIndex: rhsIndex)
          count += 1
        }
      }

      return count > 0 ? total / Double(count) : 255
    }

    func copyRows(
      startRow: Int,
      rowCount: Int,
      into destination: inout [UInt8],
      destinationRow: Int
    ) {
      guard rowCount > 0 else { return }

      for localRow in 0..<rowCount {
        let sourceIndex = (startRow + localRow) * bytesPerRow
        let destinationIndex = (destinationRow + localRow) * bytesPerRow
        destination[destinationIndex..<(destinationIndex + bytesPerRow)] =
          pixels[sourceIndex..<(sourceIndex + bytesPerRow)]
      }
    }

    func makeCGImage() -> CGImage? {
      Self.makeCGImage(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
    }

    func makeLumaPlane() -> ScrollingCaptureLumaPlane {
      ScrollingCaptureLumaPlane(rgbaPixels: pixels, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    func makeCroppedCGImage(
      xStart: Int,
      xEnd: Int,
      startRow: Int,
      rowCount: Int
    ) -> CGImage? {
      let safeXStart = max(0, xStart)
      let safeXEnd = min(width, xEnd)
      let safeStartRow = max(0, startRow)
      let safeRowCount = min(rowCount, height - safeStartRow)

      guard safeXStart < safeXEnd, safeRowCount > 0 else { return nil }

      let croppedWidth = safeXEnd - safeXStart
      let croppedBytesPerRow = croppedWidth * 4
      var croppedPixels = [UInt8](repeating: 0, count: safeRowCount * croppedBytesPerRow)

      for localRow in 0..<safeRowCount {
        let sourceIndex = (safeStartRow + localRow) * bytesPerRow + safeXStart * 4
        let destinationIndex = localRow * croppedBytesPerRow
        croppedPixels[destinationIndex..<(destinationIndex + croppedBytesPerRow)] =
          pixels[sourceIndex..<(sourceIndex + croppedBytesPerRow)]
      }

      return Self.makeCGImage(
        width: croppedWidth,
        height: safeRowCount,
        bytesPerRow: croppedBytesPerRow,
        pixels: croppedPixels
      )
    }

    static func makeCGImage(
      width: Int,
      height: Int,
      bytesPerRow: Int,
      pixels: [UInt8]
    ) -> CGImage? {
      let data = Data(pixels) as CFData
      guard let provider = CGDataProvider(data: data) else { return nil }

      let bitmapInfo = CGBitmapInfo(rawValue:
        CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
      )

      return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
      )
    }

    private func colorDifference(comparedTo other: RasterImage, lhsIndex: Int, rhsIndex: Int) -> Double {
      let dr = abs(Int(pixels[lhsIndex]) - Int(other.pixels[rhsIndex]))
      let dg = abs(Int(pixels[lhsIndex + 1]) - Int(other.pixels[rhsIndex + 1]))
      let db = abs(Int(pixels[lhsIndex + 2]) - Int(other.pixels[rhsIndex + 2]))

      let lhsLuma =
        Int(pixels[lhsIndex]) * 299 +
        Int(pixels[lhsIndex + 1]) * 587 +
        Int(pixels[lhsIndex + 2]) * 114
      let rhsLuma =
        Int(other.pixels[rhsIndex]) * 299 +
        Int(other.pixels[rhsIndex + 1]) * 587 +
        Int(other.pixels[rhsIndex + 2]) * 114

      let colorAverage = Double(dr + dg + db) / 3.0
      let lumaDifference = Double(abs(lhsLuma - rhsLuma)) / 1000.0
      return colorAverage * 0.42 + lumaDifference * 0.58
    }
  }

  private struct ContentSlice {
    let raster: RasterImage
    let startRow: Int
    let rowCount: Int
  }

  private struct Match {
    let direction: ScrollingCaptureMergeDirection
    let deltaY: Int
    let pixelScore: Double
    let totalScore: Double
    let strongBandCount: Int
    let bandCount: Int
    let worstBandScore: Double
    let bandVariance: Double
  }

  private struct MatchSearchResult {
    let best: Match
    let runnerUp: Match?
  }

  private struct OverlapMetrics {
    let averageDifference: Double
    let strongBandCount: Int
    let bandCount: Int
    let worstDifference: Double
    let variance: Double
  }

  private struct VisionAlignmentEstimate {
    let deltaY: Int
    let agreementCount: Int
    let observedCount: Int
    let deltaSpread: Int
  }

  private var baseRaster: RasterImage?
  private var lastRaster: RasterImage?
  private var contentSlices: [ContentSlice] = []
  private var headerHeight = 0
  private var footerHeight = 0
  private var leadingStaticWidth = 0
  private var trailingStaticWidth = 0
  private var mergeDirection: ScrollingCaptureMergeDirection = .unresolved
  private var cachedMergedImage: CGImage?
  private var lastMatch: Match?
  private var matchNotFoundCount = 0
  /// First row of `lastRaster` that belongs to the output but is not committed
  /// yet; the tail runs from here to the bottom of the content area. Pages fade
  /// or dim content near the bottom edge for as long as it sits there, so rows
  /// are only committed once a later frame has carried them `edgeClearance`
  /// rows clear of that edge. Until then they are rendered from the newest
  /// frame, along with the footer band below them.
  ///
  /// Anchored to its first row rather than stored as a count, so a footer
  /// estimate that grows mid-capture shortens the tail instead of shifting it.
  private var tailStartRow: Int?
  private var lastLuma: ScrollingCaptureLumaPlane?
  /// Votes on which rows are fixed chrome, gathered across frame pairs that
  /// moved.
  private var stickyVotes = ScrollingCaptureStickyEdgeAccumulator()
  /// Votes on which side columns stay put, cast column by column.
  private var sideVotes = ScrollingCaptureStickyEdgeAccumulator()
  /// Rounds after which the chrome estimate is frozen for the capture.
  private static let settledStickyRounds = 8
  /// Rows of movement needed before a frame pair can vote on chrome.
  private static let minimumStickyMeasurementDelta = 8
  /// Deepest bottom-edge treatment measured on this page, in pixels.
  private var measuredDimmedDepth: Int?
  private var dimmingMeasurementCount = 0

  /// Pages that show no measurable treatment still keep a little lag, which
  /// absorbs a partly drawn row at the boundary.
  private static let minimumEdgeClearance = 80
  /// Added to the measured depth, since its last rows are the least certain.
  private static let edgeClearanceMargin = 60
  /// Rows of movement needed before a frame pair can say anything about the
  /// edge treatment.
  private static let minimumDimmingMeasurementDelta = 8
  /// Measurements after which the depth estimate is treated as settled.
  private static let maximumDimmingMeasurements = 8

  private(set) var acceptedFrameCount = 0

  var outputHeight: Int {
    renderedSlices.reduce(0) { $0 + $1.rowCount }
  }

  private var tailRowCount: Int {
    guard let tailStartRow, let lastRaster else { return 0 }
    return max(0, lastRaster.height - footerHeight - tailStartRow)
  }

  private var chromeHasSettled: Bool {
    stickyVotes.rounds >= Self.settledStickyRounds
  }

  private var sidesHaveSettled: Bool {
    sideVotes.rounds >= Self.settledStickyRounds
  }

  func start(with image: CGImage) -> ScrollingCaptureStitchUpdate? {
    guard let raster = RasterImage(cgImage: image) else { return nil }

    baseRaster = raster
    lastRaster = raster
    contentSlices = [ContentSlice(raster: raster, startRow: 0, rowCount: raster.height)]
    headerHeight = 0
    footerHeight = 0
    leadingStaticWidth = 0
    trailingStaticWidth = 0
    mergeDirection = .unresolved
    cachedMergedImage = image
    lastMatch = nil
    matchNotFoundCount = 0
    tailStartRow = nil
    lastLuma = nil
    stickyVotes = ScrollingCaptureStickyEdgeAccumulator()
    sideVotes = ScrollingCaptureStickyEdgeAccumulator()
    measuredDimmedDepth = nil
    dimmingMeasurementCount = 0
    acceptedFrameCount = 1

    return ScrollingCaptureStitchUpdate(
      outcome: .initialized,
      mergedImage: image,
      acceptedFrameCount: acceptedFrameCount,
      outputHeight: outputHeight,
      matchFailureCount: matchNotFoundCount,
      mergeDirection: mergeDirection,
      likelyReachedBoundary: false,
      safety: .confirmed,
      alignmentDebug: ScrollingCaptureAlignmentDebugInfo(
        path: .initialFrame,
        usedVisionEstimate: false,
        confidence: 1,
        pixelScore: nil,
        totalScore: nil,
        appendDeltaY: nil,
        visionAgreementCount: 0
      )
    )
  }

  func append(
    _ image: CGImage,
    maxOutputHeight: Int,
    expectedSignedDeltaPixels: Int? = nil,
    renderMergedImage: Bool = true,
    allowsSettledPartialStep: Bool = false
  ) -> ScrollingCaptureStitchUpdate? {
    guard let lastRaster, let baseRaster else { return start(with: image) }
    guard let raster = RasterImage(cgImage: image) else { return nil }
    let expectedDeltaPixels = expectedSignedDeltaPixels.map(abs)
    guard raster.width == lastRaster.width, raster.height == lastRaster.height else {
      matchNotFoundCount += 1
      return currentUpdate(outcome: .ignoredAlignmentFailed, includeMergedImage: renderMergedImage)
    }

    let previousLuma = lastLuma ?? lastRaster.makeLumaPlane()
    let currentLuma = raster.makeLumaPlane()
    // Until the votes settle, this pair's own estimate keeps chrome that has
    // not been voted in yet out of the matching region. Static side columns,
    // such as a window sidebar, never match at a real scroll offset and would
    // dilute every score. They are found first, because a sidebar stays put in
    // every row and would otherwise make ordinary rows look like chrome.
    let pairStaticSides = sidesHaveSettled
      ? ScrollingCaptureStaticSides.none
      : ScrollingCaptureStickyEdgeDetector.detectSides(
        previous: previousLuma,
        current: currentLuma,
        rowStart: headerHeight,
        rowEnd: raster.height - footerHeight
      )
    let inferredLeadingStaticWidth = max(leadingStaticWidth, pairStaticSides.leading)
    let inferredTrailingStaticWidth = max(trailingStaticWidth, pairStaticSides.trailing)
    // Chrome comes from votes only. A single frame pair is a poor witness: on a
    // page with large flat areas it reports bands hundreds of pixels deep that
    // are not there, which shrinks the searchable content area until a long
    // scroll has no overlap left to match.
    let inferredHeaderHeight = headerHeight
    let inferredFooterHeight = footerHeight
    let visionAlignmentEstimate = estimateVisionAlignment(
      previous: lastRaster,
      current: raster,
      headerHeight: inferredHeaderHeight,
      footerHeight: inferredFooterHeight,
      leadingStaticWidth: inferredLeadingStaticWidth,
      trailingStaticWidth: inferredTrailingStaticWidth
    )
    // A wheel request is an upper bound at the end of a scroll area. Only a
    // viewport independently verified as settled may use a smaller visual prior.
    let matchingExpectedDelta: Int?
    if allowsSettledPartialStep,
       let expectedDeltaPixels,
       let estimate = visionAlignmentEstimate,
       estimate.agreementCount >= 2,
       estimate.deltaY > 0, estimate.deltaY < expectedDeltaPixels {
      matchingExpectedDelta = estimate.deltaY * ((expectedSignedDeltaPixels ?? 0) < 0 ? -1 : 1)
    } else {
      matchingExpectedDelta = expectedSignedDeltaPixels
    }
    let frameDifference = contentDifference(
      previous: lastRaster,
      current: raster,
      headerHeight: inferredHeaderHeight,
      footerHeight: inferredFooterHeight,
      leadingStaticWidth: inferredLeadingStaticWidth,
      trailingStaticWidth: inferredTrailingStaticWidth
    )
    let fastGuidedMatch = bestMatch(
      previous: lastRaster,
      current: raster,
      previousLuma: previousLuma,
      currentLuma: currentLuma,
      headerHeight: inferredHeaderHeight,
      footerHeight: inferredFooterHeight,
      leadingStaticWidth: inferredLeadingStaticWidth,
      trailingStaticWidth: inferredTrailingStaticWidth,
      expectedSignedDeltaPixels: matchingExpectedDelta,
      visionAlignmentEstimate: nil,
      searchMode: .guided
    )
    let strongVisionMovement = hasStrongVisionMovement(visionAlignmentEstimate)

    if
      frameDifference < 8.5,
      !strongVisionMovement,
      fastGuidedMatch == nil
    {
      return currentUpdate(
        outcome: .ignoredNoMovement,
        includeMergedImage: renderMergedImage,
        likelyReachedBoundary: true,
        alignmentDebug: ScrollingCaptureAlignmentDebugInfo(
          path: .duplicateBoundary,
          usedVisionEstimate: visionAlignmentEstimate != nil,
          confidence: 1,
          pixelScore: nil,
          totalScore: nil,
          appendDeltaY: nil,
          visionAgreementCount: 0
        )
      )
    }

    var alignmentPath: ScrollingCaptureAlignmentPath = .fastGuided
    var match = fastGuidedMatch

    if shouldValidateFastGuidedMatch(match, visionAlignmentEstimate: visionAlignmentEstimate) {
      let guidedVisionMatch = bestMatch(
        previous: lastRaster,
        current: raster,
        previousLuma: previousLuma,
        currentLuma: currentLuma,
        headerHeight: inferredHeaderHeight,
        footerHeight: inferredFooterHeight,
        leadingStaticWidth: inferredLeadingStaticWidth,
        trailingStaticWidth: inferredTrailingStaticWidth,
        expectedSignedDeltaPixels: matchingExpectedDelta,
        visionAlignmentEstimate: visionAlignmentEstimate,
        searchMode: .guided
      )

      if let guidedVisionMatch {
        match = guidedVisionMatch
        alignmentPath = .guidedVision
      } else if match == nil || !fastGuidedMatchDisagreesWithVision(match, visionAlignmentEstimate: visionAlignmentEstimate) {
        match = fastGuidedMatch
        alignmentPath = .fastGuided
      } else {
        match = nil
      }
    }

    if match == nil {
      match = bestMatch(
        previous: lastRaster,
        current: raster,
        previousLuma: previousLuma,
        currentLuma: currentLuma,
        headerHeight: inferredHeaderHeight,
        footerHeight: inferredFooterHeight,
        leadingStaticWidth: inferredLeadingStaticWidth,
        trailingStaticWidth: inferredTrailingStaticWidth,
        expectedSignedDeltaPixels: matchingExpectedDelta,
        visionAlignmentEstimate: visionAlignmentEstimate,
        searchMode: .recovery
      )
      alignmentPath = .recoveryVision
    }

    if
      let expectedDeltaPixels,
      expectedDeltaPixels > 0,
      let candidate = match,
      !isVerifiedSettledPartialMatch(candidate, expectedDeltaPixels: expectedDeltaPixels,
        visionAlignmentEstimate: visionAlignmentEstimate, allowed: allowsSettledPartialStep),
      stronglyContradictsKnownStep(
        candidate,
        expectedDeltaPixels: expectedDeltaPixels,
        visionAlignmentEstimate: visionAlignmentEstimate
      )
    {
      matchNotFoundCount += 1
      return currentUpdate(
        outcome: .ignoredAlignmentFailed,
        includeMergedImage: renderMergedImage,
        alignmentDebug: ScrollingCaptureAlignmentDebugInfo(
          path: .alignmentFailed,
          usedVisionEstimate: visionAlignmentEstimate != nil,
          confidence: matcherConfidence(for: candidate),
          pixelScore: candidate.pixelScore,
          totalScore: candidate.totalScore,
          appendDeltaY: candidate.deltaY,
          visionAgreementCount: visionAlignmentEstimate?.agreementCount ?? 0
        )
      )
    }

    if isLikelyDuplicateBoundary(
      frameDifference: frameDifference,
      match: match,
      expectedDeltaPixels: expectedDeltaPixels,
      visionAlignmentEstimate: visionAlignmentEstimate
    ) {
      return currentUpdate(
        outcome: .ignoredNoMovement,
        includeMergedImage: renderMergedImage,
        likelyReachedBoundary: true,
        alignmentDebug: ScrollingCaptureAlignmentDebugInfo(
          path: .duplicateBoundary,
          usedVisionEstimate: visionAlignmentEstimate != nil,
          confidence: match.map { matcherConfidence(for: $0) } ?? 1,
          pixelScore: match?.pixelScore,
          totalScore: match?.totalScore,
          appendDeltaY: nil,
          visionAgreementCount: visionAlignmentEstimate?.agreementCount ?? 0
        )
      )
    }

    guard let match else {
      matchNotFoundCount += 1
      return currentUpdate(
        outcome: .ignoredAlignmentFailed,
        includeMergedImage: renderMergedImage,
        alignmentDebug: ScrollingCaptureAlignmentDebugInfo(
          path: .alignmentFailed,
          usedVisionEstimate: visionAlignmentEstimate != nil,
          confidence: 0,
          pixelScore: nil,
          totalScore: nil,
          appendDeltaY: nil,
          visionAgreementCount: visionAlignmentEstimate?.agreementCount ?? 0
        )
      )
    }

    let votedStickyEdges = voteOnStickyEdgesIfNeeded(
      previous: previousLuma,
      current: currentLuma,
      deltaY: match.deltaY,
      columnStart: inferredLeadingStaticWidth,
      columnEnd: raster.width - inferredTrailingStaticWidth
    )

    measureEdgeDimmingIfNeeded(
      previous: previousLuma,
      current: currentLuma,
      deltaY: match.deltaY,
      headerHeight: max(inferredHeaderHeight, votedStickyEdges.top),
      footerHeight: max(inferredFooterHeight, votedStickyEdges.bottom),
      leadingStaticWidth: inferredLeadingStaticWidth,
      trailingStaticWidth: inferredTrailingStaticWidth
    )

    // Side columns only steer matching, never where strips are cut, so they can
    // keep growing with the votes.
    let votedStaticSides = voteOnStaticSidesIfNeeded(
      previous: previousLuma,
      current: currentLuma,
      deltaY: match.deltaY,
      rowStart: max(inferredHeaderHeight, votedStickyEdges.top),
      rowEnd: raster.height - max(inferredFooterHeight, votedStickyEdges.bottom)
    )

    if mergeDirection == .unresolved {
      mergeDirection = match.direction
      headerHeight = max(inferredHeaderHeight, votedStickyEdges.top)
      footerHeight = max(inferredFooterHeight, votedStickyEdges.bottom)
      leadingStaticWidth = max(inferredLeadingStaticWidth, votedStaticSides.leading)
      trailingStaticWidth = max(inferredTrailingStaticWidth, votedStaticSides.trailing)
      bootstrapContentSlices(with: baseRaster)
    } else {
      // Chrome only grows, and stops changing once the votes settle: any strip
      // cut with a band too short repeats that chrome down the capture.
      headerHeight = max(headerHeight, votedStickyEdges.top)
      footerHeight = max(footerHeight, votedStickyEdges.bottom)
      leadingStaticWidth = max(leadingStaticWidth, votedStaticSides.leading)
      trailingStaticWidth = max(trailingStaticWidth, votedStaticSides.trailing)
    }

    let remainingHeight = maxOutputHeight - outputHeight
    guard remainingHeight > 0 else {
      return currentUpdate(
        outcome: .reachedHeightLimit,
        includeMergedImage: renderMergedImage,
        alignmentDebug: makeAlignmentDebugInfo(
          for: match,
          path: .heightLimit,
          usedVisionEstimate: visionAlignmentEstimate != nil,
          visionAlignmentEstimate: visionAlignmentEstimate
        )
      )
    }

    let acceptedDelta = min(match.deltaY, remainingHeight)
    guard sliceStartRow(for: match.direction, in: raster, deltaY: match.deltaY) != nil else {
      matchNotFoundCount += 1
      return currentUpdate(
        outcome: .ignoredAlignmentFailed,
        includeMergedImage: renderMergedImage,
        alignmentDebug: ScrollingCaptureAlignmentDebugInfo(
          path: .alignmentFailed,
          usedVisionEstimate: visionAlignmentEstimate != nil,
          confidence: 0,
          pixelScore: match.pixelScore,
          totalScore: match.totalScore,
          appendDeltaY: nil,
          visionAgreementCount: visionAlignmentEstimate?.agreementCount ?? 0
        )
      )
    }

    advanceTail(from: lastRaster, to: raster, deltaY: match.deltaY, acceptedDelta: acceptedDelta)
    self.lastRaster = raster
    self.lastLuma = currentLuma
    self.lastMatch = Match(
      direction: match.direction,
      deltaY: acceptedDelta,
      pixelScore: match.pixelScore,
      totalScore: match.totalScore,
      strongBandCount: match.strongBandCount,
      bandCount: match.bandCount,
      worstBandScore: match.worstBandScore,
      bandVariance: match.bandVariance
    )
    self.matchNotFoundCount = 0
    acceptedFrameCount += 1
    cachedMergedImage = nil

    let outcome: ScrollingCaptureStitchOutcome = acceptedDelta < match.deltaY
      ? .reachedHeightLimit
      : .appended(deltaY: acceptedDelta)

    return currentUpdate(
      outcome: outcome,
      includeMergedImage: renderMergedImage,
      alignmentDebug: makeAlignmentDebugInfo(
        for: match,
        path: acceptedDelta < match.deltaY ? .heightLimit : alignmentPath,
        usedVisionEstimate: visionAlignmentEstimate != nil,
        visionAlignmentEstimate: visionAlignmentEstimate,
        appendDeltaY: acceptedDelta
      )
    )
  }

  func mergedImage() -> CGImage? {
    if let cachedMergedImage {
      return cachedMergedImage
    }

    guard let baseRaster else { return nil }
    let width = baseRaster.width
    let bytesPerRow = baseRaster.bytesPerRow
    let height = outputHeight
    guard height > 0 else { return nil }

    var mergedPixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    var destinationRow = 0

    for slice in renderedSlices {
      slice.raster.copyRows(
        startRow: slice.startRow,
        rowCount: slice.rowCount,
        into: &mergedPixels,
        destinationRow: destinationRow
      )
      destinationRow += slice.rowCount
    }

    cachedMergedImage = RasterImage.makeCGImage(
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
      pixels: mergedPixels
    )
    return cachedMergedImage
  }

  func previewImage(maxPixelWidth: Int, maxPixelHeight: Int) -> CGImage? {
    guard let baseRaster else { return nil }
    let safeMaxPixelWidth = max(1, maxPixelWidth)
    let safeMaxPixelHeight = max(1, maxPixelHeight)
    let targetScale = min(
      1,
      Double(safeMaxPixelWidth) / Double(baseRaster.width),
      Double(safeMaxPixelHeight) / Double(max(outputHeight, 1))
    )

    let targetWidth = max(1, Int((Double(baseRaster.width) * targetScale).rounded()))
    let targetHeight = max(1, Int((Double(outputHeight) * targetScale).rounded()))
    let bytesPerRow = targetWidth * 4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    guard
      let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else {
      return nil
    }

    context.interpolationQuality = .medium

    var destinationRow = 0
    for slice in renderedSlices {
      guard
        let sliceImage = slice.raster.makeCroppedCGImage(
          xStart: 0,
          xEnd: slice.raster.width,
          startRow: slice.startRow,
          rowCount: slice.rowCount
        )
      else {
        destinationRow += slice.rowCount
        continue
      }

      let sourceTop = CGFloat(destinationRow) / CGFloat(max(outputHeight, 1))
      let sourceBottom = CGFloat(destinationRow + slice.rowCount) / CGFloat(max(outputHeight, 1))
      let destinationTop = CGFloat(targetHeight) * (1 - sourceTop)
      let destinationBottom = CGFloat(targetHeight) * (1 - sourceBottom)
      let destinationRect = CGRect(
        x: 0,
        y: destinationBottom,
        width: CGFloat(targetWidth),
        height: max(1, destinationTop - destinationBottom)
      )
      context.draw(sliceImage, in: destinationRect)
      destinationRow += slice.rowCount
    }

    return context.makeImage()
  }

  private func currentUpdate(
    outcome: ScrollingCaptureStitchOutcome,
    includeMergedImage: Bool = true,
    likelyReachedBoundary: Bool = false,
    safety: ScrollingCaptureStitchSafety? = nil,
    alignmentDebug: ScrollingCaptureAlignmentDebugInfo? = nil
  ) -> ScrollingCaptureStitchUpdate {
    ScrollingCaptureStitchUpdate(
      outcome: outcome,
      mergedImage: includeMergedImage ? mergedImage() : cachedMergedImage,
      acceptedFrameCount: acceptedFrameCount,
      outputHeight: outputHeight,
      matchFailureCount: matchNotFoundCount,
      mergeDirection: mergeDirection,
      likelyReachedBoundary: likelyReachedBoundary,
      safety: safety ?? defaultSafety(for: outcome),
      alignmentDebug: alignmentDebug
    )
  }

  private func defaultSafety(for outcome: ScrollingCaptureStitchOutcome) -> ScrollingCaptureStitchSafety {
    switch outcome {
    case .initialized, .appended, .ignoredNoMovement, .reachedHeightLimit:
      return .confirmed
    case .ignoredAlignmentFailed:
      return .unsafe(reason: "alignment-failed")
    }
  }

  private func makeAlignmentDebugInfo(
    for match: Match,
    path: ScrollingCaptureAlignmentPath,
    usedVisionEstimate: Bool,
    visionAlignmentEstimate: VisionAlignmentEstimate?,
    appendDeltaY: Int? = nil
  ) -> ScrollingCaptureAlignmentDebugInfo {
    ScrollingCaptureAlignmentDebugInfo(
      path: path,
      usedVisionEstimate: usedVisionEstimate,
      confidence: matcherConfidence(for: match),
      pixelScore: match.pixelScore,
      totalScore: match.totalScore,
      appendDeltaY: appendDeltaY,
      visionAgreementCount: visionAlignmentEstimate?.agreementCount ?? 0
    )
  }

  /// The base frame keeps its header, which is genuine content the first time
  /// it is seen. Its own bottom rows are edge-treated like any other frame's,
  /// so they stay in the tail until a later frame carries them clear.
  private func bootstrapContentSlices(with baseRaster: RasterImage) {
    let contentBottom = baseRaster.height - footerHeight
    let contentHeight = max(1, contentBottom - headerHeight)
    let tailStart = contentBottom - min(edgeClearance, contentHeight - 1)
    tailStartRow = tailStart
    contentSlices = [ContentSlice(raster: baseRaster, startRow: 0, rowCount: tailStart)]
  }

  /// Committed slices, then the uncommitted tail and the footer band, both
  /// drawn from the newest accepted frame. Fixed chrome along the bottom is
  /// kept out of every strip, so it appears once, at the end, in the state the
  /// capture finished in.
  private var renderedSlices: [ContentSlice] {
    guard mergeDirection != .unresolved, let lastRaster else { return contentSlices }
    let contentBottom = lastRaster.height - footerHeight
    var slices = contentSlices
    if tailRowCount > 0 {
      slices.append(
        ContentSlice(raster: lastRaster, startRow: contentBottom - tailRowCount, rowCount: tailRowCount)
      )
    }
    if footerHeight > 0 {
      slices.append(ContentSlice(raster: lastRaster, startRow: contentBottom, rowCount: footerHeight))
    }
    return slices
  }

  /// Votes with frame pairs that really moved until the estimate settles.
  /// - Returns: the chrome the votes support so far.
  private func voteOnStickyEdgesIfNeeded(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    deltaY: Int,
    columnStart: Int,
    columnEnd: Int
  ) -> ScrollingCaptureStickyEdges {
    if !chromeHasSettled, deltaY >= Self.minimumStickyMeasurementDelta {
      stickyVotes.add(
        ScrollingCaptureStickyEdgeDetector.chromeRows(
          previous: previous,
          current: current,
          columnStart: columnStart,
          columnEnd: columnEnd
        )
      )
    }
    return stickyVotes.edges(frameHeight: current.height)
  }

  private func voteOnStaticSidesIfNeeded(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    deltaY: Int,
    rowStart: Int,
    rowEnd: Int
  ) -> ScrollingCaptureStaticSides {
    if !sidesHaveSettled, deltaY >= Self.minimumStickyMeasurementDelta {
      sideVotes.add(
        ScrollingCaptureStickyEdgeDetector.staticColumns(
          previous: previous,
          current: current,
          rowStart: rowStart,
          rowEnd: rowEnd
        )
      )
    }
    return sideVotes.sides(frameWidth: current.width)
  }

  /// Rows the tail must be carried clear of the bottom edge before it is
  /// committed. Capped so it never holds back more than a third of the frame.
  private var edgeClearance: Int {
    guard let baseRaster else { return 0 }
    let usableHeight = baseRaster.height - headerHeight - footerHeight
    guard usableHeight > 0 else { return 0 }
    let measured = (measuredDimmedDepth ?? 0) + Self.edgeClearanceMargin
    return min(max(Self.minimumEdgeClearance, measured), usableHeight / 3)
  }

  /// Measured on the first few frame pairs that really moved, then frozen. The
  /// depth only ever grows, since a band that reaches further on one pair
  /// reaches that far.
  private func measureEdgeDimmingIfNeeded(
    previous: ScrollingCaptureLumaPlane,
    current: ScrollingCaptureLumaPlane,
    deltaY: Int,
    headerHeight: Int,
    footerHeight: Int,
    leadingStaticWidth: Int,
    trailingStaticWidth: Int
  ) {
    guard
      dimmingMeasurementCount < Self.maximumDimmingMeasurements,
      deltaY >= Self.minimumDimmingMeasurementDelta
    else { return }

    let columns = matchingColumnBounds(
      width: previous.width,
      leadingStaticWidth: leadingStaticWidth,
      trailingStaticWidth: trailingStaticWidth
    )
    guard
      let depth = ScrollingCaptureEdgeDimmingDetector.dimmedDepth(
        previous: previous,
        current: current,
        offset: deltaY,
        headerHeight: headerHeight,
        footerHeight: footerHeight,
        xStart: columns?.0 ?? 0,
        xEnd: columns?.1
      )
    else { return }

    dimmingMeasurementCount += 1
    measuredDimmedDepth = max(measuredDimmedDepth ?? 0, depth)
  }

  /// Moves the uncommitted tail from `previous` into `current`, which shows the
  /// content `deltaY` rows higher, and commits every tail row that now sits at
  /// least `edgeClearance` rows above the bottom edge.
  private func advanceTail(
    from previous: RasterImage,
    to current: RasterImage,
    deltaY: Int,
    acceptedDelta: Int
  ) {
    let previousContentBottom = previous.height - footerHeight
    let contentBottom = current.height - footerHeight
    var tailStart = min(tailStartRow ?? previousContentBottom, previousContentBottom)

    // Tail rows that scroll under the header in `current` can only come from
    // `previous`.
    let hiddenEnd = min(headerHeight + deltaY, previousContentBottom)
    if hiddenEnd > tailStart {
      commitRows(from: previous, startRow: tailStart, rowCount: hiddenEnd - tailStart)
      tailStart = hiddenEnd
    }

    var tailTop = min(tailStart - deltaY, contentBottom)

    // The height limit clipped this step, so nothing will follow it.
    if acceptedDelta < deltaY {
      let clippedEnd = contentBottom - deltaY + acceptedDelta
      commitRows(from: current, startRow: tailTop, rowCount: clippedEnd - tailTop)
      tailStartRow = contentBottom
      return
    }

    let clean = contentBottom - edgeClearance - tailTop
    if clean > 0 {
      commitRows(from: current, startRow: tailTop, rowCount: clean)
      tailTop += clean
    }
    tailStartRow = tailTop
  }

  private func commitRows(from raster: RasterImage, startRow: Int, rowCount: Int) {
    guard rowCount > 0 else { return }
    contentSlices.append(ContentSlice(raster: raster, startRow: startRow, rowCount: rowCount))
  }

  private func sliceStartRow(
    for direction: ScrollingCaptureMergeDirection,
    in raster: RasterImage,
    deltaY: Int
  ) -> Int? {
    switch direction {
    case .appendFromBottom:
      let contentBottom = raster.height - footerHeight
      let startRow = contentBottom - deltaY
      return startRow >= headerHeight ? startRow : nil
    case .appendFromTop:
      let startRow = headerHeight
      let contentBottom = raster.height - footerHeight
      return startRow + deltaY <= contentBottom ? startRow : nil
    case .unresolved:
      return nil
    }
  }

  private func contentDifference(
    previous: RasterImage,
    current: RasterImage,
    headerHeight: Int,
    footerHeight: Int,
    leadingStaticWidth: Int,
    trailingStaticWidth: Int
  ) -> Double {
    let contentHeight = previous.height - headerHeight - footerHeight
    guard contentHeight > 24 else { return 255 }

    guard let (xStart, xEnd) = matchingColumnBounds(
      width: previous.width,
      leadingStaticWidth: leadingStaticWidth,
      trailingStaticWidth: trailingStaticWidth
    ) else {
      return 255
    }

    let columnStride = max(2, (xEnd - xStart) / 72)
    let bandHeight = max(12, min(24, contentHeight / 8))
    let bandCount = 8
    var total = 0.0
    var count = 0

    for index in 0..<bandCount {
      let ratio = Double(index + 1) / Double(bandCount + 1)
      let row = headerHeight + min(
        max(0, contentHeight - bandHeight),
        Int(Double(max(0, contentHeight - bandHeight)) * ratio)
      )

      total += previous.blockDifference(
        comparedTo: current,
        startRow: row,
        otherStartRow: row,
        rowCount: bandHeight,
        xStart: xStart,
        xEnd: xEnd,
        columnStride: columnStride,
        rowStride: 2
      )
      count += 1
    }

    return count > 0 ? total / Double(count) : 255
  }

  private func bestMatch(
    previous: RasterImage,
    current: RasterImage,
    previousLuma: ScrollingCaptureLumaPlane,
    currentLuma: ScrollingCaptureLumaPlane,
    headerHeight: Int,
    footerHeight: Int,
    leadingStaticWidth: Int,
    trailingStaticWidth: Int,
    expectedSignedDeltaPixels: Int?,
    visionAlignmentEstimate: VisionAlignmentEstimate?,
    searchMode: MatchSearchMode
  ) -> Match? {
    let contentHeight = previous.height - headerHeight - footerHeight
    let expectedDeltaPixels = expectedSignedDeltaPixels.map(abs)
    guard let broadRange = broadDeltaRange(
      for: contentHeight,
      expectedDeltaPixels: expectedDeltaPixels,
      visionAlignmentEstimate: visionAlignmentEstimate,
      searchMode: searchMode
    ) else { return nil }

    let directions: [ScrollingCaptureMergeDirection]
    if mergeDirection == .unresolved {
      directions = [.appendFromBottom]
    } else {
      directions = [mergeDirection]
    }

    let focusedRange = focusedDeltaRange(
      inside: broadRange,
      expectedDeltaPixels: expectedDeltaPixels,
      visionAlignmentEstimate: visionAlignmentEstimate,
      searchMode: searchMode
    )

    var searchResult = searchBestMatch(
      previous: previous,
      current: current,
      headerHeight: headerHeight,
      footerHeight: footerHeight,
      leadingStaticWidth: leadingStaticWidth,
      trailingStaticWidth: trailingStaticWidth,
      directions: directions,
      deltaRange: focusedRange ?? broadRange,
      expectedDeltaPixels: expectedDeltaPixels,
      visionAlignmentEstimate: visionAlignmentEstimate,
      searchMode: searchMode
    )

    if !isAcceptable(
      searchResult?.best,
      expectedDeltaPixels: expectedDeltaPixels,
      visionAlignmentEstimate: visionAlignmentEstimate,
      searchMode: searchMode
    )
      || isAmbiguous(searchResult, expectedDeltaPixels: expectedDeltaPixels)
    {
      guard focusedRange != nil else { return nil }

      let broaderResult = searchBestMatch(
        previous: previous,
        current: current,
        headerHeight: headerHeight,
        footerHeight: footerHeight,
        leadingStaticWidth: leadingStaticWidth,
        trailingStaticWidth: trailingStaticWidth,
        directions: directions,
        deltaRange: broadRange,
        expectedDeltaPixels: expectedDeltaPixels,
        visionAlignmentEstimate: visionAlignmentEstimate,
        searchMode: searchMode
      )

      if broaderResult?.best.totalScore ?? .greatestFiniteMagnitude
        < searchResult?.best.totalScore ?? .greatestFiniteMagnitude
      {
        searchResult = broaderResult
      }
    }

    let columns = matchingColumnBounds(
      width: previous.width,
      leadingStaticWidth: leadingStaticWidth,
      trailingStaticWidth: trailingStaticWidth
    )

    func verdict(_ deltaY: Int) -> ScrollingCaptureOffsetVerifier.Verdict {
      ScrollingCaptureOffsetVerifier.verdict(
        previous: previousLuma,
        current: currentLuma,
        offset: deltaY,
        headerHeight: headerHeight,
        footerHeight: footerHeight,
        columnStart: columns?.0 ?? 0,
        columnEnd: columns?.1
      )
    }

    // The frames themselves are the authority: if content moved up by this
    // offset, every row that carries contrast lines up across the whole
    // overlap. Scores only propose candidates, because on a page with large
    // flat areas background agrees at every offset, the sampled bands tie, and
    // the scan settles on whichever candidate it happened to see first.
    // The frames themselves are the authority: if content moved up by this
    // offset, every row that carries contrast lines up across the whole
    // overlap. Scores only propose candidates, because on a page with large
    // flat areas background agrees at every offset, the sampled bands tie, and
    // the scan settles on whichever candidate it happened to see first.
    // What the scroll was asked to travel, confirmed by the frames, is the
    // strongest evidence there is, and the scan measured it to the pixel.
    func matchesExpectedStep(_ deltaY: Int) -> Bool {
      guard let expectedDeltaPixels, expectedDeltaPixels > 24 else { return false }
      return abs(deltaY - expectedDeltaPixels) <= max(12, expectedDeltaPixels / 10)
    }

    // Vision is the tie-breaker on a repeating layout, where a wrong repeat of
    // the pattern lines up as convincingly as the true offset. It is not
    // reliable enough on a flat page to overrule an offset the frames confirm
    // at the distance the page was asked to travel.
    func visionConfirms(_ deltaY: Int) -> Bool {
      guard
        let visionAlignmentEstimate,
        visionAlignmentEstimate.agreementCount >= 2,
        visionAlignmentEstimate.deltaY > 0
      else { return false }
      let tolerance = max(24, visionAlignmentEstimate.deltaY / 4)
      return abs(deltaY - visionAlignmentEstimate.deltaY) <= tolerance
    }

    // The page can travel farther than one step when frames were missed, but a
    // move shorter than the step it was asked to make is an intermediate frame
    // caught mid-scroll: committing it pins later steps to the wrong overlap.
    func isPlausibleTravel(_ deltaY: Int, visionConfirms: Bool) -> Bool {
      guard let expectedDeltaPixels, expectedDeltaPixels > 24 else { return true }
      if matchesExpectedStep(deltaY) { return true }
      // A shorter move goes through the sweep instead, which commits it only
      // when the frames confirm no competing offset.
      return deltaY > expectedDeltaPixels && visionConfirms
    }

    if let best = searchResult?.best, best.direction == .appendFromBottom,
       verdict(best.deltaY) == .verified,
       fitsExpectedStep(best.deltaY, expectedDeltaPixels: expectedDeltaPixels),
       isPlausibleTravel(best.deltaY, visionConfirms: visionConfirms(best.deltaY)) {
      return best
    }

    let confirmed = sweptVerifiedMatch(
      deltaRange: broadRange,
      previous: previous,
      current: current,
      searchBest: searchResult?.best,
      expectedDeltaPixels: expectedDeltaPixels,
      headerHeight: headerHeight,
      footerHeight: footerHeight,
      leadingStaticWidth: leadingStaticWidth,
      trailingStaticWidth: trailingStaticWidth,
      visionAlignmentEstimate: visionAlignmentEstimate,
      verdict: verdict
    )
    if let confirmed {
      return confirmed
    }

    // Nothing in the overlap carries enough content to judge by, so fall back
    // to the score gates.
    guard
      let searchResult,
      verdict(searchResult.best.deltaY) == .noEvidence,
      isAcceptable(
        searchResult.best,
        expectedDeltaPixels: expectedDeltaPixels,
        visionAlignmentEstimate: visionAlignmentEstimate,
        searchMode: searchMode
      ),
      !isAmbiguous(searchResult, expectedDeltaPixels: expectedDeltaPixels)
    else {
      return nil
    }
    return searchResult.best
  }

  /// A confirmed offset still has to be a plausible step. An intermediate frame
  /// caught mid-scroll really did move a few pixels, so it is confirmed, but
  /// committing it pins later steps to the wrong overlap.
  private func fitsExpectedStep(_ deltaY: Int, expectedDeltaPixels: Int?) -> Bool {
    guard let expectedDeltaPixels, expectedDeltaPixels > 24 else { return true }
    // A page often travels a little less than it was asked to, and farther when
    // frames were missed. Only a small fraction of the step is implausible.
    return deltaY >= max(18, expectedDeltaPixels / 2) && deltaY <= expectedDeltaPixels * 2
  }

  /// Sweeps the plausible range with the verifier and takes the confirmed run
  /// of offsets that best fits how far the scroll was expected to travel. This
  /// is what a flat page needs: judging content rows over the whole overlap
  /// separates offsets that the band scores cannot.
  private func sweptVerifiedMatch(
    deltaRange: ClosedRange<Int>,
    previous: RasterImage,
    current: RasterImage,
    searchBest: Match?,
    expectedDeltaPixels: Int?,
    headerHeight: Int,
    footerHeight: Int,
    leadingStaticWidth: Int,
    trailingStaticWidth: Int,
    visionAlignmentEstimate: VisionAlignmentEstimate?,
    verdict: (Int) -> ScrollingCaptureOffsetVerifier.Verdict
  ) -> Match? {
    // The band of offsets the frames confirm is only a few pixels wide around a
    // true offset, so a coarse sweep walks straight past it. Step by one pixel
    // across the range the scroll plausibly travelled, and coarsely elsewhere.
    let coarseStep = max(2, (deltaRange.upperBound - deltaRange.lowerBound) / 220)
    var probes: [Int] = []
    if let expectedDeltaPixels, expectedDeltaPixels > 24 {
      let fineLower = max(deltaRange.lowerBound, expectedDeltaPixels / 2)
      let fineUpper = min(deltaRange.upperBound, expectedDeltaPixels * 2)
      if fineLower <= fineUpper {
        probes.append(contentsOf: fineLower...fineUpper)
      }
    }
    probes.append(
      contentsOf: stride(from: deltaRange.lowerBound, through: deltaRange.upperBound, by: coarseStep)
    )

    var runs: [[Int]] = []
    for delta in Set(probes).sorted() where verdict(delta) == .verified {
      if var last = runs.last, let tail = last.last, delta - tail <= coarseStep * 2 {
        last.append(delta)
        runs[runs.count - 1] = last
      } else {
        runs.append([delta])
      }
    }
    guard !runs.isEmpty else { return nil }

    let centers = runs.map { $0[$0.count / 2] }
    let chosenCenter: Int
    if centers.count == 1, let only = centers.first {
      // One confirmed answer needs no tie-breaking.
      chosenCenter = only
    } else if let visionAlignmentEstimate, visionAlignmentEstimate.agreementCount >= 2,
              visionAlignmentEstimate.deltaY > 0,
              let nearest = centers.min(by: {
                abs($0 - visionAlignmentEstimate.deltaY) < abs($1 - visionAlignmentEstimate.deltaY)
              }),
              abs(nearest - visionAlignmentEstimate.deltaY) <= max(24, visionAlignmentEstimate.deltaY / 4) {
      // A repeating layout confirms the wrong repeat as readily as the true
      // offset, so what Vision saw decides between them.
      chosenCenter = nearest
    } else if let expectedDeltaPixels, expectedDeltaPixels > 0,
              let nearest = centers.min(by: {
                abs($0 - expectedDeltaPixels) < abs($1 - expectedDeltaPixels)
              }),
              abs(nearest - expectedDeltaPixels) <= max(96, expectedDeltaPixels / 2) {
      // Several confirmed runs with nothing to separate them: only the one the
      // page was actually asked to travel is safe to commit.
      chosenCenter = nearest
    } else {
      return nil
    }

    guard
      let chosenRun = runs.first(where: { $0[$0.count / 2] == chosenCenter }),
      let runStart = chosenRun.first,
      let runEnd = chosenRun.last
    else { return nil }

    // A flat page confirms a wide band of offsets, so the run says which
    // neighbourhood is right, not which pixel. The scan measured to the pixel,
    // so its answer wins whenever it falls inside the confirmed run.
    var deltaY = chosenCenter
    if let searchBest, searchBest.direction == .appendFromBottom,
       searchBest.deltaY >= runStart - coarseStep, searchBest.deltaY <= runEnd + coarseStep,
       verdict(searchBest.deltaY) == .verified {
      deltaY = searchBest.deltaY
    } else if let expectedDeltaPixels, expectedDeltaPixels > 0,
              expectedDeltaPixels >= runStart - coarseStep, expectedDeltaPixels <= runEnd + coarseStep,
              verdict(expectedDeltaPixels) == .verified {
      // Otherwise the step the scroll was asked to travel, when the frames
      // confirm it, beats the middle of a band.
      deltaY = expectedDeltaPixels
    } else {
      var refined: [Int] = []
      let lower = max(deltaRange.lowerBound, chosenCenter - coarseStep)
      let upper = min(deltaRange.upperBound, chosenCenter + coarseStep)
      for delta in lower...upper where verdict(delta) == .verified {
        refined.append(delta)
      }
      if !refined.isEmpty { deltaY = refined[refined.count / 2] }
    }

    guard fitsExpectedStep(deltaY, expectedDeltaPixels: expectedDeltaPixels) else { return nil }

    // A page often travels a little less than it was asked to, and that is
    // worth committing. Much less than asked is what an intermediate frame
    // caught mid-scroll looks like, and a repeating layout confirms such an
    // offset as readily as the real one. A viewport independently verified as
    // settled comes back through `allowsSettledPartialStep`, which lowers the
    // expected step to what Vision measured, so a genuine short travel is
    // committed on the retry instead.
    if let expectedDeltaPixels, expectedDeltaPixels > 24, deltaY < expectedDeltaPixels {
      let tolerance = max(16, expectedDeltaPixels / 5)
      guard expectedDeltaPixels - deltaY <= tolerance else { return nil }
    }

    guard let metrics = overlapMetrics(
      previous: previous,
      current: current,
      direction: .appendFromBottom,
      deltaY: deltaY,
      headerHeight: headerHeight,
      footerHeight: footerHeight,
      leadingStaticWidth: leadingStaticWidth,
      trailingStaticWidth: trailingStaticWidth
    ) else { return nil }

    return Match(
      direction: .appendFromBottom,
      deltaY: deltaY,
      pixelScore: metrics.averageDifference,
      totalScore: metrics.averageDifference,
      strongBandCount: metrics.strongBandCount,
      bandCount: metrics.bandCount,
      worstBandScore: metrics.worstDifference,
      bandVariance: metrics.variance
    )
  }

  private func broadDeltaRange(
    for contentHeight: Int,
    expectedDeltaPixels: Int?,
    visionAlignmentEstimate: VisionAlignmentEstimate?,
    searchMode: MatchSearchMode
  ) -> ClosedRange<Int>? {
    let defaultMinOverlap = max(160, Int(Double(contentHeight) * 0.26))
    let aggressiveMinOverlap = max(96, Int(Double(contentHeight) * 0.16))
    let defaultMinDelta = max(14, min(120, contentHeight / 28))
    let signalMinDelta: Int
    let signalMinOverlap: Int

    if searchMode == .guided, let expectedDeltaPixels, expectedDeltaPixels > 0 {
      signalMinDelta = max(12, expectedDeltaPixels / 2)
      signalMinOverlap = contentHeight - expectedDeltaPixels
    } else if searchMode == .guided, let lastMatch {
      signalMinDelta = max(12, lastMatch.deltaY / 2)
      signalMinOverlap = contentHeight - lastMatch.deltaY
    } else {
      signalMinDelta = defaultMinDelta
      signalMinOverlap = defaultMinOverlap
    }

    var minimumOverlapFloor = aggressiveMinOverlap
    var preferredMinimumOverlap = signalMinOverlap

    if let visionAlignmentEstimate, visionAlignmentEstimate.deltaY > 0 {
      let visionOverlapFloor = visionAlignmentEstimate.agreementCount >= 2
        ? max(56, Int(Double(contentHeight) * 0.08))
        : aggressiveMinOverlap
      minimumOverlapFloor = min(minimumOverlapFloor, visionOverlapFloor)
      preferredMinimumOverlap = min(
        preferredMinimumOverlap,
        max(visionOverlapFloor, contentHeight - visionAlignmentEstimate.deltaY)
      )
    }

    let minDelta = min(defaultMinDelta, signalMinDelta)
    let minOverlap = max(minimumOverlapFloor, min(defaultMinOverlap, preferredMinimumOverlap))
    let maxDelta = max(minDelta, contentHeight - minOverlap)
    return maxDelta > minDelta ? minDelta...maxDelta : nil
  }

  private func focusedDeltaRange(
    inside broadRange: ClosedRange<Int>,
    expectedDeltaPixels: Int?,
    visionAlignmentEstimate: VisionAlignmentEstimate?,
    searchMode: MatchSearchMode
  ) -> ClosedRange<Int>? {
    guard searchMode == .guided || visionAlignmentEstimate != nil else { return nil }

    var centers: [Int] = []

    if let expectedDeltaPixels, expectedDeltaPixels > 0 {
      centers.append(clamp(expectedDeltaPixels, to: broadRange))
    }

    if let lastMatch, lastMatchAgreesWithExpected(
      lastMatchDelta: lastMatch.deltaY,
      expectedDeltaPixels: expectedDeltaPixels
    ) {
      centers.append(clamp(lastMatch.deltaY, to: broadRange))
    }

    if let visionAlignmentEstimate, visionAlignmentEstimate.deltaY > 0 {
      let clampedVisionDelta = clamp(visionAlignmentEstimate.deltaY, to: broadRange)
      let repeatCount = max(2, visionAlignmentEstimate.agreementCount + 1)
      for _ in 0..<repeatCount {
        centers.append(clampedVisionDelta)
      }
    }

    guard !centers.isEmpty else { return nil }

    let center = Int(round(Double(centers.reduce(0, +)) / Double(centers.count)))
    let spread = max(28, min(96, center / 2 + 12))
    let lower = max(broadRange.lowerBound, center - spread)
    let upper = min(broadRange.upperBound, center + spread)
    return lower < upper ? lower...upper : nil
  }

  private func searchBestMatch(
    previous: RasterImage,
    current: RasterImage,
    headerHeight: Int,
    footerHeight: Int,
    leadingStaticWidth: Int,
    trailingStaticWidth: Int,
    directions: [ScrollingCaptureMergeDirection],
    deltaRange: ClosedRange<Int>,
    expectedDeltaPixels: Int?,
    visionAlignmentEstimate: VisionAlignmentEstimate?,
    searchMode: MatchSearchMode
  ) -> MatchSearchResult? {
    let contentHeight = previous.height - headerHeight - footerHeight
    let coarseStep = max(2, min(10, contentHeight / 160))
    var coarseCandidates: [Match] = []

    for direction in directions {
      for delta in stride(from: deltaRange.lowerBound, through: deltaRange.upperBound, by: coarseStep) {
        guard let metrics = overlapMetrics(
          previous: previous,
          current: current,
          direction: direction,
          deltaY: delta,
          headerHeight: headerHeight,
          footerHeight: footerHeight,
          leadingStaticWidth: leadingStaticWidth,
          trailingStaticWidth: trailingStaticWidth
        ) else {
          continue
        }

        let totalScore = metrics.averageDifference
          + consistencyPenalty(for: metrics, searchMode: searchMode)
          + priorPenalty(
          deltaY: delta,
          expectedDeltaPixels: expectedDeltaPixels,
          visionAlignmentEstimate: visionAlignmentEstimate,
          direction: direction,
          searchMode: searchMode
        )

        let candidate = Match(
          direction: direction,
          deltaY: delta,
          pixelScore: metrics.averageDifference,
          totalScore: totalScore,
          strongBandCount: metrics.strongBandCount,
          bandCount: metrics.bandCount,
          worstBandScore: metrics.worstDifference,
          bandVariance: metrics.variance
        )

        coarseCandidates.append(candidate)
      }
    }

    guard
      let coarseBest = coarseCandidates.min(by: { $0.totalScore < $1.totalScore })
    else {
      return nil
    }

    let refineRadius = max(8, coarseStep * 2)
    let refineStart = max(deltaRange.lowerBound, coarseBest.deltaY - refineRadius)
    let refineEnd = min(deltaRange.upperBound, coarseBest.deltaY + refineRadius)
    var refinedBest = coarseBest

    for delta in refineStart...refineEnd {
      guard let metrics = overlapMetrics(
        previous: previous,
        current: current,
        direction: coarseBest.direction,
        deltaY: delta,
        headerHeight: headerHeight,
        footerHeight: footerHeight,
        leadingStaticWidth: leadingStaticWidth,
        trailingStaticWidth: trailingStaticWidth
      ) else {
        continue
      }

      let totalScore = metrics.averageDifference
        + consistencyPenalty(for: metrics, searchMode: searchMode)
        + priorPenalty(
        deltaY: delta,
        expectedDeltaPixels: expectedDeltaPixels,
        visionAlignmentEstimate: visionAlignmentEstimate,
        direction: coarseBest.direction,
        searchMode: searchMode
      )

      if totalScore < refinedBest.totalScore {
        refinedBest = Match(
          direction: coarseBest.direction,
          deltaY: delta,
          pixelScore: metrics.averageDifference,
          totalScore: totalScore,
          strongBandCount: metrics.strongBandCount,
          bandCount: metrics.bandCount,
          worstBandScore: metrics.worstDifference,
          bandVariance: metrics.variance
        )
      }
    }

    let ambiguityWindow = max(24, coarseStep * 3)
    let runnerUp = coarseCandidates
      .filter { candidate in
        candidate.direction != refinedBest.direction || abs(candidate.deltaY - refinedBest.deltaY) > ambiguityWindow
      }
      .min(by: { $0.totalScore < $1.totalScore })

    return MatchSearchResult(best: refinedBest, runnerUp: runnerUp)
  }

  private func overlapMetrics(
    previous: RasterImage,
    current: RasterImage,
    direction: ScrollingCaptureMergeDirection,
    deltaY: Int,
    headerHeight: Int,
    footerHeight: Int,
    leadingStaticWidth: Int,
    trailingStaticWidth: Int
  ) -> OverlapMetrics? {
    let contentHeight = previous.height - headerHeight - footerHeight
    let overlapHeight = contentHeight - deltaY
    guard overlapHeight > 24 else { return nil }

    guard let (xStart, xEnd) = matchingColumnBounds(
      width: previous.width,
      leadingStaticWidth: leadingStaticWidth,
      trailingStaticWidth: trailingStaticWidth
    ) else {
      return nil
    }

    let columnStride = max(2, (xEnd - xStart) / 72)
    let bandCount = min(10, max(6, overlapHeight / 80))
    let bandHeight = max(12, min(28, overlapHeight / max(3, bandCount + 1)))
    var differences: [Double] = []
    differences.reserveCapacity(bandCount)

    for index in 0..<bandCount {
      let ratio = Double(index + 1) / Double(bandCount + 1)
      let rowOffset = min(
        max(0, overlapHeight - bandHeight),
        Int(Double(max(0, overlapHeight - bandHeight)) * ratio)
      )

      let previousRow: Int
      let currentRow: Int

      switch direction {
      case .appendFromBottom:
        previousRow = headerHeight + deltaY + rowOffset
        currentRow = headerHeight + rowOffset
      case .appendFromTop:
        previousRow = headerHeight + rowOffset
        currentRow = headerHeight + deltaY + rowOffset
      case .unresolved:
        return nil
      }

      let difference = previous.blockDifference(
        comparedTo: current,
        startRow: previousRow,
        otherStartRow: currentRow,
        rowCount: bandHeight,
        xStart: xStart,
        xEnd: xEnd,
        columnStride: columnStride,
        rowStride: 2
      )
      differences.append(difference)
    }

    guard !differences.isEmpty else { return nil }

    let averageDifference = differences.reduce(0.0, +) / Double(differences.count)
    let strongThreshold = max(8.2, min(10.5, averageDifference * 0.92))
    let strongBandCount = differences.filter { $0 <= strongThreshold }.count
    let worstDifference = differences.max() ?? averageDifference
    let variance = differences.reduce(0.0) { partialResult, difference in
      let delta = difference - averageDifference
      return partialResult + delta * delta
    } / Double(differences.count)

    return OverlapMetrics(
      averageDifference: averageDifference,
      strongBandCount: strongBandCount,
      bandCount: differences.count,
      worstDifference: worstDifference,
      variance: variance
    )
  }

  private func consistencyPenalty(
    for metrics: OverlapMetrics,
    searchMode: MatchSearchMode
  ) -> Double {
    guard metrics.bandCount > 0 else { return 255 }

    let strongRatio = Double(metrics.strongBandCount) / Double(metrics.bandCount)
    let weakBandCount = max(0, metrics.bandCount - metrics.strongBandCount)
    var penalty = Double(weakBandCount) * (searchMode == .guided ? 1.1 : 0.9)

    if strongRatio < 0.5 {
      penalty += (0.5 - strongRatio) * (searchMode == .guided ? 9 : 7)
    }

    if metrics.worstDifference > 18 {
      penalty += min(6, (metrics.worstDifference - 18) * 0.4)
    }

    if metrics.variance > 14 {
      penalty += min(5, (metrics.variance - 14) * 0.3)
    }

    return penalty
  }

  private func priorPenalty(
    deltaY: Int,
    expectedDeltaPixels: Int?,
    visionAlignmentEstimate: VisionAlignmentEstimate?,
    direction: ScrollingCaptureMergeDirection,
    searchMode: MatchSearchMode
  ) -> Double {
    var penalty = 0.0

    if searchMode == .guided, let expectedDeltaPixels, expectedDeltaPixels > 0 {
      penalty += deviationPenalty(candidate: deltaY, expected: expectedDeltaPixels, weight: 22)

      let largeLeapThreshold = max(expectedDeltaPixels * 2, expectedDeltaPixels + 180)
      if deltaY > largeLeapThreshold {
        penalty += 14
      }
    }

    if searchMode == .guided, let lastMatch, lastMatchAgreesWithExpected(
      lastMatchDelta: lastMatch.deltaY,
      expectedDeltaPixels: expectedDeltaPixels
    ) {
      penalty += deviationPenalty(candidate: deltaY, expected: lastMatch.deltaY, weight: 18)

      let largeLeapThreshold = max(lastMatch.deltaY * 2, lastMatch.deltaY + 160)
      if deltaY > largeLeapThreshold {
        penalty += 10
      }
    }

    if let visionAlignmentEstimate, visionAlignmentEstimate.deltaY > 0 {
      let agreementBonus = Double(max(0, visionAlignmentEstimate.agreementCount - 1)) * 6.0
      let spreadDiscount = Double(min(visionAlignmentEstimate.deltaSpread, 12)) * 0.4
      let weight = (searchMode == .guided ? 24.0 : 30.0) + agreementBonus - spreadDiscount
      penalty += deviationPenalty(candidate: deltaY, expected: visionAlignmentEstimate.deltaY, weight: weight)

      let largeLeapThreshold = max(
        visionAlignmentEstimate.deltaY * 2,
        visionAlignmentEstimate.deltaY + max(96, 148 - visionAlignmentEstimate.agreementCount * 18)
      )
      if deltaY > largeLeapThreshold {
        penalty += searchMode == .guided ? 8 : 12
      }
    }

    if mergeDirection != .unresolved && direction != mergeDirection {
      penalty += 1_000
    }

    return penalty
  }

  private func deviationPenalty(candidate: Int, expected: Int, weight: Double) -> Double {
    let baseline = max(1, expected)
    let deviation = Double(abs(candidate - expected)) / Double(baseline)
    return deviation * weight
  }

  private func lastMatchAgreesWithExpected(
    lastMatchDelta: Int,
    expectedDeltaPixels: Int?
  ) -> Bool {
    guard let expectedDeltaPixels, expectedDeltaPixels > 0 else { return true }
    let tolerance = max(28, expectedDeltaPixels / 2)
    return abs(lastMatchDelta - expectedDeltaPixels) <= tolerance
  }

  private func isVerifiedSettledPartialMatch(
    _ match: Match,
    expectedDeltaPixels: Int,
    visionAlignmentEstimate: VisionAlignmentEstimate?,
    allowed: Bool
  ) -> Bool {
    guard allowed, match.deltaY < expectedDeltaPixels,
          let estimate = visionAlignmentEstimate, estimate.agreementCount >= 2 else { return false }
    return abs(estimate.deltaY - match.deltaY) <= 2
      && match.pixelScore < 2
      && match.bandVariance < 2
      && matcherConfidence(for: match) >= 0.9
  }

  private func stronglyContradictsKnownStep(
    _ match: Match,
    expectedDeltaPixels: Int,
    visionAlignmentEstimate: VisionAlignmentEstimate?
  ) -> Bool {
    let error = abs(match.deltaY - expectedDeltaPixels)
    let tooLarge = error > max(48, Int(Double(expectedDeltaPixels) * 1.35))
    let tooSmall = match.deltaY < max(18, expectedDeltaPixels / 2)
    guard tooLarge || tooSmall else { return false }

    let confidence = matcherConfidence(for: match)
    let visionDelta = visionAlignmentEstimate?.deltaY ?? 0
    let independentlyStrong =
      confidence >= 0.88
      && match.pixelScore < 6.5
      && (visionAlignmentEstimate?.agreementCount ?? 0) >= 2
      && visionDelta > 0
      && abs(visionDelta - match.deltaY) <= max(24, expectedDeltaPixels / 4)
      && error <= max(56, Int(Double(expectedDeltaPixels) * 0.65))

    return !independentlyStrong
  }

  private func isAcceptable(
    _ match: Match?,
    expectedDeltaPixels: Int?,
    visionAlignmentEstimate: VisionAlignmentEstimate?,
    searchMode: MatchSearchMode
  ) -> Bool {
    guard let match else { return false }

    switch searchMode {
    case .guided:
      guard match.pixelScore < 18 && match.totalScore < 28 else { return false }
    case .recovery:
      guard match.pixelScore < 20.5 && match.totalScore < 31 else { return false }
    }

    let requiredStrongBands = searchMode == .guided
      ? max(3, match.bandCount / 2)
      : max(3, match.bandCount / 3)
    let bandCredit = max(0, (visionAlignmentEstimate?.agreementCount ?? 0) - 1)
    if match.strongBandCount + bandCredit < requiredStrongBands && match.pixelScore > 8.8 {
      return false
    }

    if match.worstBandScore > (searchMode == .guided ? 26 : 29), match.bandVariance > 18 {
      return false
    }

    if let expectedDeltaPixels, expectedDeltaPixels > 0 {
      let tolerance = max(28, expectedDeltaPixels)
      if abs(match.deltaY - expectedDeltaPixels) > tolerance && match.pixelScore > 9.5 {
        return false
      }
    }

    if let visionAlignmentEstimate, visionAlignmentEstimate.deltaY > 0 {
      let tolerance = searchMode == .guided
        ? max(20, visionAlignmentEstimate.deltaY / max(2, visionAlignmentEstimate.agreementCount))
        : max(32, Int(Double(visionAlignmentEstimate.deltaY) * 0.65))
      if abs(match.deltaY - visionAlignmentEstimate.deltaY) > tolerance && match.pixelScore > 10.5 {
        return false
      }
    }

    return true
  }

  private func isAmbiguous(
    _ searchResult: MatchSearchResult?,
    expectedDeltaPixels: Int?
  ) -> Bool {
    guard
      let searchResult,
      let runnerUp = searchResult.runnerUp
    else {
      return false
    }

    let best = searchResult.best
    let scoreGap = runnerUp.totalScore - best.totalScore
    let pixelGap = runnerUp.pixelScore - best.pixelScore
    let deltaGap = abs(runnerUp.deltaY - best.deltaY)
    let directionConflict = runnerUp.direction != best.direction

    if directionConflict && scoreGap < 2.4 {
      return true
    }

    if deltaGap >= max(40, best.deltaY / 3) && scoreGap < 1.3 {
      return true
    }

    if deltaGap >= max(28, best.deltaY / 4) && pixelGap < 0.9 && best.pixelScore > 8.5 {
      return true
    }

    if best.pixelScore > 14 && scoreGap < 2.0 {
      return true
    }

    if let expectedDeltaPixels, expectedDeltaPixels > 0 {
      let tolerance = max(56, expectedDeltaPixels / 2)
      if abs(best.deltaY - expectedDeltaPixels) > tolerance && scoreGap < 3.2 {
        return true
      }
    }

    return false
  }

  private func matcherConfidence(for match: Match) -> Double {
    let pixelComponent = max(0, 1 - match.pixelScore / 20)
    let totalComponent = max(0, 1 - match.totalScore / 32)
    let strongBandComponent = Double(match.strongBandCount) / Double(max(1, match.bandCount))
    let variancePenalty = min(1, match.bandVariance / 30)

    let confidence =
      pixelComponent * 0.4 +
      totalComponent * 0.3 +
      strongBandComponent * 0.2 +
      (1 - variancePenalty) * 0.1

    return min(1, max(0, confidence))
  }

  private func shouldValidateFastGuidedMatch(
    _ match: Match?,
    visionAlignmentEstimate: VisionAlignmentEstimate?
  ) -> Bool {
    guard let match else { return true }
    guard let visionAlignmentEstimate, visionAlignmentEstimate.deltaY > 0 else { return false }

    return matcherConfidence(for: match) < 0.82
      || fastGuidedMatchDisagreesWithVision(match, visionAlignmentEstimate: visionAlignmentEstimate)
  }

  private func fastGuidedMatchDisagreesWithVision(
    _ match: Match?,
    visionAlignmentEstimate: VisionAlignmentEstimate?
  ) -> Bool {
    guard let match, let visionAlignmentEstimate, visionAlignmentEstimate.deltaY > 0 else { return false }

    let tolerance: Int
    if visionAlignmentEstimate.agreementCount >= 2 {
      tolerance = max(18, visionAlignmentEstimate.deltaY / 3)
    } else {
      tolerance = max(32, visionAlignmentEstimate.deltaY / 2)
    }

    return abs(match.deltaY - visionAlignmentEstimate.deltaY) > tolerance
  }

  private func hasStrongVisionMovement(_ visionAlignmentEstimate: VisionAlignmentEstimate?) -> Bool {
    guard let visionAlignmentEstimate else { return false }
    return visionAlignmentEstimate.agreementCount >= 2 && visionAlignmentEstimate.deltaY >= 10
  }

  private func isLikelyDuplicateBoundary(
    frameDifference: Double,
    match: Match?,
    expectedDeltaPixels: Int?,
    visionAlignmentEstimate: VisionAlignmentEstimate?
  ) -> Bool {
    guard frameDifference < 8.5 else { return false }
    guard !hasStrongVisionMovement(visionAlignmentEstimate) else { return false }
    guard let match else { return true }

    let priorDelta = lastMatch?.deltaY ?? 0
    let baselineDelta = max(priorDelta, expectedDeltaPixels ?? 0)
    let suspiciousDeltaCeiling = max(18, min(36, max(baselineDelta / 2, priorDelta / 3)))
    let suspiciousExpectedMismatch = baselineDelta > 0 && match.deltaY < max(18, baselineDelta / 2)
    let lowConfidence = matcherConfidence(for: match) < 0.84

    return lowConfidence || suspiciousExpectedMismatch || match.deltaY <= suspiciousDeltaCeiling
  }

  private func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
    min(range.upperBound, max(range.lowerBound, value))
  }

  private func estimateVisionAlignment(
    previous: RasterImage,
    current: RasterImage,
    headerHeight: Int,
    footerHeight: Int,
    leadingStaticWidth: Int,
    trailingStaticWidth: Int
  ) -> VisionAlignmentEstimate? {
    guard let (xStart, xEnd) = matchingColumnBounds(
      width: previous.width,
      leadingStaticWidth: leadingStaticWidth,
      trailingStaticWidth: trailingStaticWidth
    ) else {
      return nil
    }

    let contentHeight = previous.height - headerHeight - footerHeight
    guard contentHeight > 80 else { return nil }

    let verticalTrim = min(24, max(6, contentHeight / 24))
    let startRow = headerHeight + verticalTrim
    let rowCount = contentHeight - verticalTrim * 2
    guard rowCount > 64 else { return nil }

    var regions: [(xStart: Int, xEnd: Int, startRow: Int, rowCount: Int)] = [
      (xStart, xEnd, startRow, rowCount)
    ]

    let contentWidth = xEnd - xStart
    if contentWidth > 220 {
      let horizontalTrim = max(14, min(36, contentWidth / 8))
      regions.append((
        xStart + horizontalTrim,
        xEnd - horizontalTrim,
        startRow,
        rowCount
      ))
    }

    if rowCount > 170 {
      let centeredRowCount = max(96, Int(Double(rowCount) * 0.72))
      let centeredStartRow = startRow + (rowCount - centeredRowCount) / 2
      regions.append((xStart, xEnd, centeredStartRow, centeredRowCount))
    }

    var samples: [Int] = []

    for region in regions {
      if let delta = estimateVisionTranslation(
        previous: previous,
        current: current,
        xStart: region.xStart,
        xEnd: region.xEnd,
        startRow: region.startRow,
        rowCount: region.rowCount
      ) {
        samples.append(delta)
      }
    }

    guard !samples.isEmpty else { return nil }

    let sortedSamples = samples.sorted()
    var bestCluster: [Int] = []

    for sample in sortedSamples {
      let tolerance = max(6, sample / 10)
      let cluster = sortedSamples.filter { abs($0 - sample) <= tolerance }
      if cluster.count > bestCluster.count {
        bestCluster = cluster
      }
    }

    let chosenSamples = bestCluster.isEmpty ? sortedSamples : bestCluster
    let medianIndex = chosenSamples.count / 2
    let deltaY = chosenSamples[medianIndex]
    let deltaSpread = max(0, (chosenSamples.last ?? deltaY) - (chosenSamples.first ?? deltaY))

    return VisionAlignmentEstimate(
      deltaY: deltaY,
      agreementCount: chosenSamples.count,
      observedCount: samples.count,
      deltaSpread: deltaSpread
    )
  }

  private func estimateVisionTranslation(
    previous: RasterImage,
    current: RasterImage,
    xStart: Int,
    xEnd: Int,
    startRow: Int,
    rowCount: Int
  ) -> Int? {
    guard
      let previousImage = previous.makeCroppedCGImage(
        xStart: xStart,
        xEnd: xEnd,
        startRow: startRow,
        rowCount: rowCount
      ),
      let currentImage = current.makeCroppedCGImage(
        xStart: xStart,
        xEnd: xEnd,
        startRow: startRow,
        rowCount: rowCount
      )
    else {
      return nil
    }

    let request = VNTranslationalImageRegistrationRequest(
      targetedCGImage: currentImage,
      options: [:],
      completionHandler: nil
    )
    let handler = VNSequenceRequestHandler()

    do {
      try handler.perform([request], on: previousImage)
    } catch {
      return nil
    }

    guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
      return nil
    }

    let transform = observation.alignmentTransform
    let horizontalShift = abs(transform.tx)
    let verticalShift = abs(transform.ty)

    guard horizontalShift.isFinite, verticalShift.isFinite else { return nil }
    guard verticalShift >= 6 else { return nil }
    guard horizontalShift <= max(10, CGFloat(previousImage.width) * 0.03) else { return nil }

    let deltaY = Int(round(verticalShift))
    let maxUsefulDelta = max(18, rowCount - max(72, Int(Double(rowCount) * 0.12)))
    guard deltaY <= maxUsefulDelta else { return nil }

    return deltaY
  }

  private func matchingColumnBounds(
    width: Int,
    leadingStaticWidth: Int,
    trailingStaticWidth: Int
  ) -> (Int, Int)? {
    let safetyInset = max(10, width / 48)
    let xStart = max(leadingStaticWidth, leadingStaticWidth + safetyInset)
    let xEnd = min(width, width - trailingStaticWidth - safetyInset)
    guard xEnd - xStart >= max(48, width / 5) else {
      let fallbackStart = min(max(0, leadingStaticWidth), max(0, width - 2))
      let fallbackEnd = max(fallbackStart + 1, width - trailingStaticWidth)
      return fallbackEnd - fallbackStart >= max(40, width / 6)
        ? (fallbackStart, fallbackEnd)
        : nil
    }

    return (xStart, xEnd)
  }
}
