//
//  VideoEditorControlsFitPolicyTests.swift
//  SnapzyTests
//
//  Geometry coverage for the playback controls row's badge decision (issue #780).
//

import AppKit
@testable import Snapzy
import SwiftUI
import XCTest

/// The badge decision reads one number: the width the trailing side frame was actually given.
/// These tests pin that rule against the widths measured from the #780 screenshot; the frame
/// widths themselves are measured in `VideoControlsLayoutLawTests`, on a copy of the row's
/// structure, so nothing below assumes how SwiftUI divides the row.
final class VideoEditorControlsFitPolicyTests: XCTestCase {
  // Widths as they come out at the reported size: the `.compact` style of a ~530 pt controls
  // container inside a 1200 pt window with both sidebars and the AI panel open.
  private let badgeSpacing: CGFloat = 6
  private let zoom: CGFloat = 74 // minus / fit / plus capsule
  private let status: CGFloat = 129 // zoom count + ✂ trimmed duration badges

  private func shows(trailing: CGFloat, zoom: CGFloat = 74, status: CGFloat = 129) -> Bool {
    VideoControlsFitPolicy.showsStatus(
      trailingWidth: trailing,
      zoomWidth: zoom,
      statusWidth: status,
      badgeSpacing: badgeSpacing
    )
  }

  func testReportedSize_hidesBadgesBecauseTheTrailingFrameCannotHoldThem() {
    // 147 pt is what the trailing frame is laid out in at a 530 pt container, measured in
    // `VideoControlsLayoutLawTests`; the group needs 209 pt.
    XCTAssertFalse(shows(trailing: 147))
  }

  /// The bug itself, in one line: the four clusters really do pack into the container, which is
  /// what the old check priced the badges against, while the trailing side is given only part of
  /// what is left. If the two models ever agree again, this test says so.
  func testOldPackingArithmeticWasTheFlaw() {
    let container: CGFloat = 530
    let leading: CGFloat = 76
    let transport: CGFloat = 212
    let outerSpacing: CGFloat = 12
    XCTAssertLessThanOrEqual(
      leading + transport + zoom + badgeSpacing + status + 2 * outerSpacing,
      container,
      "old model: the row packs into 521 of the 530 pt, so the badges were priced as fitting"
    )
    XCTAssertFalse(
      shows(trailing: 147),
      "new model: the 147 pt the trailing side is laid out in cannot hold the group"
    )
  }

  func testThreshold_isTheGroupWidthExactly() {
    let group = zoom + badgeSpacing + status
    XCTAssertTrue(shows(trailing: group))
    XCTAssertFalse(shows(trailing: group - 1))
  }

  /// The point of measuring the frame instead of deriving it: whatever the row decides to give the
  /// trailing side — a narrow container, an oversized leading cluster, a different layout style —
  /// the badges are priced against that number and nothing else.
  func testDecisionFollowsTheFrameNotAnAssumptionAboutTheRow() {
    let group = zoom + badgeSpacing + status
    for trailing in stride(from: CGFloat(1), through: 400, by: 1) {
      XCTAssertEqual(shows(trailing: trailing), trailing >= group, "at \(trailing) pt of frame")
    }
  }

  func testUnmeasuredWidths_keepTheFirstPassLayout() {
    // The measurements arrive one pass after the view appears, so an unknown anything must not
    // hide the badges forever.
    XCTAssertTrue(shows(trailing: 0))
    XCTAssertTrue(shows(trailing: 500, status: 0))
    XCTAssertTrue(shows(trailing: 500, zoom: 0))
  }

  /// Whatever the decision, the configuration it chose fits the frame it was priced against — the
  /// invariant the #780 overlap broke. Swept from the zoom cluster's own width up: below it the
  /// cluster that is part of the row's minimum is what no longer fits, which is a regime the badge
  /// decision cannot fix and the row's minimum keeps the window out of.
  func testShowingBadgesAlwaysImpliesTheGroupFitsItsFrame() {
    for trailing in stride(from: zoom, through: 1200, by: 1) {
      let shown = shows(trailing: trailing)
      let needed = shown ? zoom + badgeSpacing + status : zoom
      XCTAssertGreaterThanOrEqual(trailing, needed - 0.001, "at \(trailing) pt of frame")
    }
  }
}

/// Renders the production row itself twice — once with badges to show, once with a state that has
/// none — and compares the pixels. At a narrow container the two must be the same image, which is
/// the only statement about #780 that does not depend on any model of the row: the badges are not
/// painted over the duration readout.
///
/// The roomy container is the control. There the badges do fit, so the two renders must differ; if
/// they do not, this machine's offscreen rendering cannot tell the two states apart and the narrow
/// comparison would be proving nothing, so the test says so instead of passing for free.
@MainActor
final class VideoEditorControlsRowRenderingTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUp() {
    super.setUp()
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyTests_780Rendering_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDirectory)
    tempDirectory = nil
    super.tearDown()
  }

  func testBadgesAreNotPaintedOnceTheTrailingFrameCannotHoldThem() async throws {
    let withBadges = try await VideoEditorActivityFixture.makeState(in: tempDirectory)
    _ = withBadges.addZoom(at: 1)
    withBadges.hasUnsavedChanges = true
    XCTAssertFalse(withBadges.zoomSegments.isEmpty)
    let withoutBadges = try await VideoEditorActivityFixture.makeState(in: tempDirectory)

    let roomy = render(withBadges, width: 1200)
    let roomyWithoutBadges = render(withoutBadges, width: 1200)
    try XCTSkipIf(
      roomy == roomyWithoutBadges,
      "offscreen rendering here cannot distinguish the badge group; the narrow comparison would prove nothing"
    )

    XCTAssertEqual(
      render(withBadges, width: 530),
      render(withoutBadges, width: 530),
      "at a 530 pt container the row must render exactly as if it had no badges at all"
    )
  }

  private func render(_ state: VideoEditorState, width: CGFloat) -> Data {
    let host = NSHostingView(rootView: VideoControlsView(state: state).frame(width: width, height: 60))
    host.frame = NSRect(x: 0, y: 0, width: width, height: 60)
    host.layoutSubtreeIfNeeded()
    // The badge decision lands on the pass after the measurements arrive, so let the row settle.
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
    guard let rep else { return Data() }
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.representation(using: .tiff, properties: [:]) ?? Data()
  }
}

/// Measures the row's division, the overlap it has to prevent, and the badge decision on a
/// structural twin of the controls row: `.fixedSize()` clusters in an `HStack` with 12 pt spacing,
/// the side clusters inside `.frame(maxWidth: .infinity, alignment:)` wrappers, and the status
/// group inside the `.frame(minWidth: 0)` wrapper that exempts it from the row's minimum.
///
/// The widths are the ones measured from the #780 screenshot: a ~530 pt controls container at the
/// default window size with the left sidebar and the AI panel open.
@MainActor
final class VideoControlsLayoutLawTests: XCTestCase {
  private let outerSpacing: CGFloat = 12
  private let badgeSpacing: CGFloat = 6
  private let leading: CGFloat = 76 // cut / delete / add-clip capsule
  private let transport: CGFloat = 212 // time, step back, play, step forward, duration
  private let zoom: CGFloat = 74 // minus / fit / plus capsule
  private let status: CGFloat = 129 // zoom count + trimmed duration badges
  private let container: CGFloat = 530

  func testEachSideFrameGetsHalfOfWhatTheTransportLeaves() throws {
    let share = (container - transport - 2 * outerSpacing) / 2
    let frames = laidOutFrames(showsStatus: false, statusCountedInRowMinimum: false)
    let leadingFrame = try XCTUnwrap(frames["leadingFrame"])
    let trailingFrame = try XCTUnwrap(frames["trailingFrame"])
    let transportFrame = try XCTUnwrap(frames["transport"])

    XCTAssertEqual(leadingFrame.width, share, accuracy: 0.5)
    XCTAssertEqual(trailingFrame.width, share, accuracy: 0.5)
    // The two equal frames are what centre the transport, and they abut it across the spacing.
    XCTAssertEqual(transportFrame.midX, container / 2, accuracy: 0.5)
    XCTAssertEqual(trailingFrame.minX, transportFrame.maxX + outerSpacing, accuracy: 0.5)
  }

  /// The bug, reproduced on the row's own structure. The four clusters do pack into 530 pt — which
  /// is what the old check priced the badges against, so it said they were safe — yet the exempted
  /// badge group is laid out inside the trailing side's 147 pt and reaches across the duration
  /// readout. The zoom capsule, which is part of the row's minimum, only ends up flush against the
  /// row's edge: nothing of the essentials overlaps.
  func testBadgesExemptFromTheRowMinimumOverflowTheTransport() throws {
    let frames = laidOutFrames(showsStatus: true, statusCountedInRowMinimum: false)
    let statusGroup = try XCTUnwrap(frames["status"])
    let zoomGroup = try XCTUnwrap(frames["zoom"])
    let transportFrame = try XCTUnwrap(frames["transport"])
    let trailingFrame = try XCTUnwrap(frames["trailingFrame"])

    XCTAssertLessThanOrEqual(
      leading + transport + zoom + badgeSpacing + status + 2 * outerSpacing,
      container,
      "the packing total the old check compared against really does fit"
    )
    XCTAssertEqual(trailingFrame.width, 147, accuracy: 1, "the number the decision now reads")
    XCTAssertEqual(statusGroup.width, status, accuracy: 0.5, "the badges keep their fixed width")
    XCTAssertGreaterThan(statusGroup.intersection(transportFrame).width, 0, "…and the surplus lies on the transport")
    XCTAssertLessThanOrEqual(zoomGroup.intersection(transportFrame).width, 0.5, "only the exempted group overlaps")
  }

  /// Why the fix drops the badges instead of reserving their width: count the group in the row's
  /// minimum and it stops overlapping — by taking the width from the leading side, which moves the
  /// play button off centre. It would also raise the row's minimum, and that feeds the window's
  /// content minimum — the very thing that once made ⌘K widen the window instead of narrowing the
  /// editor.
  func testCountingTheBadgesInTheRowMinimumCostsCentringInsteadOfOverlapping() throws {
    let frames = laidOutFrames(showsStatus: true, statusCountedInRowMinimum: true)
    let statusGroup = try XCTUnwrap(frames["status"])
    let transportFrame = try XCTUnwrap(frames["transport"])

    XCTAssertLessThanOrEqual(statusGroup.intersection(transportFrame).width, 0.5)
    XCTAssertLessThan(transportFrame.midX, container / 2, "the transport has given up its centring")
  }

  /// The end-to-end guarantee, in the order the row really works: it appears with the badges on,
  /// measures the frame it was given, decides from that measurement, and lays out again. The
  /// second layout must not overlap, and re-deciding from it must not change anything — otherwise
  /// the row would flicker between two configurations every pass.
  func testMeasuredDecisionConvergesAndNeverOverlaps() {
    for width in [CGFloat(340), 386, 420, 480, 530, 620, 700, 920, 1200] {
      let first = laidOutFrames(showsStatus: true, container: width)
      let shows = decide(from: first)
      let second = laidOutFrames(showsStatus: shows, container: width)

      assertNoVisibleOverlap(in: second, showsStatus: shows, at: width)
      XCTAssertEqual(
        decide(from: second),
        shows,
        "at \(width) pt the decision changed between two passes over the same configuration"
      )
    }
  }

  /// The reason for reading the frame instead of deriving it: an oversized leading cluster takes
  /// width the derived share would have promised to the trailing side, and the decision follows
  /// the frame that is actually left.
  func testOversizedLeadingSide_shrinksTheFrameAndTheDecisionFollows() throws {
    let frames = laidOutFrames(showsStatus: true, container: 700, leadingWidth: 300)
    let trailingFrame = try XCTUnwrap(frames["trailingFrame"])
    let derivedHalf = (700 - transport - 2 * outerSpacing) / 2

    XCTAssertLessThan(trailingFrame.width, derivedHalf, "the leading cluster took more than its half")
    XCTAssertEqual(
      decide(from: frames),
      VideoControlsFitPolicy.showsStatus(
        trailingWidth: trailingFrame.width,
        zoomWidth: zoom,
        statusWidth: status,
        badgeSpacing: badgeSpacing
      )
    )
    assertNoVisibleOverlap(in: laidOutFrames(showsStatus: decide(from: frames), container: 700, leadingWidth: 300),
                           showsStatus: decide(from: frames), at: 700)
  }

  /// What the view computes from a laid-out row: the widths the row measured for itself.
  private func decide(from frames: [String: CGRect]) -> Bool {
    VideoControlsFitPolicy.showsStatus(
      trailingWidth: frames["trailingFrame"]?.width ?? 0,
      zoomWidth: frames["zoom"]?.width ?? 0,
      statusWidth: frames["status"]?.width ?? 0,
      badgeSpacing: badgeSpacing
    )
  }

  /// No two clusters the user can see may end up on top of each other. The measuring copy of the
  /// badges is excluded while they are hidden — it is `.hidden()` and inert in production too.
  private func assertNoVisibleOverlap(
    in frames: [String: CGRect],
    showsStatus: Bool,
    at width: CGFloat,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    var visible: [(name: String, rect: CGRect)] = []
    for name in ["leading", "transport", "zoom"] + (showsStatus ? ["status"] : []) {
      guard let rect = frames[name] else {
        XCTFail("\(name) was not measured at \(width) pt", file: file, line: line)
        return
      }
      visible.append((name, rect))
    }
    for first in 0 ..< visible.count {
      for second in (first + 1) ..< visible.count {
        let overlap = visible[first].rect.intersection(visible[second].rect)
        XCTAssertLessThanOrEqual(
          overlap.width,
          0.5,
          "at \(width) pt (badges \(showsStatus ? "shown" : "hidden")) "
            + "\(visible[first].name) lies on \(visible[second].name) by \(overlap.width) pt",
          file: file,
          line: line
        )
      }
    }
  }

  private func laidOutFrames(
    showsStatus: Bool,
    statusCountedInRowMinimum: Bool = false,
    container: CGFloat = 530,
    leadingWidth: CGFloat? = nil
  ) -> [String: CGRect] {
    var collected: [String: CGRect] = [:]
    let host = NSHostingView(
      rootView: MirroredControlsRow(
        containerWidth: container,
        leadingWidth: leadingWidth ?? leading,
        transportWidth: transport,
        zoomWidth: zoom,
        statusWidth: status,
        outerSpacing: outerSpacing,
        badgeSpacing: badgeSpacing,
        showsStatus: showsStatus,
        statusCountedInRowMinimum: statusCountedInRowMinimum,
        onFrames: { collected = $0 }
      )
    )
    host.frame = NSRect(x: 0, y: 0, width: container, height: 60)
    host.layoutSubtreeIfNeeded()
    // A preference is published on the pass after the layout that measured it, so give the tree one
    // update cycle instead of reading straight after the first layout.
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    host.layoutSubtreeIfNeeded()

    let missing = ["leading", "leadingFrame", "trailingFrame", "transport", "zoom", "status"]
      .filter { collected[$0] == nil }
    XCTAssertTrue(missing.isEmpty, "missing measured frames \(missing) — the assertions below would compare nothing")
    return collected
  }
}

private struct LawFrameKey: PreferenceKey {
  static var defaultValue: [String: CGRect] = [:]

  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue(), uniquingKeysWith: { _, next in next })
  }
}

private struct MirroredControlsRow: View {
  let containerWidth: CGFloat
  let leadingWidth: CGFloat
  let transportWidth: CGFloat
  let zoomWidth: CGFloat
  let statusWidth: CGFloat
  let outerSpacing: CGFloat
  let badgeSpacing: CGFloat
  let showsStatus: Bool
  /// `false` wraps the badges in `.frame(minWidth: 0)`, the production row's exemption that keeps
  /// them out of the window's content minimum; `true` lets them count towards it.
  let statusCountedInRowMinimum: Bool
  let onFrames: ([String: CGRect]) -> Void

  var body: some View {
    HStack(spacing: outerSpacing) {
      cluster(width: leadingWidth, name: "leading")
        .frame(maxWidth: .infinity, alignment: .leading)
        .measure("leadingFrame")

      cluster(width: transportWidth, name: "transport")

      trailingGroup
        .frame(maxWidth: .infinity, alignment: .trailing)
        .measure("trailingFrame")
    }
    .frame(width: containerWidth)
    .onPreferenceChange(LawFrameKey.self) { onFrames($0) }
  }

  private var trailingGroup: some View {
    HStack(spacing: badgeSpacing) {
      if showsStatus {
        if statusCountedInRowMinimum {
          cluster(width: statusWidth, name: "status")
        } else {
          cluster(width: statusWidth, name: "status")
            .frame(minWidth: 0, alignment: .trailing)
        }
      }
      cluster(width: zoomWidth, name: "zoom")
    }
    // Production keeps one invisible copy of the badges while they are hidden so the decision
    // still has their width to price; the mirror needs the same, or the second pass would decide
    // from nothing.
    .background(alignment: .trailing) {
      if !showsStatus {
        cluster(width: statusWidth, name: "status")
          .hidden()
          .allowsHitTesting(false)
      }
    }
  }

  private func cluster(width: CGFloat, name: String) -> some View {
    Color.clear
      .frame(width: width, height: 24)
      .fixedSize(horizontal: true, vertical: false)
      .measure(name)
  }
}

private extension View {
  /// Publishes this view's laid-out rect, in the hosting view's coordinate space, under `name`.
  func measure(_ name: String) -> some View {
    background(
      GeometryReader { proxy in
        Color.clear.preference(key: LawFrameKey.self, value: [name: proxy.frame(in: .global)])
      }
    )
  }
}
