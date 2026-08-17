import Foundation
import PluginKitHost
import SnapzyPluginAPI

/// The policy that makes isolation non-negotiable: a plugin cannot pick its
/// own runtime. First-party plugins *compiled into the app* run in-process
/// (`loadsBundles: false` — Snapzy never `dlopen`s anything, ever); every
/// third-party plugin runs in an isolated, sandboxed process (`.process`).
struct SnapzyRuntimeSelector: RuntimeSelector {
  func selectRuntime(
    for manifest: PluginManifest,
    trust: TrustLevel,
    requiresInProcess: Bool,
    available: [RuntimeID]
  ) -> RuntimeID? {
    // A local-only contract can only run in-process, so only first-party
    // plugins may target one. Everything Snapzy v1 publishes is remotable,
    // so this is fail-closed territory rather than a live path.
    if requiresInProcess {
      guard trust >= .firstParty, available.contains(.inProcess) else { return nil }
      return .inProcess
    }

    // Compiled-in first-party plugins may run in-process.
    if trust >= .firstParty, manifest.runtime.preferredRuntime == .inProcess,
      available.contains(.inProcess)
    {
      return .inProcess
    }

    // Native out-of-process Swift plugin (sandboxed child process)
    if available.contains(.process) {
      return .process
    }
    return nil
  }
}
