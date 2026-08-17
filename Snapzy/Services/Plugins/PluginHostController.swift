import Combine
import Foundation
import PluginKitHost
import PluginKitInProcess
import SnapzyPluginAPI

/// The application-facing entry point for the plugin system, and the only
/// file in Snapzy that may import PluginKitHost. The rest of the app sees
/// `PluginSnapshot`, `PluginCommandItem`, and the coordinator — never a
/// PluginKit type, so if the framework has to be replaced the blast radius is
/// this file plus the runtime.
@MainActor
final class PluginHostController: ObservableObject {
  static let shared = PluginHostController()

  /// The plugin manager's decisions are reached through this broker too, so
  /// host-side checks and the manager can never disagree.
  let broker: PolicyCapabilityBroker

  let manager: PluginManager
  private let storageFactory: any PluginStorageFactory
  private let processSupervisor: PluginProcessSupervisor
  private let processRuntime: SnapzyProcessRuntime
  private var hasStarted = false

  /// UI state stream: the app renders from these snapshots.
  @Published private(set) var snapshots: [PluginSnapshot] = []

  /// Set once at the end of `init` so the broker's plugin provider can reach
  /// back without capturing `self` mid-initialization.
  private static weak var activeController: PluginHostController?

  /// Live command contracts, keyed by invocation, for cancellation.
  private var activeProxies: [UUID: NativeCommandProxy] = [:]

  private init() {
    // The two boundaries, built before PluginKit boots: the sandbox (helper)
    // and the broker (capability checks).
    let broker = PluginServiceBroker(
      environment: PluginServiceBroker.Environment(
        pluginProvider: { pluginID in
          await PluginHostController.activeController?.brokerRecord(for: pluginID)
        },
        decisionProvider: { request, identity, trust in
          await PluginHostController.activeController?.vend(request, to: identity, trust: trust)
            ?? .denied(.unavailable(request.id))
        },
        storageProvider: { pluginID in
          try await PluginHostController.activeController?.storage(for: pluginID)
            ?? (try InMemoryPluginStorage())
        },
        secrets: PluginSecretsStore(),
        invocations: PluginInvocationRegistry.shared
      )
    )

    let processSupervisor = PluginProcessSupervisor(
      broker: broker,
      progressHandler: { update in
        Task { @MainActor in
          PluginTaskStateStore.shared.update(update)
        }
      }
    )
    let processRuntime = SnapzyProcessRuntime(supervisor: processSupervisor)

    let world = SnapzyHostConfiguration.make(
      runtimes: [
        InProcessPluginRuntime(loadsBundles: false),
        processRuntime,
      ]
    )

    self.broker = world.broker
    self.manager = PluginManager(configuration: world.configuration)
    self.storageFactory = world.storageFactory
    self.processSupervisor = processSupervisor
    self.processRuntime = processRuntime

    PluginHostController.activeController = self
  }

  // MARK: - Lifecycle

  /// Boots PluginKit off the launch critical path. Never throws: failures
  /// land on records and in diagnostics; the app always has *some* state to
  /// render.
  func start() async {
    guard !hasStarted else { return }
    hasStarted = true

    await manager.start()
    await refreshSnapshots()

    #if DEBUG
    await emitCatalogDocument()
    #endif

    DiagnosticLogger.shared.log(
      .info, .plugin,
      "Plugin host started: \(snapshots.count) plugin(s)."
    )

    // Idle process reaping, hourly.
    let supervisor = self.processSupervisor
    Task.detached {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3_600))
        await supervisor.reapIdle()
      }
    }
  }

  /// Re-discovers sources (called after install/remove/load-from-folder).
  func restart() async {
    await manager.start()
    await refreshSnapshots()
  }

  func shutdown() async {
    await manager.shutdown()
    await PluginInvocationRegistry.shared.endAll()
  }

  // MARK: - Snapshots

  private func refreshSnapshots() async {
    let records = await manager.plugins()
    var snapshots: [PluginSnapshot] = []
    for record in records {
      snapshots.append(await Self.snapshot(for: record, manager: manager))
    }
    self.snapshots = snapshots.sorted { $0.displayName < $1.displayName }
  }

  private static func snapshot(for record: PluginRecord, manager: PluginManager) async -> PluginSnapshot {
    let tier = await PluginTierStore.shared.tier(for: record.id.rawValue)
    var problem = ""
    var warnings: [String] = []

    switch record.phase {
    case .unsatisfied:
      problem = record.unsatisfied?.description ?? "The plugin cannot run."
    case .rejected:
      problem = record.lastError ?? "The plugin was rejected."
    case .failed:
      problem = record.lastError ?? "The plugin failed to load."
    case .quarantined:
      problem = "Quarantined after \(record.failureCount) crash(es)."
    default:
      break
    }

    for warning in record.warnings {
      warnings.append(warning.detail)
    }

    // Command items, decoded from the manifest — no code loaded. A
    // contribution whose emitted ops this host does not support gets a
    // readable "requires newer Snapzy" sentence.
    var commands: [PluginCommandItem] = []
    let handles = await manager.contributions(to: SnapzyCommandPoint.self)
      .filter { $0.contributor.id == record.id }
    for handle in handles {
      commands.append(PluginCommandCatalog.makeItem(handle: handle, pluginName: record.manifest.displayName))
      if let explanation = PluginDocumentCapabilityNegotiator.explanation(for: handle.metadata.emits) {
        problem = explanation
      }
    }

    return PluginSnapshot(
      id: record.id.rawValue,
      version: record.manifest.version.description,
      displayName: record.manifest.displayName,
      summary: record.manifest.summary,
      phase: record.phase.rawValue,
      tier: tier,
      trust: record.trust.description,
      problem: problem,
      warnings: warnings,
      declaredCapabilities: record.manifest.capabilities,
      contributions: commands,
      failureCount: record.failureCount,
      userEnabled: record.userEnabled,
      locationPath: Self.locationPath(record)
    )
  }

  private static func locationPath(_ record: PluginRecord) -> String? {
    if case .bundle(let url) = record.location {
      return url.path
    }
    return nil
  }

  // MARK: - Broker wiring

  /// Maps a record to the broker's minimal view.
  private func brokerRecord(for pluginID: String) async -> PluginServiceBroker.PluginBrokerRecord? {
    guard let record = await manager.plugin(PluginID(pluginID)) else { return nil }
    return PluginServiceBroker.PluginBrokerRecord(
      identity: record.identity,
      trust: record.trust,
      manifestCapabilities: record.manifest.capabilities
    )
  }

  /// The broker's capability decision: policy + consent, attenuated scope.
  private func vend(
    _ request: CapabilityRequest,
    to identity: PluginIdentity,
    trust: TrustLevel
  ) async -> CapabilityDecision {
    await broker.vend(request, to: identity, trust: trust)
  }

  private func storage(for pluginID: String) async throws -> PluginStorage {
    try storageFactory.makeStorage(
      for: PluginIdentity(id: PluginID(pluginID), version: "0.0.0", displayName: pluginID)
    )
  }

  /// The plugin's recorded manifest capabilities (authoritative for scope
  /// checks).
  func manifestCapabilities(for pluginID: String) async -> [CapabilityRequest] {
    (await manager.plugin(PluginID(pluginID)))?.manifest.capabilities ?? []
  }

  /// Gated document-write consent: the ops actually used in a patch must be
  /// declared and consented. Returns the ops that passed both gates.
  func gateDocumentWrite(
    pluginID: String,
    ops: [DocumentEditKind]
  ) async -> [DocumentEditKind] {
    guard let record = await manager.plugin(PluginID(pluginID)) else { return [] }
    guard let request = record.manifest.capabilities.first(where: { $0.id == SnapzyDocumentWrite.capabilityID }) else {
      return []
    }

    // Declared ops from the manifest scope.
    var declaredOps: Set<DocumentEditKind> = []
    if case .object(let object) = request.scope, case .array(let values)? = object["ops"] {
      for value in values {
        if case .string(let raw) = value, let op = DocumentEditKind(rawValue: raw) {
          declaredOps.insert(op)
        }
      }
    }

    // Only declared ops may be requested.
    let requested = ops.filter { declaredOps.contains($0) }
    guard !requested.isEmpty else { return [] }

    // Consent gate with the actual ops as the requested scope.
    let consentRequest = CapabilityRequest(
      id: SnapzyDocumentWrite.capabilityID,
      scope: .object(["ops": .array(requested.map { .string($0.rawValue) })]),
      required: request.required,
      reason: request.reason
    )
    let decision = await broker.vend(consentRequest, to: record.identity, trust: record.trust)
    guard decision.capability != nil else { return [] }
    return requested
  }

  // MARK: - Queries used by the catalog / coordinator

  /// All command items across installed plugins. No I/O, no plugin code.
  func commandItems() async -> [PluginCommandItem] {
    let handles = await manager.contributions(to: SnapzyCommandPoint.self)
    return PluginCommandCatalog.items(from: handles)
  }

  /// Resolves a command item into its live contract (loads the plugin here,
  /// first use). Native command proxies are tracked per invocation so cancellation
  /// can reach the supervisor.
  func resolveContract(
    for item: PluginCommandItem,
    invocationID: UUID
  ) async throws -> any SnapzyCommand {
    guard let box = item.handle as? SnapzyCommandHandleBox else {
      throw PluginCommandError.pluginFailed(code: "internal", message: "Unresolvable handle.")
    }
    let contract = try await box.handle.resolve()
    if let proxy = contract as? NativeCommandProxy {
      activeProxies[invocationID] = proxy
    }
    return contract
  }

  /// Tells the helper hosting the invocation's plugin to stop.
  func cancelInvocation(_ invocationID: UUID) {
    guard let proxy = activeProxies.removeValue(forKey: invocationID) else { return }
    proxy.cancel(invocationID: invocationID)
  }

  /// Marks a plugin enabled/disabled.
  func setEnabled(_ pluginID: String, _ enabled: Bool) async {
    try? await manager.setEnabled(PluginID(pluginID), enabled)
    await refreshSnapshots()
  }

  /// Revokes consent for a plugin (detail view reset).
  func revokeConsent(for pluginID: String) async {
    await manager.revokeConsent(for: PluginID(pluginID))
  }

  /// Removes an installed plugin: bundle, settings, storage, secrets, consent.
  func removePlugin(_ pluginID: String) async {
    await manager.deactivate(PluginID(pluginID))
    await manager.revokeConsent(for: PluginID(pluginID))
    PluginSecretsStore().deleteAll(pluginID: pluginID)
    await PluginTierStore.shared.remove(pluginID: pluginID)
    if let directory = PluginDirectory.installedPluginDirectory(id: pluginID) {
      try? FileManager.default.removeItem(at: directory)
    }
    if let dataDirectory = PluginDirectory.pluginDirectory(id: pluginID, in: PluginDirectory.pluginDataDirectory) {
      try? FileManager.default.removeItem(at: dataDirectory)
    }
    await PluginDevelopmentWatcher.shared.remove(pluginID: pluginID)
    await restart()
  }

  // MARK: - Invocation bookkeeping

  func beginInvocation(kind: SnapzyDocumentKind, assetURL: URL) async -> UUID {
    let id = UUID()
    await PluginInvocationRegistry.shared.begin(invocationID: id, assetURL: assetURL, kind: kind)
    return id
  }

  func endInvocation(_ id: UUID) async {
    await PluginInvocationRegistry.shared.end(invocationID: id)
  }

  // MARK: - Catalog emission

  /// Writes the vocabulary catalog into the built bundle, for the `pluginkit`
  /// CLI.
  private func emitCatalogDocument() async {
    let document = await manager.catalogDocument()
    guard let data = try? JSONEncoder().encode(document) else { return }
    guard let resources = Bundle.main.resourceURL?
      .appendingPathComponent("PluginAPI", isDirectory: true)
    else { return }
    do {
      try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
      try data.write(to: resources.appendingPathComponent("catalog.json"), options: .atomic)
    } catch {
      DiagnosticLogger.shared.log(.warning, .plugin, "Could not emit the plugin catalog: \(error)")
    }
  }
}
