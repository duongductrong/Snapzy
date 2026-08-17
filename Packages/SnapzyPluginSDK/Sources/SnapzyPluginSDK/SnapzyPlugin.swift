import Foundation
import PluginKitCore
import SnapzyPluginAPI

public typealias JSONValue = PluginKitCore.JSONValue

/// The root protocol for a Snapzy plugin.
///
/// An author conforms to `SnapzyPlugin` and annotates the conforming type
/// with `@main`. The SDK handles the process lifecycle, sandboxing self-check,
/// wire protocol handshake, capability routing, and cancellation.
///
/// ```swift
/// import SnapzyPluginSDK
///
/// @main
/// struct MyPlugin: SnapzyPlugin {
///   init() {}
///
///   func activate(_ context: SnapzyPluginContext) async throws {
///     context.command("run") { request, ctx in
///       let image = try await ctx.asset.read()
///       return .text("Captured \(image.count) bytes")
///     }
///   }
/// }
/// ```
public protocol SnapzyPlugin: Sendable {
  init()

  /// Called once when the plugin is activated. Register command handlers here.
  func activate(_ context: SnapzyPluginContext) async throws

  /// Called before the plugin is deactivated or shut down.
  func deactivate() async

  /// Called to verify plugin health. Returns true if healthy.
  func healthCheck() async -> Bool

  /// Called before upgrading from a previous version.
  func willUpgrade(from previousVersion: String, context: SnapzyPluginContext) async throws
}

public extension SnapzyPlugin {
  func deactivate() async {}
  func healthCheck() async -> Bool { true }
  func willUpgrade(from previousVersion: String, context: SnapzyPluginContext) async throws {}
}
