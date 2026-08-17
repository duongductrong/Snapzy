import Foundation
import PluginKitCore

/// The application-facing entry point to PluginKit.
///
/// An actor because plugin state is genuinely shared and genuinely contended: a
/// preferences panel, a menu click, a filesystem change, and a background refresh
/// can all touch it at once. Serialising through an actor removes that class of bug
/// rather than documenting a locking discipline nobody will follow.
///
/// Everything it needs arrives through ``HostConfiguration``; it reaches for no
/// globals, so a test can build one with in-memory stores and a fake runtime and
/// get fully deterministic behaviour.
///
/// ```swift
/// let manager = PluginManager(configuration: configuration)
/// await manager.start()
///
/// for handle in await manager.contributions(to: CommandPoint.self) {
///     palette.add(handle.metadata.title) {
///         try await handle.resolve().handle(RunCommand(...))   // loads here, not before
///     }
/// }
/// ```
public actor PluginManager {
    private let configuration: HostConfiguration

    private var records: [PluginID: PluginRecord] = [:]
    private var resolvedPlugins: [PluginID: ResolvedPlugin] = [:]
    private var loaded: [PluginID: LoadedPlugin] = [:]
    /// In-flight activations, so two concurrent `resolve()` calls on the same
    /// plugin produce one activation rather than two.
    private var activations: [PluginID: Task<Void, any Error>] = [:]
    /// Source precedence, by rank. Decided once at construction so ordering is
    /// stable for the life of the manager.
    private let sourceRank: [SourceID: Int]
    private var hasStarted = false

    private var observers: [UUID: AsyncStream<PluginManagerEvent>.Continuation] = [:]
    private var lifecycleObservers: [PluginID: [UUID: AsyncStream<HostLifecycleEvent>.Continuation]] = [:]

    private struct LoadedPlugin {
        let instance: any PluginInstance
        let context: HostPluginContext
        let registrar: ContributionRegistrar
    }

    public init(configuration: HostConfiguration) {
        self.configuration = configuration
        var rank: [SourceID: Int] = [:]
        for (index, source) in configuration.sources.enumerated() where rank[source.sourceID] == nil {
            rank[source.sourceID] = index
        }
        self.sourceRank = rank
    }

    // MARK: - Lifecycle

    /// Discovers, validates, and resolves every plugin, then activates only those
    /// declaring eager activation.
    ///
    /// **Never throws.** A launch path has to produce *some* state — an app that
    /// fails to start because one plugin bundle is corrupt is worse than one that
    /// starts with that plugin listed as broken. Failures land on the records and
    /// in diagnostics.
    ///
    /// Safe to call again; it re-runs discovery and applies the difference.
    public func start() async {
        broadcast(.startedDiscovery)
        await configuration.diagnostics.record(
            DiagnosticEvent(kind: .discovered, plugin: nil, detail: "Discovery started.")
        )

        let candidates = await discover()
        var newRecords: [PluginID: PluginRecord] = [:]

        for candidate in candidates {
            newRecords[candidate.id] = await validate(candidate)
        }

        // Dependency resolution needs every candidate's phase settled first: a
        // plugin cannot know whether its dependency is satisfiable until the
        // dependency itself has been validated.
        newRecords = resolveDependencies(in: newRecords)

        // Plugins that disappeared must be shut down before their records go.
        for id in records.keys where newRecords[id] == nil {
            await deactivate(id, reason: "No longer present in any source.")
            resolvedPlugins[id] = nil
        }

        records = newRecords
        hasStarted = true

        let resolved = records.values.filter { $0.phase == .resolved }.count
        let rejected = records.values.filter { $0.phase == .rejected }.count
        broadcast(.finishedDiscovery(
            discovered: records.count, resolved: resolved, rejected: rejected
        ))
        broadcast(.registryChanged)

        guard !configuration.safeMode else {
            configuration.log.log(
                .notice, plugin: nil,
                "Safe mode: \(records.count) plugin(s) discovered, none will be loaded."
            )
            return
        }

        for record in records.values where record.phase == .resolved && record.manifest.activation.isEager {
            do {
                try await ensureActive(record.id)
            } catch {
                configuration.log.log(
                    .error, plugin: record.id,
                    "Eager activation failed: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Deactivates everything, in reverse dependency order.
    public func shutdown() async {
        publishLifecycle(.willTerminate)
        for id in shutdownOrder() {
            await deactivate(id, reason: "Host is shutting down.")
        }
        for continuation in observers.values { continuation.finish() }
        observers.removeAll()
    }

    // MARK: - Queries

    /// Every installed plugin, sorted by display name.
    public func plugins() -> [PluginRecord] {
        records.values.sorted { $0.manifest.displayName < $1.manifest.displayName }
    }

    public func plugin(_ id: PluginID) -> PluginRecord? { records[id] }

    /// Handles for every contribution to a point, ordered by the point's arity.
    ///
    /// **No plugin code is loaded by this call.** Metadata comes from manifests, so
    /// a host can build its full menu structure at launch and pay for a plugin only
    /// when someone uses it.
    ///
    /// A contribution whose metadata fails to decode is skipped and reported rather
    /// than crashing the caller: one plugin's bad manifest must not be able to
    /// empty another plugin's menu.
    public func contributions<P: ExtensionPoint>(to point: P.Type) -> [ExtensionHandle<P>] {
        var handles: [ExtensionHandle<P>] = []

        for record in records.values where record.isAvailable {
            for contribution in record.manifest.contributions
            where contribution.extensionPoint == P.extensionPointID {
                let metadata: P.Metadata
                do {
                    metadata = try contribution.metadata.decode(as: P.Metadata.self)
                } catch {
                    configuration.log.log(
                        .error, plugin: record.id,
                        "Skipping contribution '\(contribution.name)' to "
                            + "'\(P.extensionPointID)': \(error.localizedDescription)"
                    )
                    continue
                }

                let pluginID = record.id
                let name = contribution.name
                handles.append(
                    ExtensionHandle<P>(
                        id: ContributionKey(
                            plugin: pluginID, extensionPoint: P.extensionPointID, name: name
                        ),
                        contributor: record.identity,
                        name: name,
                        metadata: metadata,
                        priority: contribution.priority,
                        resolver: { [self] in
                            try await contract(P.self, from: pluginID, name: name)
                        }
                    )
                )
            }
        }

        handles = sort(handles, arity: P.arity)
        if case .single = P.arity { return Array(handles.prefix(1)) }
        return handles
    }

    /// Resolves one contribution's contract, activating its plugin if needed.
    ///
    /// This is where lazy loading actually happens.
    public func contract<P: ExtensionPoint>(
        _ point: P.Type,
        from plugin: PluginID,
        name: String
    ) async throws -> P.Contract {
        try await ensureActive(plugin)

        guard let loadedPlugin = loaded[plugin] else {
            throw PluginKitError.runtime(.notActive(plugin))
        }

        let clock = ContinuousClock()
        let began = clock.now
        let value = try await loadedPlugin.instance.contract(
            for: P.extensionPointID, contribution: name
        )
        let elapsed = clock.now - began

        guard let typed = value as? P.Contract else {
            throw PluginKitError.extensionPoint(
                .contractTypeMismatch(
                    point: P.extensionPointID,
                    expected: configuration.extensionPoints.contractTypeName(for: P.extensionPointID),
                    found: String(describing: type(of: value))
                )
            )
        }

        await configuration.diagnostics.record(
            DiagnosticEvent(
                kind: .contractResolved,
                plugin: plugin,
                detail: "\(P.extensionPointID)#\(name)",
                duration: elapsed
            )
        )
        return typed
    }

    /// Observable manager events, for a plugin manager UI.
    public func events() -> AsyncStream<PluginManagerEvent> {
        AsyncStream { continuation in
            let id = UUID()
            observers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    public var diagnostics: PluginDiagnostics { configuration.diagnostics }

    /// The machine-readable vocabulary description, for a host to write into its
    /// own bundle so `pluginkit describe` can read it.
    public func catalogDocument() -> CatalogDocument {
        configuration.extensionPoints.document(
            appIdentifier: configuration.appIdentifier,
            appVersion: configuration.appVersion,
            vocabularies: configuration.vocabularies,
            capabilities: configuration.capabilities.descriptors
        )
    }

    // MARK: - User actions

    /// Turns a plugin on or off, persisting the choice.
    public func setEnabled(_ id: PluginID, _ enabled: Bool) async throws {
        guard var record = records[id] else { throw PluginKitError.unknownPlugin(id) }
        await configuration.enablement.setEnabled(id, enabled)
        record.userEnabled = enabled

        if enabled {
            if record.phase == .unsatisfied, record.unsatisfied == .disabledByUser {
                record.phase = .resolved
                record.unsatisfied = nil
            }
            records[id] = record
        } else {
            records[id] = record
            await deactivate(id, reason: "Turned off.")
            var updated = records[id] ?? record
            updated.phase = .unsatisfied
            updated.unsatisfied = .disabledByUser
            records[id] = updated
        }
        broadcast(.registryChanged)
    }

    /// Deactivates a plugin without changing whether it is enabled.
    public func deactivate(_ id: PluginID) async {
        await deactivate(id, reason: "Requested by the host.")
    }

    /// Forgets consent decisions for a plugin.
    ///
    /// Does not deactivate it: the plugin keeps running with whatever it already
    /// holds until it is next activated. A host wanting immediate effect should
    /// deactivate afterwards — made explicit because silently tearing down a
    /// running plugin from a permissions screen would be a surprising side effect.
    public func revokeConsent(for id: PluginID, capability: CapabilityID? = nil) async {
        await configuration.consent.revoke(for: id, capability: capability)
    }

    /// Publishes a host lifecycle event to every active plugin.
    public func publishLifecycle(_ event: HostLifecycleEvent) {
        for continuations in lifecycleObservers.values {
            for continuation in continuations.values { continuation.yield(event) }
        }
    }

    /// Publishes a host event onto the bus.
    public func publish<Event: PluginEvent>(_ event: Event) async {
        await configuration.eventBus.publishFromHost(event)
    }

    // MARK: - Discovery

    private func discover() async -> [DiscoveredPlugin] {
        var seen: [PluginID: DiscoveredPlugin] = [:]
        var shadowed: [(winner: DiscoveredPlugin, loser: DiscoveredPlugin)] = []

        for source in configuration.sources {
            let found: [DiscoveredPlugin]
            do {
                found = try await source.discover()
            } catch {
                configuration.log.log(
                    .error, plugin: nil,
                    "Source '\(source.sourceID)' failed: \(error.localizedDescription)"
                )
                continue
            }

            for candidate in found {
                if let incumbent = seen[candidate.id] {
                    // Earlier source wins. Never silent: a user-dropped plugin
                    // quietly overriding an IT-deployed one is a support incident
                    // waiting to happen, so the shadowing is recorded either way.
                    shadowed.append((winner: incumbent, loser: candidate))
                    continue
                }
                seen[candidate.id] = candidate
            }
        }

        for pair in shadowed {
            await configuration.diagnostics.record(
                DiagnosticEvent(
                    kind: .shadowed,
                    plugin: pair.loser.id,
                    detail: "'\(pair.loser.id)' from '\(pair.loser.source)' is shadowed by "
                        + "the copy from '\(pair.winner.source)'."
                )
            )
        }

        return seen.values.sorted { lhs, rhs in
            (sourceRank[lhs.source] ?? .max, lhs.id.rawValue)
                < (sourceRank[rhs.source] ?? .max, rhs.id.rawValue)
        }
    }

    /// Everything checkable without loading code.
    private func validate(_ candidate: DiscoveredPlugin) async -> PluginRecord {
        let manifest = candidate.manifest
        var record = PluginRecord(
            manifest: manifest,
            source: candidate.source,
            location: candidate.location,
            trust: .sandboxedOnly,
            phase: .discovered,
            userEnabled: await configuration.enablement.isEnabled(manifest.id)
        )

        func reject(_ message: String) async -> PluginRecord {
            record.phase = .rejected
            record.lastError = message
            await configuration.diagnostics.record(
                DiagnosticEvent(kind: .rejected, plugin: manifest.id, detail: message)
            )
            configuration.log.log(.error, plugin: manifest.id, "Rejected: \(message)")
            return record
        }

        func unsatisfy(_ reason: UnsatisfiedReason) async -> PluginRecord {
            record.phase = .unsatisfied
            record.unsatisfied = reason
            await configuration.diagnostics.record(
                DiagnosticEvent(
                    kind: .unsatisfied, plugin: manifest.id, detail: reason.description
                )
            )
            return record
        }

        do {
            try manifest.validateStructure()
        } catch {
            return await reject(error.localizedDescription)
        }

        guard manifest.sdkVersion.contains(PluginKitVersion.current) else {
            return await reject(
                PluginManifestError.incompatibleSDK(
                    required: manifest.sdkVersion, hostProvides: PluginKitVersion.current
                ).localizedDescription ?? "Incompatible PluginKit version."
            )
        }

        if let required = manifest.minimumOSVersion, !Self.systemSatisfies(required) {
            return await unsatisfy(
                .disabledByPolicy(reason: "Requires macOS \(required) or later.")
            )
        }

        switch await configuration.trustPolicy.evaluate(candidate) {
        case .blocked(let reason):
            return await reject(reason.localizedDescription ?? "Refused by the trust policy.")
        case .trusted(let level):
            record = PluginRecord(
                manifest: manifest,
                source: candidate.source,
                location: candidate.location,
                trust: level,
                phase: .validated,
                userEnabled: record.userEnabled
            )
        }

        // Vocabulary compatibility. Checked before contributions so a plugin built
        // against the wrong generation reports *that*, rather than a cascade of
        // per-point mismatches that all have the same cause.
        for dependency in manifest.contracts {
            guard let hostVersion = configuration.vocabularyVersion(dependency.vocabulary) else {
                continue
            }
            guard dependency.compatibleWith.contains(hostVersion) else {
                return await unsatisfy(
                    .vocabularyUnsupported(
                        dependency.vocabulary,
                        required: dependency.compatibleWith,
                        hostProvides: hostVersion
                    )
                )
            }
        }

        let permitsInProcess = configuration.runtimeSelector.selectRuntime(
            for: manifest,
            trust: record.trust,
            requiresInProcess: true,
            available: [.inProcess]
        ) == .inProcess

        for contribution in manifest.contributions {
            if let error = configuration.extensionPoints.validate(
                contribution, permitsInProcess: permitsInProcess
            ) {
                return await unsatisfy(.extensionPoint(error))
            }
            if let warning = configuration.extensionPoints.deprecationWarning(for: contribution) {
                record.warnings.append(warning)
                await configuration.diagnostics.record(
                    DiagnosticEvent(
                        kind: .deprecationWarning, plugin: manifest.id, detail: warning.detail
                    )
                )
            }
        }

        // A *required* capability the host does not implement at all is a static
        // fact, checkable now. Whether policy or the user will permit it is not —
        // prompting during discovery would ask about plugins that may never run.
        for request in manifest.capabilities
        where request.required && configuration.capabilities.entry(for: request.id) == nil {
            return await unsatisfy(
                .requiredCapabilityDenied(request.id, reason: "This host does not provide it.")
            )
        }

        if record.userEnabled == false {
            return await unsatisfy(.disabledByUser)
        }

        if configuration.safeMode {
            return await unsatisfy(.disabledByPolicy(reason: "Safe mode is on."))
        }

        // Runtime availability last: it is the check most likely to be relaxed by
        // configuration, so everything genuinely wrong with the plugin is reported
        // in preference to it.
        let available = configuration.runtimes
            .filter { $0.canHost(manifest, at: candidate.location) }
            .map(\.runtimeID)
        let requiresInProcess = configuration.extensionPoints
            .requiresInProcess(manifest.contributions)

        guard let runtime = configuration.runtimeSelector.selectRuntime(
            for: manifest,
            trust: record.trust,
            requiresInProcess: requiresInProcess,
            available: available
        ) else {
            return await unsatisfy(
                .noRuntimeAvailable(
                    requested: manifest.runtime.preferredRuntime,
                    trust: record.trust.description
                )
            )
        }

        record.runtime = runtime
        if runtime == .inProcess, record.trust < .firstParty {
            record.warnings.append(
                PluginWarning(
                    kind: .unisolated,
                    detail: "Running in the host's address space, so its capability grants are "
                        + "a disclosure contract rather than an enforced boundary.",
                    guidance: "Ship an isolating runtime to enforce them."
                )
            )
        }

        record.phase = .resolved
        resolvedPlugins[manifest.id] = ResolvedPlugin(
            manifest: manifest,
            location: candidate.location,
            source: candidate.source,
            trust: record.trust,
            runtime: runtime
        )
        await configuration.diagnostics.record(
            DiagnosticEvent(kind: .resolved, plugin: manifest.id, detail: "Runtime: \(runtime).")
        )
        return record
    }

    /// Checks dependencies once every candidate's phase is known.
    private func resolveDependencies(in candidates: [PluginID: PluginRecord]) -> [PluginID: PluginRecord] {
        var result = candidates

        for (id, record) in candidates where record.phase == .resolved {
            var updated = record
            var failed = false

            for dependency in record.manifest.dependencies {
                guard let target = candidates[dependency.id], target.phase.contributesToRegistry else {
                    if dependency.required {
                        updated.phase = .unsatisfied
                        updated.unsatisfied = .missingDependency(dependency.id)
                        failed = true
                        break
                    }
                    updated.warnings.append(
                        PluginWarning(
                            kind: .optionalDependencyMissing,
                            detail: "Optional dependency '\(dependency.id)' is not available."
                        )
                    )
                    continue
                }

                guard dependency.versions.contains(target.manifest.version) else {
                    if dependency.required {
                        updated.phase = .unsatisfied
                        updated.unsatisfied = .dependencyVersionMismatch(
                            dependency.id,
                            required: dependency.versions,
                            found: target.manifest.version
                        )
                        failed = true
                        break
                    }
                    continue
                }
            }

            if !failed, let cycle = Self.findCycle(from: id, in: candidates) {
                updated.phase = .unsatisfied
                updated.unsatisfied = .dependencyCycle(cycle)
            }

            result[id] = updated
            if updated.phase != .resolved { resolvedPlugins[id] = nil }
        }

        return result
    }

    /// Depth-first search for a dependency cycle reachable from `start`.
    ///
    /// Rejected outright rather than broken arbitrarily: picking an activation
    /// order for a cycle means picking which plugin sees a half-initialised peer,
    /// and there is no correct answer to that.
    private static func findCycle(
        from start: PluginID,
        in candidates: [PluginID: PluginRecord]
    ) -> [PluginID]? {
        var path: [PluginID] = []
        var visiting = Set<PluginID>()

        func visit(_ id: PluginID) -> [PluginID]? {
            if visiting.contains(id) {
                let cycleStart = path.firstIndex(of: id) ?? 0
                return Array(path[cycleStart...]) + [id]
            }
            guard let record = candidates[id] else { return nil }
            visiting.insert(id)
            path.append(id)
            defer {
                visiting.remove(id)
                path.removeLast()
            }
            for dependency in record.manifest.dependencies {
                if let cycle = visit(dependency.id) { return cycle }
            }
            return nil
        }

        return visit(start)
    }

    private static func systemSatisfies(_ required: SemanticVersion) -> Bool {
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let running = SemanticVersion(
            current.majorVersion, current.minorVersion, current.patchVersion
        )
        return running >= required
    }

    // MARK: - Activation

    /// Task-local chain of plugins currently activating.
    ///
    /// A task-local rather than a field on the actor because the question being
    /// answered is "did *this* activation lead here?", not "is anything activating
    /// anywhere?" — and actor reentrancy makes those different questions. Without
    /// it, two plugins whose services reference each other would deadlock waiting
    /// on each other's activation task instead of reporting a cycle.
    private enum ActivationChain {
        @TaskLocal static var current: [PluginID] = []
    }

    private func ensureActive(_ id: PluginID) async throws {
        guard let record = records[id] else { throw PluginKitError.unknownPlugin(id) }

        if record.phase == .active { return }

        if let reason = record.unsatisfied {
            throw PluginKitError.unsatisfied(id, reason)
        }
        guard record.phase == .resolved || record.phase == .inactive || record.phase == .failed else {
            throw PluginKitError.runtime(.notActive(id))
        }
        if record.phase == .quarantined {
            throw PluginKitError.runtime(.quarantined(id, crashCount: record.failureCount))
        }

        if ActivationChain.current.contains(id) {
            throw PluginKitError.unsatisfied(
                id, .dependencyCycle(ActivationChain.current + [id])
            )
        }

        if let inFlight = activations[id] {
            try await inFlight.value
            return
        }

        let chain = ActivationChain.current + [id]
        let task = Task { [self] in
            try await ActivationChain.$current.withValue(chain) {
                try await performActivation(id)
            }
        }
        activations[id] = task
        do {
            try await task.value
            activations[id] = nil
        } catch {
            activations[id] = nil
            throw error
        }
    }

    private func performActivation(_ id: PluginID) async throws {
        guard var record = records[id], let resolved = resolvedPlugins[id] else {
            throw PluginKitError.unknownPlugin(id)
        }
        guard let runtime = configuration.runtimes.first(where: { $0.runtimeID == resolved.runtime })
        else {
            throw PluginKitError.runtime(.noRuntimeAvailable(id, requested: resolved.runtime))
        }

        transition(&record, to: .loading)

        let clock = ContinuousClock()
        let began = clock.now

        do {
            let registrar = ContributionRegistrar(manifest: resolved.manifest)
            let context = try await makeContext(for: resolved, registrar: registrar)
            let instance = try await runtime.load(resolved, context: context)

            // Upgrade hook before activation, so a plugin migrates its own state
            // before anything reads it.
            if let previous = try? await storedVersion(for: resolved, storage: context.storage),
               previous != resolved.manifest.version {
                try await callWillUpgrade(instance: instance, from: previous, context: context)
            }

            try await instance.activate()

            let elapsed = clock.now - began
            loaded[id] = LoadedPlugin(instance: instance, context: context, registrar: registrar)
            record.activationDuration = elapsed
            record.failureCount = 0
            transition(&record, to: .active)
            try? await recordVersion(resolved.manifest.version, storage: context.storage)

            await configuration.diagnostics.record(
                DiagnosticEvent(
                    kind: .activated,
                    plugin: id,
                    detail: "Activated via \(resolved.runtime).",
                    duration: elapsed
                )
            )
            broadcast(.registryChanged)
        } catch {
            record.failureCount += 1
            record.lastError = error.localizedDescription
            loaded[id] = nil

            if configuration.crashBudget.quarantines,
               record.failureCount >= configuration.crashBudget.maximumFailures {
                transition(&record, to: .quarantined)
                await configuration.diagnostics.record(
                    DiagnosticEvent(
                        kind: .quarantined,
                        plugin: id,
                        detail: "Disabled after \(record.failureCount) failed attempt(s)."
                    )
                )
            } else {
                transition(&record, to: .failed)
            }

            await configuration.diagnostics.record(
                DiagnosticEvent(kind: .failed, plugin: id, detail: error.localizedDescription)
            )
            broadcast(.failed(id, reason: error.localizedDescription))
            throw error
        }
    }

    /// Calls `willUpgrade` through the instance's own activation path.
    ///
    /// Routed via the runtime rather than by casting to ``Plugin`` because an
    /// out-of-process instance has no `Plugin` object on this side of the boundary.
    /// For now only the in-process runtime can honour it, and doing nothing
    /// elsewhere is correct: a plugin that never ran on this machine has nothing to
    /// migrate.
    private func callWillUpgrade(
        instance: any PluginInstance,
        from previous: SemanticVersion,
        context: any PluginContext
    ) async throws {
        guard let upgradable = instance as? any UpgradeAwareInstance else { return }
        try await upgradable.willUpgrade(from: previous, context: context)
    }

    private func makeContext(
        for resolved: ResolvedPlugin,
        registrar: ContributionRegistrar
    ) async throws -> HostPluginContext {
        let identity = resolved.identity
        let storage = try configuration.storage.makeStorage(for: identity)
        let settings = try configuration.configurationStores.makeStore(
            for: identity, schema: resolved.manifest.configuration
        )
        let events = await configuration.eventBus.scoped(
            to: identity.id,
            publishing: configuration.publishableTopics(for: identity.id),
            subscribing: configuration.subscribableTopics(for: identity.id)
        )

        let host = HostInfo(
            appIdentifier: configuration.appIdentifier,
            appVersion: configuration.appVersion,
            vocabularies: Dictionary(
                configuration.extensionPoints.allEntries.map { ($0.vocabulary, $0.contractVersion) },
                uniquingKeysWith: max
            ),
            isInProcess: resolved.runtime == .inProcess
        )

        return HostPluginContext(
            manifest: resolved.manifest,
            trust: resolved.trust,
            host: host,
            logger: PluginLogger(sink: configuration.log, plugin: identity.id),
            configuration: settings,
            storage: storage,
            events: events,
            broker: configuration.capabilityBroker,
            registrar: registrar,
            serviceResolver: { [self] serviceID, consumer in
                try await resolveService(serviceID, for: consumer)
            },
            lifecycle: { [self] in
                // Nonisolated hop: the protocol's accessor is synchronous, so the
                // registration completes a moment later. Events in that window are
                // missed, which matches the lifecycle stream being advisory.
                AsyncStream { continuation in
                    let id = UUID()
                    Task {
                        await self.addLifecycleObserver(
                            identity.id, id: id, continuation: continuation
                        )
                    }
                    continuation.onTermination = { _ in
                        Task { await self.removeLifecycleObserver(identity.id, id: id) }
                    }
                }
            }
        )
    }

    private func resolveService(_ id: ServiceID, for consumer: PluginID) async throws -> any Sendable {
        guard let provider = records.values.first(where: {
            $0.manifest.declaresService(id) && $0.isAvailable
        }) else {
            throw PluginKitError.misconfigured(
                reason: "No available plugin provides service '\(id)'."
            )
        }

        try await ensureActive(provider.id)
        guard let loadedProvider = loaded[provider.id] else {
            throw PluginKitError.runtime(.notActive(provider.id))
        }
        return try await loadedProvider.instance.service(id)
    }

    private func storedVersion(
        for resolved: ResolvedPlugin,
        storage: any PluginStorage
    ) async throws -> SemanticVersion? {
        guard let data = try await storage.data(forKey: Self.versionKey),
              let raw = String(data: data, encoding: .utf8)
        else { return nil }
        return SemanticVersion(string: raw)
    }

    private func recordVersion(
        _ version: SemanticVersion,
        storage: any PluginStorage
    ) async throws {
        try await storage.setData(Data(version.description.utf8), forKey: Self.versionKey)
    }

    private static let versionKey = "pluginkit.lastVersion"

    // MARK: - Deactivation

    private func deactivate(_ id: PluginID, reason: String) async {
        guard let loadedPlugin = loaded[id] else { return }

        for continuation in lifecycleObservers[id]?.values ?? [:].values {
            continuation.yield(.willDeactivate)
        }

        let instance = loadedPlugin.instance
        let completed = await withDeadline(configuration.deactivationBudget) {
            await instance.deactivate()
        }

        loaded[id] = nil
        await loadedPlugin.registrar.reset()
        for continuation in lifecycleObservers[id]?.values ?? [:].values { continuation.finish() }
        lifecycleObservers[id] = nil

        if var record = records[id] {
            if !completed {
                // In-process, an overrun is abandoned rather than unloaded: the
                // plugin's objects may still be reachable from the host, so
                // reclaiming its code would turn a hang into a crash.
                record.lastError = PluginRuntimeError
                    .deactivationTimedOut(id, budget: configuration.deactivationBudget)
                    .localizedDescription
                configuration.log.log(
                    .error, plugin: id,
                    "Deactivation overran \(configuration.deactivationBudget); "
                        + "abandoning in place."
                )
            }
            if record.phase == .active || record.phase == .loading {
                transition(&record, to: .inactive)
            } else {
                records[id] = record
            }
        }

        await configuration.diagnostics.record(
            DiagnosticEvent(kind: .deactivated, plugin: id, detail: reason)
        )
    }

    /// Dependents before dependencies, so nothing is torn down while something
    /// still using it is alive.
    private func shutdownOrder() -> [PluginID] {
        var order: [PluginID] = []
        var visited = Set<PluginID>()

        func visit(_ id: PluginID) {
            guard visited.insert(id).inserted else { return }
            for (otherID, record) in records
            where record.manifest.dependencies.contains(where: { $0.id == id }) {
                visit(otherID)
            }
            order.append(id)
        }

        for id in loaded.keys { visit(id) }
        return order
    }

    // MARK: - Plumbing

    private func transition(_ record: inout PluginRecord, to phase: PluginPhase) {
        let previous = record.phase
        record.phase = phase
        records[record.id] = record
        guard previous != phase else { return }
        broadcast(.phaseChanged(record.id, from: previous, to: phase))
    }

    private func sort<P: ExtensionPoint>(
        _ handles: [ExtensionHandle<P>],
        arity: ExtensionPointArity
    ) -> [ExtensionHandle<P>] {
        let ordering: ContributionOrdering
        switch arity {
        case .single: ordering = .priority
        case .many(let value): ordering = value
        }

        return handles.sorted { lhs, rhs in
            if ordering == .priority, lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            // Ties break by source precedence then identity, so the order is the
            // same on every launch. Load-order-dependent menus are a real bug that
            // only shows up on someone else's machine.
            let lhsRank = records[lhs.contributor.id].flatMap { sourceRank[$0.source] } ?? .max
            let rhsRank = records[rhs.contributor.id].flatMap { sourceRank[$0.source] } ?? .max
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.contributor.id != rhs.contributor.id {
                return lhs.contributor.id.rawValue < rhs.contributor.id.rawValue
            }
            return lhs.name < rhs.name
        }
    }

    private func addLifecycleObserver(
        _ plugin: PluginID,
        id: UUID,
        continuation: AsyncStream<HostLifecycleEvent>.Continuation
    ) {
        lifecycleObservers[plugin, default: [:]][id] = continuation
    }

    private func removeLifecycleObserver(_ plugin: PluginID, id: UUID) {
        lifecycleObservers[plugin]?[id] = nil
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    private func broadcast(_ event: PluginManagerEvent) {
        for continuation in observers.values { continuation.yield(event) }
    }
}

/// Implemented by runtimes that can deliver ``Plugin/willUpgrade(from:context:)``.
///
/// Not part of ``PluginInstance`` because most runtimes cannot honour it — an
/// out-of-process instance has no `Plugin` object on the host's side — and a
/// protocol requirement every conformer stubs out is a requirement that teaches
/// nobody anything.
public protocol UpgradeAwareInstance: PluginInstance {
    func willUpgrade(from previousVersion: SemanticVersion, context: any PluginContext) async throws
}
