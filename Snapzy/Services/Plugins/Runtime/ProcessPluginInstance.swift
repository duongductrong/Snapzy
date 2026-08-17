import Foundation
import PluginKitCore
import PluginKitHost
import SnapzyPluginAPI
import SnapzyPluginMessages
import SnapzyPluginProtocol

final class ProcessPluginInstance: PluginInstance, @unchecked Sendable {
  let identity: PluginIdentity
  private let manifest: PluginManifest
  private let executableURL: URL
  private let supervisor: PluginProcessSupervisor
  private var channel: FrameChannel?
  private var contracts: [String: any Sendable] = [:]
  private let lock = NSLock()

  init(
    plugin: ResolvedPlugin,
    executableURL: URL,
    supervisor: PluginProcessSupervisor
  ) {
    self.identity = plugin.identity
    self.manifest = plugin.manifest
    self.executableURL = executableURL
    self.supervisor = supervisor
  }

  func activate() async throws {
    let chan = try await supervisor.connection(
      for: identity.id.rawValue,
      executableURL: executableURL,
      manifest: manifest,
      options: .object([:])
    )
    lock.lock()
    self.channel = chan
    lock.unlock()
  }

  func deactivate() async {
    await supervisor.deactivate(pluginID: identity.id.rawValue)
    lock.lock()
    self.channel = nil
    lock.unlock()
  }

  func contract(for point: ExtensionPointID, contribution name: String) async throws -> any Sendable {
    lock.lock()
    let key = "\(point.rawValue)#\(name)"
    if let cached = contracts[key] {
      lock.unlock()
      return cached
    }
    guard let chan = self.channel else {
      lock.unlock()
      throw PluginKitError.runtime(.notActive(identity.id))
    }
    lock.unlock()

    guard point == SnapzyCommandPoint.extensionPointID else {
      throw PluginKitError.extensionPoint(.unknownExtensionPoint(point))
    }

    let isLongRunning = manifest.contributions.first {
      $0.extensionPoint == point && $0.name == name
    }?.metadata["isLongRunning"]?.boolValue ?? false

    let proxy = NativeCommandProxy(
      pluginID: identity.id.rawValue,
      channel: chan,
      isLongRunning: isLongRunning
    )

    lock.lock()
    contracts[key] = proxy
    lock.unlock()

    return proxy
  }

  func service(_ id: ServiceID) async throws -> any Sendable {
    throw PluginKitError.extensionPoint(.unknownExtensionPoint(ExtensionPointID(id.rawValue)))
  }

  func health() async -> PluginHealth {
    lock.lock()
    guard let chan = self.channel else {
      lock.unlock()
      return .crashed
    }
    lock.unlock()

    let healthMsg = HostMessage.healthCheck(SnapzyPluginIPC.HealthRequest(pluginID: identity.id.rawValue))
    guard let (kind, payload) = try? healthMsg.encode() else { return .unresponsive }

    do {
      let reply = try await chan.request(kind, payload: payload)
      let msg = try PluginMessage.decode(kind: reply.kind, payload: reply.payload)
      if case .result(let resp) = msg,
         case .success(let json) = resp.outcome,
         json["status"]?.stringValue == "ok" {
        return .ok
      }
      return .unresponsive
    } catch {
      return .unresponsive
    }
  }
}
