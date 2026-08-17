import Foundation
import PluginKitCore
import SnapzyPluginAPI
import SnapzyPluginMessages
import SnapzyPluginProtocol

public typealias CommandHandler = @Sendable (SnapzyCommandRequest, CommandContext) async throws -> CommandOutcome

public final class SnapzyPluginContext: Sendable {
  public let pluginID: String
  public let host: SnapzyPluginProtocol.HostInfo
  public let configuration: PluginKitCore.JSONValue
  private let commandRegistry: CommandRegistry

  public init(
    pluginID: String,
    host: SnapzyPluginProtocol.HostInfo,
    configuration: PluginKitCore.JSONValue,
    commandRegistry: CommandRegistry
  ) {
    self.pluginID = pluginID
    self.host = host
    self.configuration = configuration
    self.commandRegistry = commandRegistry
  }

  public func command(_ name: String, handler: @escaping CommandHandler) {
    commandRegistry.register(name: name, handler: handler)
  }
}

public final class CommandRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var handlers: [String: CommandHandler] = [:]

  public init() {}

  public func register(name: String, handler: @escaping CommandHandler) {
    lock.lock()
    defer { lock.unlock() }
    handlers[name] = handler
  }

  public func handler(for name: String) -> CommandHandler? {
    lock.lock()
    defer { lock.unlock() }
    return handlers[name]
  }

  public var defaultHandler: CommandHandler? {
    lock.lock()
    defer { lock.unlock() }
    if handlers.count == 1 {
      return handlers.values.first
    }
    return handlers["run"] ?? handlers["default"]
  }

  public var registeredCommandNames: [String] {
    lock.lock()
    defer { lock.unlock() }
    return Array(handlers.keys)
  }
}
