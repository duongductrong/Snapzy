import Foundation

/// The off-main serial executor for plugin-system services (broker, runtime
/// supervision, installer, request log). Keeps plugin work off the app's main
/// actor while preserving the plan's actor semantics — the Snapzy target is
/// Swift 5 language mode with default MainActor isolation, where `nonisolated`
/// type declarations are unavailable.
@globalActor
actor PluginEngine {
  static let shared = PluginEngine()
}
