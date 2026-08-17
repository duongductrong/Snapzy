import Foundation
import PluginKitCore
import PluginKitHost
import SnapzyPluginAPI
import SnapzyPluginMessages
import SnapzyPluginProtocol
import XCTest

@testable import Snapzy

final class ProcessPluginRuntimeTests: XCTestCase {
  func testRuntimeSelectorPicksProcessRuntime() {
    let selector = SnapzyRuntimeSelector()
    let manifest = PluginManifest(
      id: PluginID("com.test.native"),
      version: SemanticVersion(1, 0, 0),
      displayName: "Native Test",
      sdkVersion: VersionRange(stringLiteral: ">=1.0.0 <2.0.0"),
      contracts: [],
      runtime: .custom(RuntimeID.process, options: ["executable": .string("NativeBinary")]),
      activation: .onDemand,
      capabilities: [],
      contributions: []
    )

    let runtimeID = selector.selectRuntime(
      for: manifest,
      trust: .sandboxedOnly,
      requiresInProcess: false,
      available: [.inProcess, .script, .process]
    )

    XCTAssertEqual(runtimeID, .process)
  }

  func testCanHostChecksExecutable() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let execURL = tempDir.appendingPathComponent("MyPlugin")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: execURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)

    let broker = PluginServiceBroker(
      environment: PluginServiceBroker.Environment(
        pluginProvider: { _ in nil },
        decisionProvider: { _, _, _ in .denied(.unavailable(CapabilityID("test"))) },
        storageProvider: { _ in try InMemoryPluginStorage() },
        secrets: PluginSecretsStore(),
        invocations: PluginInvocationRegistry.shared
      )
    )
    let supervisor = PluginProcessSupervisor(broker: broker, progressHandler: { _ in })
    let runtime = SnapzyProcessRuntime(supervisor: supervisor)

    let manifest = PluginManifest(
      id: PluginID("com.test.native"),
      version: SemanticVersion(1, 0, 0),
      displayName: "Native Test",
      sdkVersion: VersionRange(stringLiteral: ">=1.0.0 <2.0.0"),
      contracts: [],
      runtime: .custom(RuntimeID.process, options: ["executable": .string("MyPlugin")]),
      activation: .onDemand,
      capabilities: [],
      contributions: []
    )

    let canHost = runtime.canHost(manifest, at: .bundle(tempDir))
    XCTAssertTrue(canHost)

    let nonExistentManifest = PluginManifest(
      id: PluginID("com.test.native"),
      version: SemanticVersion(1, 0, 0),
      displayName: "Native Test",
      sdkVersion: VersionRange(stringLiteral: ">=1.0.0 <2.0.0"),
      contracts: [],
      runtime: .custom(RuntimeID.process, options: ["executable": .string("DoesNotExist")]),
      activation: .onDemand,
      capabilities: [],
      contributions: []
    )
    XCTAssertFalse(runtime.canHost(nonExistentManifest, at: .bundle(tempDir)))
  }

  func testSignatureVerifierRejectsUnsignedOfficialPlugin() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let execURL = tempDir.appendingPathComponent("UnsignedBinary")
    try Data("mock".utf8).write(to: execURL)

    XCTAssertThrowsError(
      try PluginSignatureVerifier.verify(executableURL: execURL, tier: .official, trustLevel: .sandboxedOnly)
    )
  }
}
