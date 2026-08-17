//
//  OfficialPluginManifestTests.swift
//  SnapzyTests
//
//  The official plugin manifests as committed fixtures. Drift breaks a build
//  rather than a user: a vocabulary change that invalidates a shipped manifest
//  fails here, before someone finds it in Browse.
//

import Foundation
import PluginKitCore
import SnapzyPluginAPI
import XCTest

@testable import Snapzy

final class OfficialPluginManifestTests: XCTestCase {
  /// The repository root, found from this file rather than from a bundle:
  /// these manifests are source, not test resources, and are the same bytes
  /// that get published.
  private static var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Plugins
      .deletingLastPathComponent()  // Services
      .deletingLastPathComponent()  // SnapzyTests
      .deletingLastPathComponent()  // repository root
  }

  private static let officialIDs = ["com.snapzy.translate", "com.snapzy.webhook-upload"]

  private func manifest(forOfficial id: String) throws -> PluginManifest {
    let url = Self.repositoryRoot
      .appendingPathComponent("plugins/official/\(id)/plugin.json")
    return try PluginManifest.load(from: url)
  }

  // MARK: - Structure

  func testOfficialManifestsDecodeAndValidate() throws {
    for id in Self.officialIDs {
      let manifest = try manifest(forOfficial: id)
      XCTAssertNoThrow(try manifest.validateStructure(), "\(id) is structurally invalid.")
      XCTAssertEqual(manifest.id.rawValue, id, "The manifest id must match its folder.")
      XCTAssertFalse(manifest.displayName.isEmpty)
      XCTAssertNotNil(manifest.summary, "\(id) needs a summary: Browse shows it before install.")
    }
  }

  func testOfficialManifestsRunAsSandboxedProcess() throws {
    for id in Self.officialIDs {
      let manifest = try manifest(forOfficial: id)
      switch manifest.runtime {
      case .custom(let id, let options):
        XCTAssertEqual(id, RuntimeID.process)
        XCTAssertNotNil(options["executable"])
      case .script(let engine, _):
        XCTAssertEqual(engine, "javascriptcore")
      default:
        XCTFail("\(id) must request sandboxed process runtime.")
      }
    }
  }

  func testOfficialManifestsTargetTheCommandPointAtThisContractVersion() throws {
    for id in Self.officialIDs {
      let manifest = try manifest(forOfficial: id)
      XCTAssertFalse(manifest.contributions.isEmpty, "\(id) contributes nothing.")

      for contribution in manifest.contributions {
        XCTAssertEqual(contribution.extensionPoint, SnapzyCommandPoint.extensionPointID)
        XCTAssertEqual(
          contribution.contractVersion, SnapzyVocabulary.contractVersion,
          "\(id) was built against a contract this host no longer publishes."
        )
        // The metadata is what renders the menu before any code loads, so it
        // must decode into the point's own type.
        let metadata = try contribution.metadata.decode(
          as: SnapzyCommandPoint.Metadata.self
        )
        XCTAssertFalse(metadata.title.isEmpty)
        XCTAssertFalse(metadata.systemImage.isEmpty)
        XCTAssertFalse(metadata.accepts.isEmpty, "An empty `accepts` shows the command everywhere.")
      }

      let contract = manifest.contracts.first { $0.vocabulary == SnapzyVocabulary.vocabularyID }
      XCTAssertNotNil(contract, "\(id) does not declare the Snapzy vocabulary.")
    }
  }

  // MARK: - Capability disclosure

  func testEveryDeclaredCapabilityCarriesAUserFacingReason() throws {
    for id in Self.officialIDs {
      let manifest = try manifest(forOfficial: id)
      XCTAssertFalse(manifest.capabilities.isEmpty)
      for request in manifest.capabilities {
        // The reason is the entire text the consent prompt shows. An empty one
        // is not a formatting nit.
        XCTAssertFalse(
          request.reason.isEmpty,
          "\(id) requests \(request.id.rawValue) without telling the user why."
        )
        XCTAssertGreaterThan(request.reason.count, 20, "\(id): \(request.id.rawValue) needs a real sentence.")
      }
    }
  }

  func testNoOfficialPluginRequestsAWildcardNetworkScope() throws {
    for id in Self.officialIDs {
      let manifest = try manifest(forOfficial: id)
      guard let network = manifest.capabilityRequest(for: SnapzyNetworkAccess.capabilityID) else {
        continue
      }
      let hosts = network.scope["hosts"]?.arrayValue?.compactMap(\.stringValue) ?? []
      XCTAssertFalse(hosts.isEmpty, "\(id) asks for the network without naming a destination.")
      XCTAssertFalse(
        hosts.contains("*"),
        "\(id) asks for every host, which would make the pre-install disclosure meaningless."
      )
    }
  }

  func testDeclaredEditOpsAreCoveredByTheDocumentWriteScope() throws {
    for id in Self.officialIDs {
      let manifest = try manifest(forOfficial: id)
      let scopedOps = Set(
        manifest.capabilityRequest(for: SnapzyDocumentWrite.capabilityID)?
          .scope["ops"]?.arrayValue?.compactMap(\.stringValue) ?? []
      )
      for contribution in manifest.contributions {
        let metadata = try contribution.metadata.decode(as: SnapzyCommandPoint.Metadata.self)
        for op in metadata.emits {
          XCTAssertTrue(
            scopedOps.contains(op.rawValue),
            "\(id) says it emits \(op.rawValue) but did not scope document.write to it."
          )
        }
      }
    }
  }

  func testTranslateDeclaresExactlyTheCapabilitiesItsDocumentationClaims() throws {
    let manifest = try manifest(forOfficial: "com.snapzy.translate")
    let declared = Set(manifest.capabilities.map(\.id.rawValue))
    XCTAssertEqual(
      declared,
      [
        "snapzy.asset.read", "snapzy.ocr", "snapzy.network",
        "snapzy.document.write", "snapzy.secrets", "snapzy.ui",
      ],
      "Translate's capability set is documented in docs/PLUGINS.md and its README; update both."
    )
    // The filesystem, screen capture, clipboard read, and history are not
    // capabilities at all — assert the shape of the claim, not just the list.
    XCTAssertFalse(declared.contains { $0.contains("fs") || $0.contains("screen") })
  }
}
