import Foundation
import PluginKitCore
import SnapzyPluginAPI
import SnapzyPluginMessages
import SnapzyPluginProtocol
@testable import SnapzyPluginSDK

public final class PluginHarness<P: SnapzyPlugin>: Sendable {
  public let plugin: P
  public let host: FakeHost
  public let pluginID: String
  private let registry: CommandRegistry
  private let context: SnapzyPluginContext

  public init(
    _ pluginType: P.Type,
    host: FakeHost = FakeHost(),
    pluginID: String = "com.test.plugin",
    configuration: PluginKitCore.JSONValue = .object([:])
  ) {
    self.plugin = P()
    self.host = host
    self.pluginID = pluginID
    self.registry = CommandRegistry()
    let hostInfo = SnapzyPluginProtocol.HostInfo(
      appVersion: "1.0.0",
      appBuild: "1",
      osVersion: "macOS",
      hostID: "snapzy-test"
    )
    self.context = SnapzyPluginContext(
      pluginID: pluginID,
      host: hostInfo,
      configuration: configuration,
      commandRegistry: registry
    )
  }

  public func activate() async throws {
    try await plugin.activate(context)
  }

  public func invoke(
    _ command: String = "run",
    surface: SnapzySurface = .annotate,
    documentKind: SnapzyDocumentKind = .screenshot,
    document: SnapzyDocument? = nil,
    selection: [String] = [],
    options: PluginKitCore.JSONValue = .object([:]),
    invocationID: UUID = UUID()
  ) async throws -> CommandOutcome {
    if registry.registeredCommandNames.isEmpty {
      try await activate()
    }
    guard let handler = registry.handler(for: command) ?? registry.defaultHandler else {
      throw SnapzyPluginError.failed("No handler registered for command '\(command)'")
    }
    let request = SnapzyCommandRequest(
      invocationID: invocationID,
      surface: surface,
      documentKind: documentKind,
      document: document,
      selection: selection,
      options: options
    )
    let cmdCtx = CommandContext(
      pluginID: pluginID,
      invocationID: invocationID,
      request: request,
      dispatcher: host
    )
    return try await handler(request, cmdCtx)
  }

  public func execute(
    _ command: String = "run",
    surface: SnapzySurface = .annotate,
    documentKind: SnapzyDocumentKind = .screenshot,
    document: SnapzyDocument? = nil,
    selection: [String] = [],
    options: PluginKitCore.JSONValue = .object([:])
  ) async throws -> CommandOutcome {
    try await invoke(
      command,
      surface: surface,
      documentKind: documentKind,
      document: document,
      selection: selection,
      options: options
    )
  }

  public func deactivate() async {
    await plugin.deactivate()
  }
}
