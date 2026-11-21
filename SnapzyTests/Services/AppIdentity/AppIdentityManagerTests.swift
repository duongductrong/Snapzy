//
//  AppIdentityManagerTests.swift
//  SnapzyTests
//
//  Covers the bundle-identity cache that keeps strict signature validation off
//  the capture hot path (issue #509).
//

import Combine
import Foundation
import XCTest
@testable import Snapzy

@MainActor
final class AppIdentityManagerTests: XCTestCase {
  // MARK: - needsRevalidation

  func testNeedsRevalidation_requiresWorkWhenEitherSignatureIsUnknown() {
    let signature = AppBundleSignature(path: "/Applications/Snapzy.app", modificationTime: 1, size: 2)

    XCTAssertTrue(AppIdentityManager.needsRevalidation(previous: nil, current: nil))
    XCTAssertTrue(AppIdentityManager.needsRevalidation(previous: signature, current: nil))
    XCTAssertTrue(AppIdentityManager.needsRevalidation(previous: nil, current: signature))
  }

  func testNeedsRevalidation_skipsWorkWhileBundleIsUnchanged() {
    let signature = AppBundleSignature(path: "/Applications/Snapzy.app", modificationTime: 1_000, size: 60_000)
    let sameButEqual = AppBundleSignature(path: "/Applications/Snapzy.app", modificationTime: 1_000, size: 60_000)
    let rewritten = AppBundleSignature(path: "/Applications/Snapzy.app", modificationTime: 1_001, size: 60_000)
    let resized = AppBundleSignature(path: "/Applications/Snapzy.app", modificationTime: 1_000, size: 61_000)
    let replacedBundle = AppBundleSignature(path: "/Users/me/Snapzy.app", modificationTime: 1_000, size: 60_000)

    XCTAssertFalse(AppIdentityManager.needsRevalidation(previous: signature, current: sameButEqual))
    XCTAssertTrue(AppIdentityManager.needsRevalidation(previous: signature, current: rewritten))
    XCTAssertTrue(AppIdentityManager.needsRevalidation(previous: signature, current: resized))
    XCTAssertTrue(AppIdentityManager.needsRevalidation(previous: signature, current: replacedBundle))
  }

  // MARK: - signature

  func testSignature_isNilForPathsThatAreNotBundles() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppIdentityManagerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }

    let missingBundle = root.appendingPathComponent("DoesNotExist.app")

    XCTAssertNil(AppIdentityManager.signature(for: root), "a plain directory is not a bundle")
    XCTAssertNil(AppIdentityManager.signature(for: missingBundle))
  }

  func testSignature_tracksExecutableRewrites() throws {
    var bundle = try makeBundle(named: "Snapzy.app", executableContents: Data("one".utf8))
    let original = try XCTUnwrap(AppIdentityManager.signature(for: bundle))
    XCTAssertEqual(original.path, bundle.appendingPathComponent("Contents/MacOS/Snapzy").path)

    XCTAssertEqual(AppIdentityManager.signature(for: bundle), original)

    // Same size, different content: the modification date has to catch this.
    try Data("two".utf8).write(to: bundle.appendingPathComponent("Contents/MacOS/Snapzy"))
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(60)],
      ofItemAtPath: bundle.appendingPathComponent("Contents/MacOS/Snapzy").path
    )
    let rewritten = try XCTUnwrap(AppIdentityManager.signature(for: bundle))
    XCTAssertNotEqual(rewritten, original)

    bundle = try makeBundle(named: "Other.app", executableContents: Data("a much longer executable".utf8))
    XCTAssertNotEqual(AppIdentityManager.signature(for: bundle)?.size, original.size)
  }

  // MARK: - refresh caching

  func testRefreshWithoutForceKeepsTheCachedHealth() {
    let manager = AppIdentityManager.shared
    var evaluations = 0

    let cancellable = manager.$health
      .dropFirst()
      .sink { _ in evaluations += 1 }
    defer { cancellable.cancel() }

    manager.refresh(force: true)
    let forcedEvaluations = evaluations
    XCTAssertEqual(forcedEvaluations, 1, "a forced refresh must publish fresh health")

    manager.refresh()
    XCTAssertEqual(evaluations, forcedEvaluations, "an unchanged bundle must not be re-validated")

    manager.refresh(force: true)
    XCTAssertEqual(evaluations, forcedEvaluations + 1, "forcing again must re-validate")
  }

  func testHealthMatchesTheRunningBundle() {
    XCTAssertEqual(
      AppIdentityManager.shared.health.bundleURL,
      Bundle.main.bundleURL.standardizedFileURL
    )
  }

  // MARK: - Helpers

  private func makeBundle(named name: String, executableContents: Data) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppIdentityManagerTests-\(UUID().uuidString)", isDirectory: true)
    let bundle = root.appendingPathComponent(name, isDirectory: true)
    let execDir = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: execDir, withIntermediateDirectories: true)

    let infoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleExecutable</key>
      <string>Snapzy</string>
      <key>CFBundleIdentifier</key>
      <string>com.trongduong.snapzy.tests</string>
      <key>CFBundlePackageType</key>
      <string>APPL</string>
    </dict>
    </plist>
    """
    try infoPlist.write(
      to: bundle.appendingPathComponent("Contents/Info.plist"),
      atomically: true,
      encoding: .utf8
    )

    let executable = bundle.appendingPathComponent("Contents/MacOS/Snapzy")
    try executableContents.write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return bundle
  }
}
