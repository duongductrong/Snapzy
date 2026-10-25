//
//  CLIToolInstallerTests.swift
//  SnapzyTests
//
//  Link-state detection and shell quoting for installing the snapzy command.
//  Never touches /usr/local/bin.
//

@testable import Snapzy
import XCTest

final class CLIToolInstallerTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("CLIToolInstallerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private var link: String {
    directory.appendingPathComponent("snapzy").path
  }

  private func makeHelper(in app: String) throws -> String {
    let helper = directory.appendingPathComponent("\(app)/Contents/Helpers/snapzy")
    try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: helper.path, contents: Data())
    return helper.path
  }

  func testStates() throws {
    let helper = try makeHelper(in: "Snapzy Debug.app")
    let other = try makeHelper(in: "Other.app")

    XCTAssertEqual(CLIToolInstaller.state(linkPath: link, helperPath: helper), .notInstalled)

    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: helper)
    XCTAssertEqual(CLIToolInstaller.state(linkPath: link, helperPath: helper), .installed)
    XCTAssertEqual(CLIToolInstaller.state(linkPath: link, helperPath: other), .pointsElsewhere(helper))

    try FileManager.default.removeItem(atPath: link)
    try Data("#!/bin/sh".utf8).write(to: URL(fileURLWithPath: link))
    XCTAssertEqual(CLIToolInstaller.state(linkPath: link, helperPath: helper), .blockedByFile)
  }

  func testCaskInstallLeavesTheLinkToHomebrew() throws {
    let helper = try makeHelper(in: "Snapzy.app")
    let brewLink = directory.appendingPathComponent("brew-snapzy").path

    XCTAssertEqual(
      CLIToolInstaller.state(helperPath: helper, caskInstalled: true, linkPath: link, homebrewLinkPaths: [brewLink]),
      .homebrewLinkMissing
    )
    XCTAssertEqual(
      CLIToolInstaller.state(helperPath: helper, caskInstalled: false, linkPath: link, homebrewLinkPaths: [brewLink]),
      .notInstalled
    )

    try FileManager.default.createSymbolicLink(atPath: brewLink, withDestinationPath: helper)
    XCTAssertEqual(
      CLIToolInstaller.state(helperPath: helper, caskInstalled: true, linkPath: link, homebrewLinkPaths: [brewLink]),
      .managedByHomebrew(brewLink)
    )
    XCTAssertEqual(
      CLIToolInstaller.state(helperPath: helper, caskInstalled: false, linkPath: link, homebrewLinkPaths: [brewLink]),
      .notInstalled,
      "a link at Homebrew's path is not Homebrew's without the cask"
    )
  }

  func testCaskInstallKeepsAWorkingLink() throws {
    let helper = try makeHelper(in: "Snapzy.app")
    let brewLink = directory.appendingPathComponent("brew-snapzy").path
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: helper)

    XCTAssertEqual(
      CLIToolInstaller.state(helperPath: helper, caskInstalled: true, linkPath: link, homebrewLinkPaths: [brewLink]),
      .installed
    )
  }

  func testCaskInstallDetection() throws {
    let caskroom = directory.appendingPathComponent("Caskroom/snapzy")
    let app = URL(fileURLWithPath: "/Applications/Snapzy.app")

    XCTAssertFalse(CLIToolInstaller.isCaskInstalled(appBundleURL: app, caskroomPaths: [caskroom.path]))

    try FileManager.default.createDirectory(at: caskroom, withIntermediateDirectories: true)
    XCTAssertTrue(CLIToolInstaller.isCaskInstalled(appBundleURL: app, caskroomPaths: [caskroom.path]))
    XCTAssertFalse(CLIToolInstaller.isCaskInstalled(
      appBundleURL: URL(fileURLWithPath: "/tmp/Snapzy Debug.app"),
      caskroomPaths: [caskroom.path]
    ))
  }

  func testDanglingLinkIsPointsElsewhere() throws {
    let helper = try makeHelper(in: "Snapzy.app")
    try FileManager.default.createSymbolicLink(
      atPath: link,
      withDestinationPath: "/Applications/Gone.app/Contents/Helpers/snapzy"
    )

    XCTAssertEqual(
      CLIToolInstaller.state(linkPath: link, helperPath: helper),
      .pointsElsewhere("/Applications/Gone.app/Contents/Helpers/snapzy")
    )
  }

  func testRelativeLinkResolvesAgainstLinkDirectory() throws {
    let helper = try makeHelper(in: "Snapzy.app")
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "Snapzy.app/Contents/Helpers/snapzy")

    XCTAssertEqual(CLIToolInstaller.state(linkPath: link, helperPath: helper), .installed)
  }

  func testReplaceableLinks() throws {
    let otherTool = try makeHelper(in: "Other.app")
    let release = try makeHelper(in: "Snapzy.app")
    let debug = try makeHelper(in: "Snapzy Debug.app")

    XCTAssertTrue(CLIToolInstaller.isReplaceable(release, isDebugBuild: false))
    XCTAssertTrue(
      CLIToolInstaller.isReplaceable(debug, isDebugBuild: false),
      "release reclaims a snapzy link an older Debug build made"
    )
    XCTAssertTrue(CLIToolInstaller.isReplaceable(debug, isDebugBuild: true))
    XCTAssertFalse(CLIToolInstaller.isReplaceable(release, isDebugBuild: true), "Debug never takes a release link")

    for isDebugBuild in [false, true] {
      XCTAssertTrue(
        CLIToolInstaller.isReplaceable("/Applications/Gone.app/bin/snapzy", isDebugBuild: isDebugBuild),
        "dangling links are replaceable"
      )
      XCTAssertFalse(
        CLIToolInstaller.isReplaceable(otherTool, isDebugBuild: isDebugBuild),
        "another tool's existing binary"
      )
    }
  }

  func testDebugBuildLinksItsOwnName() {
    // Tests run inside the Debug app.
    XCTAssertTrue(CLIToolInstaller.isDebugBuild)
    XCTAssertEqual(CLIToolInstaller.linkPath, "/usr/local/bin/snapzy-debug")
  }

  func testTemporaryLocations() {
    XCTAssertTrue(CLIToolInstaller.isTemporaryLocation(URL(fileURLWithPath: "/Volumes/Snapzy/Snapzy.app")))
    XCTAssertTrue(CLIToolInstaller.isTemporaryLocation(
      URL(fileURLWithPath: "/private/var/folders/xy/T/AppTranslocation/ABC/d/Snapzy.app")
    ))
    XCTAssertFalse(CLIToolInstaller.isTemporaryLocation(URL(fileURLWithPath: "/Applications/Snapzy.app")))
  }

  func testAppleScriptQuoting() {
    XCTAssertEqual(
      CLIToolInstaller.appleScriptQuoted(#"ln -sfn '/a "b"\c' x"#),
      #""ln -sfn '/a \"b\"\\c' x""#
    )
  }

  func testShellQuoting() {
    XCTAssertEqual(CLIToolInstaller.shellQuoted("/Applications/Snapzy Debug.app"), "'/Applications/Snapzy Debug.app'")
    XCTAssertEqual(CLIToolInstaller.shellQuoted("it's"), "'it'\\''s'")
  }

  func testHelperURLIsInsideAppBundle() {
    XCTAssertEqual(
      CLIToolInstaller.helperURL(appBundleURL: URL(fileURLWithPath: "/Applications/Snapzy.app")).path,
      "/Applications/Snapzy.app/Contents/Helpers/snapzy"
    )
  }
}
