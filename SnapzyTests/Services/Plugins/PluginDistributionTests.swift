//
//  PluginDistributionTests.swift
//  SnapzyTests
//
//  The index is a contract with clients that are already installed: it has to
//  parse on an older Snapzy, block a plugin that needs a newer one with a
//  reason the user can act on, and disable a revoked plugin on the next fetch.
//

import Foundation
import SnapzyPluginAPI
import XCTest

@testable import Snapzy

final class PluginDistributionTests: XCTestCase {
  // MARK: - Forward compatibility

  func testIndexWithUnknownFutureFieldsStillParses() throws {
    let json = """
      {
        "indexVersion": 2,
        "generatedAt": "2027-01-01T00:00:00Z",
        "plugins": [{
          "id": "com.snapzy.translate",
          "version": "1.2.0",
          "displayName": "Translate",
          "tier": "official",
          "minAppVersion": "1.33.0",
          "contractVersion": "1.0.0",
          "documentSchema": 1,
          "capabilities": [{ "id": "snapzy.network", "scope": { "hosts": ["api.openai.com"] } }],
          "bundleURL": "https://example.invalid/translate-1.2.0.zip",
          "bundleSHA256": "abc123",
          "attestation": { "kind": "sigstore", "bundle": "…" }
        }]
      }
      """

    let index = try XCTUnwrap(PluginRegistryIndex.decodeForwardCompatibly(Data(json.utf8)))

    XCTAssertEqual(index.indexVersion, 2)
    let entry = try XCTUnwrap(index.plugins.first)
    XCTAssertEqual(entry.id, "com.snapzy.translate")
    XCTAssertEqual(entry.capabilities.first?.scope?["hosts"], ["api.openai.com"])
    // Absent optionals take their documented defaults rather than failing.
    XCTAssertFalse(entry.revoked)
    XCTAssertNil(entry.signature)
  }

  func testEntryMissingOptionalMetadataFallsBackToTheSafestValues() throws {
    let json = """
      { "indexVersion": 1, "plugins": [{
        "id": "com.example.minimal", "version": "0.1.0", "displayName": "Minimal",
        "bundleURL": "https://example.invalid/x.zip", "bundleSHA256": "deadbeef"
      }] }
      """

    let index = try XCTUnwrap(PluginRegistryIndex.decodeForwardCompatibly(Data(json.utf8)))
    let entry = try XCTUnwrap(index.plugins.first)

    // An entry that forgot to say what it is gets the least-trusted tier, not
    // the most.
    XCTAssertEqual(entry.tier, "community")
    XCTAssertEqual(entry.contractVersion, "1.0.0")
    XCTAssertEqual(entry.documentSchema, 1)
    XCTAssertTrue(entry.capabilities.isEmpty)
  }

  func testNativeIndexFieldsDecodeAndForwardCompat() throws {
    let json = """
      {
        "indexVersion": 1,
        "plugins": [{
          "id": "com.snapzy.native-translate",
          "version": "2.0.0",
          "displayName": "Native Translate",
          "tier": "official",
          "minAppVersion": "1.33.0",
          "contractVersion": "1.0.0",
          "documentSchema": 1,
          "capabilities": [],
          "bundleURL": "https://example.invalid/native-translate-2.0.0.zip",
          "bundleSHA256": "abcdef123456",
          "runtime": "process",
          "protocolVersion": "1.0.0",
          "architectures": ["arm64", "x86_64"],
          "teamIdentifier": "XMHV5GH2Z7"
        }]
      }
      """

    let index = try XCTUnwrap(PluginRegistryIndex.decodeForwardCompatibly(Data(json.utf8)))
    let entry = try XCTUnwrap(index.plugins.first)

    XCTAssertEqual(entry.runtime, "process")
    XCTAssertEqual(entry.protocolVersion, "1.0.0")
    XCTAssertEqual(entry.architectures, ["arm64", "x86_64"])
    XCTAssertEqual(entry.teamIdentifier, "XMHV5GH2Z7")
  }

  // MARK: - Compatibility gates

  func testAPluginNeedingANewerSnapzyIsBlockedWithAReason() {
    let entry = makeEntry(minAppVersion: "2.0.0")
    let issues = PluginPackageVerifier.compatibilityIssues(entry: entry, appVersion: "1.33.0")
    XCTAssertEqual(issues.count, 1)
    XCTAssertTrue(issues[0].contains("2.0.0"), "The reason must name the version needed: \(issues)")
  }

  func testAPluginNeedingANewerContractOrSchemaIsBlocked() {
    let newerContract = makeEntry(contractVersion: "2.0.0")
    XCTAssertFalse(
      PluginPackageVerifier.compatibilityIssues(entry: newerContract, appVersion: "1.33.0").isEmpty
    )

    let newerSchema = makeEntry(documentSchema: SnapzyVocabulary.documentSchemaVersion + 1)
    XCTAssertFalse(
      PluginPackageVerifier.compatibilityIssues(entry: newerSchema, appVersion: "1.33.0").isEmpty
    )
  }

  func testACompatiblePluginHasNoIssues() {
    let entry = makeEntry(minAppVersion: "1.0.0")
    XCTAssertTrue(
      PluginPackageVerifier.compatibilityIssues(entry: entry, appVersion: "1.33.0").isEmpty
    )
  }

  func testIncompatibleArchitectureIsBlockedWithReason() {
    let entry = makeEntry(architectures: ["nonexistent_arch"])
    let issues = PluginPackageVerifier.compatibilityIssues(entry: entry, appVersion: "1.33.0")
    XCTAssertFalse(issues.isEmpty)
    XCTAssertTrue(issues[0].contains("Requires architecture"))
  }

  func testUnsupportedRuntimeIsBlockedWithReason() {
    let entry = makeEntry(runtime: "unsupported_runtime")
    let issues = PluginPackageVerifier.compatibilityIssues(entry: entry, appVersion: "1.33.0")
    XCTAssertFalse(issues.isEmpty)
    XCTAssertTrue(issues[0].contains("Unsupported plugin runtime"))
  }

  func testVersionComparisonIsNumericNotLexicographic() {
    // "1.9.0" > "1.10.0" as strings; the gate must not agree.
    let entry = makeEntry(minAppVersion: "1.9.0")
    XCTAssertTrue(
      PluginPackageVerifier.compatibilityIssues(entry: entry, appVersion: "1.10.0").isEmpty
    )
  }

  // MARK: - Update badges

  func testUpdatesAreOfferedOnlyForNewerNonRevokedInstalledPlugins() {
    let index = PluginRegistryIndex(
      indexVersion: 1,
      plugins: [
        makeEntry(id: "com.snapzy.translate", version: "1.2.0"),
        makeEntry(id: "com.snapzy.webhook-upload", version: "1.0.0"),
        makeEntry(id: "com.example.revoked", version: "9.9.9", revoked: true),
        makeEntry(id: "com.example.notinstalled", version: "5.0.0"),
      ]
    )
    let installed = [
      snapshot(id: "com.snapzy.translate", version: "1.0.0"),
      snapshot(id: "com.snapzy.webhook-upload", version: "1.0.0"),
      snapshot(id: "com.example.revoked", version: "1.0.0"),
    ]

    let updates = PluginUpdateChecker.updatesAvailable(index: index, installed: installed)

    XCTAssertEqual(updates.map(\.id), ["com.snapzy.translate"])
  }

  func testNoIndexMeansNoUpdateBadges() {
    XCTAssertTrue(
      PluginUpdateChecker.updatesAvailable(
        index: nil, installed: [snapshot(id: "com.snapzy.translate", version: "1.0.0")]
      ).isEmpty
    )
  }

  // MARK: - Fixtures

  private func makeEntry(
    id: String = "com.snapzy.translate",
    version: String = "1.0.0",
    minAppVersion: String = "1.0.0",
    contractVersion: String = "1.0.0",
    documentSchema: Int = 1,
    revoked: Bool = false,
    runtime: String = "script",
    architectures: [String]? = nil
  ) -> PluginIndexEntry {
    PluginIndexEntry(
      id: id,
      version: version,
      displayName: "Translate",
      tier: "official",
      minAppVersion: minAppVersion,
      contractVersion: contractVersion,
      documentSchema: documentSchema,
      capabilities: [],
      bundleURL: "https://example.invalid/\(id)-\(version).zip",
      bundleSHA256: "deadbeef",
      revoked: revoked,
      runtime: runtime,
      architectures: architectures
    )
  }

  private func snapshot(id: String, version: String) -> PluginSnapshot {
    PluginSnapshot(
      id: id,
      version: version,
      displayName: id,
      summary: nil,
      phase: "resolved",
      tier: .official,
      trust: "official",
      problem: "",
      warnings: [],
      declaredCapabilities: [],
      contributions: [],
      failureCount: 0,
      userEnabled: nil,
      locationPath: nil
    )
  }
}
