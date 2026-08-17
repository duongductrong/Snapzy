//
//  PluginDevelopmentLoadTests.swift
//  SnapzyTests
//
//  "Load Plugin from Folder…" and development staging tests:
//  discovery has to find the staged copy, and the process runtime has to
//  agree it can host it.
//

import Foundation
import PluginKitHost
import SnapzyPluginAPI
import XCTest

@testable import Snapzy

final class PluginDevelopmentLoadTests: XCTestCase {
  private var temporaryRoot: URL!

  override func setUpWithError() throws {
    temporaryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("PluginDevelopmentLoadTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let temporaryRoot {
      try? FileManager.default.removeItem(at: temporaryRoot)
    }
  }

  // MARK: - Discovery

  func testDevelopmentDirectoryIsScannedForStagedBundles() async throws {
    let staging = temporaryRoot.appendingPathComponent("Development", isDirectory: true)
    try makePluginBundle(
      at: staging.appendingPathComponent("com.example.dev.plugin", isDirectory: true),
      id: "com.example.dev"
    )

    let source = DirectoryPluginSource(
      sourceID: .development,
      trustHint: .development,
      directory: staging
    )
    let discovered = try await source.discover()

    XCTAssertEqual(discovered.map { $0.id.rawValue }, ["com.example.dev"])
    // The trust hint is what drives the development banner and per-session
    // consent, so it has to survive discovery.
    XCTAssertEqual(discovered.first?.trustHint, .development)
  }

  func testABundleNestedOneLevelDeeperIsNotDiscovered() async throws {
    let plugins = temporaryRoot.appendingPathComponent("Plugins", isDirectory: true)
    let nested = plugins.appendingPathComponent("__development", isDirectory: true)
    try makePluginBundle(
      at: nested.appendingPathComponent("com.example.dev.plugin", isDirectory: true),
      id: "com.example.dev"
    )

    let source = DirectoryPluginSource(
      sourceID: .user, trustHint: .userInstalled, directory: plugins
    )
    let discovered = try await source.discover()
    XCTAssertTrue(
      discovered.isEmpty,
      "DirectoryPluginSource scans one level; staging must be its own source."
    )
  }

  func testStagingDirectoryMatchesTheDiscoveredDirectory() async {
    let staging = await PluginDevelopmentWatcher.shared.stagingDirectory
    XCTAssertEqual(staging, PluginDirectory.developmentPluginsDirectory)
  }

  // MARK: - Runtime matching

  func testProcessRuntimeAcceptsValidExecutable() throws {
    let bundle = temporaryRoot.appendingPathComponent("native.plugin", isDirectory: true)
    try makePluginBundle(at: bundle, id: "com.example.native")
    let manifest = try PluginManifest.load(from: bundle.appendingPathComponent("plugin.json"))

    XCTAssertTrue(makeRuntime().canHost(manifest, at: .bundle(bundle)))
  }

  func testProcessRuntimeRefusesMissingExecutable() throws {
    let bundle = temporaryRoot.appendingPathComponent("noexec.plugin", isDirectory: true)
    try makePluginBundle(at: bundle, id: "com.example.noexec", writesExecutable: false)
    let manifest = try PluginManifest.load(from: bundle.appendingPathComponent("plugin.json"))

    XCTAssertFalse(makeRuntime().canHost(manifest, at: .bundle(bundle)))
  }

  func testASideloadedNativePluginIsRoutedToTheProcessRuntime() throws {
    let bundle = temporaryRoot.appendingPathComponent("routed.plugin", isDirectory: true)
    try makePluginBundle(at: bundle, id: "com.example.routed")
    let manifest = try PluginManifest.load(from: bundle.appendingPathComponent("plugin.json"))

    let selected = SnapzyRuntimeSelector().selectRuntime(
      for: manifest,
      trust: .sandboxedOnly,
      requiresInProcess: false,
      available: [.inProcess, .process]
    )

    XCTAssertEqual(selected, .process, "A sideloaded native plugin must land in the process runtime.")
  }

  // MARK: - Fixtures

  private func makeRuntime() -> SnapzyProcessRuntime {
    let broker = PluginServiceBroker(
      environment: PluginServiceBroker.Environment(
        pluginProvider: { _ in nil },
        decisionProvider: { request, _, _ in .denied(.undeclared(request.id)) },
        storageProvider: { _ in throw PluginServiceError(code: "unavailable", message: "no storage") },
        secrets: PluginSecretsStore(),
        invocations: PluginInvocationRegistry.shared
      )
    )
    return SnapzyProcessRuntime(
      supervisor: PluginProcessSupervisor(broker: broker, progressHandler: { _ in })
    )
  }

  private func makePluginBundle(
    at url: URL,
    id: String,
    writesExecutable: Bool = true
  ) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let manifest = """
      {
        "id": "\(id)",
        "version": "1.0.0",
        "displayName": "Fixture",
        "runtime": { "kind": "custom", "runtimeID": "process", "options": { "executable": "Plugin" } },
        "contributions": [{
          "extensionPoint": "com.snapzy.command",
          "name": "run",
          "contractVersion": "1.0.0",
          "metadata": { "title": "Run", "systemImage": "wand.and.stars", "accepts": ["screenshot"] }
        }]
      }
      """
    try Data(manifest.utf8).write(to: url.appendingPathComponent("plugin.json"))
    if writesExecutable {
      let macosDir = url.appendingPathComponent("Contents/MacOS", isDirectory: true)
      try FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)
      let execURL = macosDir.appendingPathComponent("Plugin")
      try Data("#!/bin/sh\nexit 0\n".utf8).write(to: execURL)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)
    }
  }
}
