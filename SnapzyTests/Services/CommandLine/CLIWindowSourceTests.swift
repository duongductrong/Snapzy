//
//  CLIWindowSourceTests.swift
//  SnapzyTests
//
//  Pure mapping behind `snapzy list`: coordinate flips, active window, app
//  grouping and app-name matching.
//

@testable import Snapzy
import SnapzyCLIProtocol
import XCTest

final class CLIWindowSourceTests: XCTestCase {
  /// Main display 1512×982 points; a second display sits to its left.
  private let mainHeight: CGFloat = 982

  private func candidate(
    _ id: CGWindowID,
    _ owner: String,
    bundleID: String?,
    pid: Int32,
    frame: CGRect,
    title: String? = nil
  ) -> CLIWindowSource.Candidate {
    CLIWindowSource.Candidate(
      windowID: id,
      title: title,
      ownerName: owner,
      bundleID: bundleID,
      ownerPID: pid,
      frame: frame,
      displayID: 1
    )
  }

  // MARK: - Coordinates

  func testTopLeftFlip() {
    // AppKit window at the top-left of the main display.
    let appKit = CGRect(x: 0, y: 182, width: 1200, height: 800)

    XCTAssertEqual(
      CLICoordinateSpace.topLeftRect(fromAppKit: appKit, mainDisplayHeight: mainHeight),
      CLIRect(x: 0, y: 0, width: 1200, height: 800)
    )
  }

  func testFlipOnDisplayLeftOfAndAboveMain() {
    let leftDisplayWindow = CGRect(x: -1440, y: 100, width: 400, height: 300)
    let aboveWindow = CGRect(x: 100, y: 1200, width: 400, height: 300)

    XCTAssertEqual(
      CLICoordinateSpace.topLeftRect(fromAppKit: leftDisplayWindow, mainDisplayHeight: mainHeight),
      CLIRect(x: -1440, y: 582, width: 400, height: 300)
    )
    XCTAssertEqual(
      CLICoordinateSpace.topLeftRect(fromAppKit: aboveWindow, mainDisplayHeight: mainHeight),
      CLIRect(x: 100, y: -518, width: 400, height: 300)
    )
  }

  func testFlipRoundTrips() {
    let rect = CLIRect(x: -1440, y: -518, width: 400.5, height: 300)

    let appKit = CLICoordinateSpace.appKitRect(fromTopLeft: rect, mainDisplayHeight: mainHeight)
    XCTAssertEqual(CLICoordinateSpace.topLeftRect(fromAppKit: appKit, mainDisplayHeight: mainHeight), rect)
  }

  // MARK: - Windows and apps

  func testFrontmostAppsFirstWindowIsActive() {
    let windows = CLIWindowSource.windows(
      from: [
        candidate(
          10,
          "Safari",
          bundleID: "com.apple.Safari",
          pid: 1,
          frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        ),
        candidate(
          11,
          "Code",
          bundleID: "com.microsoft.VSCode",
          pid: 2,
          frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        ),
        candidate(
          12,
          "Code",
          bundleID: "com.microsoft.VSCode",
          pid: 2,
          frame: CGRect(x: 0, y: 0, width: 100, height: 100)
        ),
      ],
      frontmostPID: 2,
      mainDisplayHeight: mainHeight
    )

    XCTAssertEqual(windows.map(\.isActive), [false, true, false])
    XCTAssertEqual(windows.map(\.id), [10, 11, 12])
    XCTAssertTrue(windows.allSatisfy(\.isOnScreen))
  }

  func testAppsGroupInFrontToBackOrder() {
    let windows = CLIWindowSource.windows(
      from: [
        candidate(11, "Code", bundleID: "com.microsoft.VSCode", pid: 2, frame: .zero),
        candidate(10, "Safari", bundleID: "com.apple.Safari", pid: 1, frame: .zero),
        candidate(12, "Code", bundleID: "com.microsoft.VSCode", pid: 2, frame: .zero),
      ],
      frontmostPID: 1,
      mainDisplayHeight: mainHeight
    )

    XCTAssertEqual(
      CLIWindowSource.apps(from: windows),
      [
        CLIApp(name: "Code", bundleID: "com.microsoft.VSCode", pid: 2, windowCount: 2, isActive: false),
        CLIApp(name: "Safari", bundleID: "com.apple.Safari", pid: 1, windowCount: 1, isActive: true),
      ]
    )
  }

  func testUnknownPIDWindowsDoNotMergeAcrossApps() {
    let windows = CLIWindowSource.windows(
      from: [
        CLIWindowSource.Candidate(
          windowID: 1,
          title: nil,
          ownerName: "A",
          bundleID: "com.a",
          ownerPID: nil,
          frame: .zero,
          displayID: 1
        ),
        CLIWindowSource.Candidate(
          windowID: 2,
          title: nil,
          ownerName: "B",
          bundleID: "com.b",
          ownerPID: nil,
          frame: .zero,
          displayID: 1
        ),
        CLIWindowSource.Candidate(
          windowID: 3,
          title: nil,
          ownerName: "A",
          bundleID: "com.a",
          ownerPID: nil,
          frame: .zero,
          displayID: 1
        ),
      ],
      frontmostPID: nil,
      mainDisplayHeight: mainHeight
    )

    XCTAssertEqual(CLIWindowSource.apps(from: windows).map(\.name), ["A", "B"])
    XCTAssertEqual(CLIWindowSource.apps(from: windows).map(\.windowCount), [2, 1])
  }

  // MARK: - App name matching

  private struct App: Equatable {
    let name: String
    let bundleID: String?
  }

  private let apps = [
    App(name: "Code", bundleID: "com.microsoft.VSCode"),
    App(name: "Codex", bundleID: "com.openai.codex"),
    App(name: "Safari", bundleID: "com.apple.Safari"),
    App(name: "Safari Technology Preview", bundleID: "com.apple.SafariTechnologyPreview"),
  ]

  private func match(_ query: String) -> [String] {
    AppNameMatcher.filter(apps, query: query, name: \.name, bundleID: \.bundleID).map(\.name)
  }

  func testBundleIDWinsOverNames() {
    XCTAssertEqual(match("com.apple.safari"), ["Safari"])
  }

  func testExactNameBeatsPrefix() {
    XCTAssertEqual(match("code"), ["Code"])
    XCTAssertEqual(match("Safari"), ["Safari"])
  }

  func testPrefixWhenNothingExact() {
    XCTAssertEqual(match("saf"), ["Safari", "Safari Technology Preview"])
    XCTAssertEqual(match("Codex"), ["Codex"])
  }

  func testNoMatchOrBlankQuery() {
    XCTAssertEqual(match("Xcode"), [])
    XCTAssertEqual(match("  "), [])
  }

  // MARK: - Status

  func testPermissionMapping() {
    XCTAssertEqual(CLIStatusHandler.permission(for: .granted, requiresRelaunch: false), .granted)
    XCTAssertEqual(CLIStatusHandler.permission(for: .granted, requiresRelaunch: true), .unavailable)
    XCTAssertEqual(CLIStatusHandler.permission(for: .notGranted, requiresRelaunch: false), .denied)
    XCTAssertEqual(
      CLIStatusHandler.permission(for: .grantedButUnavailableDueToAppIdentity("moved"), requiresRelaunch: false),
      .unavailable
    )
  }
}
