import Combine
import Foundation
import PluginKitHost
import SnapzyPluginAPI

/// Builds `PluginCommandItem`s from manifest metadata — **no I/O, no plugin
/// code, no PluginManager lookup**. The filter is one question: is this plugin
/// enabled, does it accept this document kind, and does the host support the
/// ops it emits? Anything per-surface is coupling that will rot.
enum PluginCommandCatalog {
  /// All command items, metadata-only.
  static func items(from handles: [ExtensionHandle<SnapzyCommandPoint>]) -> [PluginCommandItem] {
    handles.map { makeItem(handle: $0, pluginName: $0.contributor.displayName) }
      .sorted { ($0.pluginName, $0.title) < ($1.pluginName, $1.title) }
  }

  /// One command item from a handle. `disabledReason` is set when the
  /// contribution's emitted ops are unsupported — the command still appears,
  /// visibly disabled, rather than silently vanishing.
  static func makeItem(
    handle: ExtensionHandle<SnapzyCommandPoint>,
    pluginName: String
  ) -> PluginCommandItem {
    let metadata = handle.metadata
    let disabledReason = PluginDocumentCapabilityNegotiator.explanation(for: metadata.emits)
    return PluginCommandItem(
      id: "\(handle.contributor.id.rawValue)#\(handle.name)",
      pluginID: handle.contributor.id.rawValue,
      pluginName: pluginName,
      name: handle.name,
      title: metadata.title,
      systemImage: metadata.systemImage,
      accepts: metadata.accepts,
      emits: metadata.emits,
      isLongRunning: metadata.isLongRunning,
      disabledReason: disabledReason,
      handle: SnapzyCommandHandleBox(handle: handle, emitted: metadata.emits)
    )
  }

  /// Filters items for a surface: enabled, accepts the kind, ops supported.
  /// Runs no plugin code and performs no I/O.
  static func commands(
    _ items: [PluginCommandItem],
    for documentKind: SnapzyDocumentKind
  ) -> [PluginCommandItem] {
    items.filter { item in
      guard item.disabledReason == nil else { return false }
      guard item.accepts.isEmpty || item.accepts.contains(documentKind) else { return false }
      return true
    }
  }
}

/// Long-running commands surface progress here, keyed by invocation.
@MainActor
final class PluginTaskStateStore: ObservableObject {
  static let shared = PluginTaskStateStore()

  struct TaskState: Equatable {
    let pluginID: String
    let title: String
    var fraction: Double?
    var message: String?
    var isCancelled = false
  }

  @Published private(set) var tasks: [UUID: TaskState] = [:]

  func begin(invocationID: UUID, pluginID: String, title: String) {
    tasks[invocationID] = TaskState(pluginID: pluginID, title: title)
  }

  func update(_ update: SnapzyPluginIPC.ProgressUpdate) {
    guard var task = tasks[update.invocationID] else { return }
    if let fraction = update.fraction {
      task.fraction = min(max(fraction, 0), 1)
    }
    if let message = update.message {
      task.message = message
    }
    tasks[update.invocationID] = task
  }

  func finish(invocationID: UUID) {
    tasks[invocationID] = nil
  }

  func task(for invocationID: UUID) -> TaskState? {
    tasks[invocationID]
  }
}
