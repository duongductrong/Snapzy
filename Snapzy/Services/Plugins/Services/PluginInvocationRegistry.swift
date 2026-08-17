import Foundation
import SnapzyPluginAPI

/// Asset read is per-invocation, never ambient: `snapzy.asset.read` is valid
/// only for the `invocationID` in the current request, and only while that
/// invocation is live. A plugin cannot read anything the user did not point it
/// at, and cannot read later, in the background, or for a different document.
@PluginEngine
final class PluginInvocationRegistry {
  static let shared = PluginInvocationRegistry()

  struct LiveInvocation {
    let assetURL: URL
    let kind: SnapzyDocumentKind
  }

  private var invocations: [UUID: LiveInvocation] = [:]

  func begin(invocationID: UUID, assetURL: URL, kind: SnapzyDocumentKind) {
    invocations[invocationID] = LiveInvocation(assetURL: assetURL, kind: kind)
  }

  func end(invocationID: UUID) {
    invocations[invocationID] = nil
  }

  func assetURL(for invocationID: UUID) -> URL? {
    invocations[invocationID]?.assetURL
  }

  func kind(for invocationID: UUID) -> SnapzyDocumentKind? {
    invocations[invocationID]?.kind
  }

  func endAll() {
    invocations.removeAll()
  }
}
