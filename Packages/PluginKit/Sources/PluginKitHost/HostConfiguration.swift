import Foundation
@_exported import PluginKitCore

/// Everything the host runtime needs, assembled in one place.
///
/// This is PluginKit's composition root and its entire dependency-injection
/// surface. Every seam — sources, runtimes, trust, capabilities, consent, storage,
/// configuration, logging — arrives here, and nothing inside ``PluginManager``
/// reaches for a global. A test builds this struct with fakes and gets a fully
/// deterministic manager; production builds it with real implementations. There is
/// no third path, which is what keeps the two honest.
public struct HostConfiguration: Sendable {
    /// The host app's bundle identifier. Reported to plugins.
    public var appIdentifier: String

    /// Used for the on-disk directory names. Defaults to the last component of
    /// ``appIdentifier``.
    public var appName: String

    public var appVersion: SemanticVersion

    /// The PluginKit generations this host can load. A plugin declaring an
    /// `sdkVersion` outside this is rejected at discovery, before loading.
    public var supportedSDKVersions: VersionRange

    /// The host's published vocabulary.
    public var extensionPoints: ExtensionPointCatalog

    /// Vocabulary versions, for the compatibility check and for the emitted
    /// catalog. Any vocabulary omitted here is inferred from its extension points.
    public var vocabularies: [VocabularyDescriptor]

    /// Where to look, in **descending precedence**. On an identity collision the
    /// earlier source wins and the loser is recorded as shadowed — so a managed
    /// deployment should come first, and a user drop-folder last.
    public var sources: [any PluginSource]

    /// Runtime backends this host ships. A host that only links
    /// `PluginKitInProcess` has exactly one, and low-trust plugins will be
    /// unsatisfied unless ``DefaultRuntimeSelector/allowsUnisolatedFallback`` is on.
    public var runtimes: [any PluginRuntime]

    public var runtimeSelector: any RuntimeSelector
    public var trustPolicy: any TrustPolicy

    public var capabilities: CapabilityRegistry
    public var capabilityPolicy: CapabilityPolicy
    public var consent: any ConsentStore

    public var configurationStores: any ConfigurationStoreFactory
    public var storage: any PluginStorageFactory
    public var enablement: any PluginEnablementStore

    public var eventBus: BrokeredEventBus
    /// Topics a plugin may publish to, by plugin. `nil` entry means the default.
    public var publishableTopics: [PluginID: [String]]
    /// Topics a plugin may observe.
    public var subscribableTopics: [PluginID: [String]]
    /// Applied to any plugin without a specific entry. Empty publish list by
    /// default: a plugin should not be able to broadcast to the whole app just
    /// because nobody configured topics.
    public var defaultPublishableTopics: [String]
    public var defaultSubscribableTopics: [String]

    public var log: any PluginLogging
    public var diagnostics: PluginDiagnostics

    /// How long `deactivate()` gets before the host stops waiting.
    public var deactivationBudget: Duration

    public var crashBudget: CrashBudget

    /// Load nothing. The escape hatch for a user whose app will not start —
    /// non-negotiable in any extensible app, and cheaper to build in now than to
    /// retrofit during an incident.
    public var safeMode: Bool

    public init(
        appIdentifier: String,
        appName: String? = nil,
        appVersion: SemanticVersion,
        supportedSDKVersions: VersionRange? = nil,
        extensionPoints: ExtensionPointCatalog = ExtensionPointCatalog(),
        vocabularies: [VocabularyDescriptor] = [],
        sources: [any PluginSource] = [],
        runtimes: [any PluginRuntime] = [],
        runtimeSelector: any RuntimeSelector = DefaultRuntimeSelector(),
        trustPolicy: any TrustPolicy = LocationTrustPolicy(),
        capabilities: CapabilityRegistry = CapabilityRegistry(),
        capabilityPolicy: CapabilityPolicy = .denyAll,
        consent: any ConsentStore = DenyingConsentStore(),
        configurationStores: any ConfigurationStoreFactory = InMemoryConfigurationStoreFactory(),
        storage: any PluginStorageFactory = InMemoryStorageFactory(),
        enablement: any PluginEnablementStore = InMemoryEnablementStore(),
        eventBus: BrokeredEventBus? = nil,
        publishableTopics: [PluginID: [String]] = [:],
        subscribableTopics: [PluginID: [String]] = [:],
        defaultPublishableTopics: [String] = [],
        defaultSubscribableTopics: [String] = [],
        log: any PluginLogging = SilentPluginLog(),
        diagnostics: PluginDiagnostics = PluginDiagnostics(),
        deactivationBudget: Duration = .seconds(2),
        crashBudget: CrashBudget = .default,
        safeMode: Bool = false
    ) {
        self.appIdentifier = appIdentifier
        self.appName = appName ?? appIdentifier.split(separator: ".").last.map(String.init)
            ?? appIdentifier
        self.appVersion = appVersion
        self.supportedSDKVersions = supportedSDKVersions
            ?? .series(of: PluginKitVersion.current)
        self.extensionPoints = extensionPoints
        self.vocabularies = vocabularies
        self.sources = sources
        self.runtimes = runtimes
        self.runtimeSelector = runtimeSelector
        self.trustPolicy = trustPolicy
        self.capabilities = capabilities
        self.capabilityPolicy = capabilityPolicy
        self.consent = consent
        self.configurationStores = configurationStores
        self.storage = storage
        self.enablement = enablement
        self.eventBus = eventBus ?? BrokeredEventBus(log: log)
        self.publishableTopics = publishableTopics
        self.subscribableTopics = subscribableTopics
        self.defaultPublishableTopics = defaultPublishableTopics
        self.defaultSubscribableTopics = defaultSubscribableTopics
        self.log = log
        self.diagnostics = diagnostics
        self.deactivationBudget = deactivationBudget
        self.crashBudget = crashBudget
        self.safeMode = safeMode
    }

    /// The broker assembled from ``capabilities``, ``capabilityPolicy``, and
    /// ``consent``.
    ///
    /// Computed rather than stored so that mutating any of the three after
    /// construction cannot leave a stale broker behind — a footgun worth
    /// eliminating, since a host naturally configures these in stages.
    public var capabilityBroker: any CapabilityBroker {
        PolicyCapabilityBroker(
            registry: capabilities,
            policy: capabilityPolicy,
            consent: consent
        )
    }

    /// Topics a plugin may publish to.
    public func publishableTopics(for plugin: PluginID) -> [String] {
        publishableTopics[plugin] ?? defaultPublishableTopics
    }

    public func subscribableTopics(for plugin: PluginID) -> [String] {
        subscribableTopics[plugin] ?? defaultSubscribableTopics
    }

    /// The vocabulary version this host is on, if declared.
    public func vocabularyVersion(_ id: VocabularyID) -> SemanticVersion? {
        vocabularies.first { $0.id == id }?.version
            ?? extensionPoints.allEntries
                .filter { $0.vocabulary == id }
                .map(\.contractVersion)
                .max()
    }

    /// What this host accepts a plugin to have been built against.
    public func vocabularyAccepts(_ id: VocabularyID) -> VersionRange? {
        if let declared = vocabularies.first(where: { $0.id == id }) { return declared.accepts }
        guard let version = vocabularyVersion(id) else { return nil }
        return .series(of: version)
    }
}

// MARK: - Presets

extension HostConfiguration {
    /// A batteries-included configuration for a normal macOS app.
    ///
    /// Built-in, user, machine-wide, and development sources; file-backed storage
    /// and settings; ``UserDefaultsEnablementStore``; prompt-for-sensitive
    /// capability policy. Register extension points and capabilities in
    /// `configure`, then replace any individual seam afterwards.
    ///
    /// ```swift
    /// let manager = PluginManager(configuration: .standard(
    ///     appIdentifier: "com.acme.editor", appVersion: "3.2.0"
    /// ) { configuration in
    ///     configuration.extensionPoints.register(CommandPoint.self)
    ///     configuration.capabilities.register((any FileReading).self) { scope, _ in
    ///         ScopedFileReader(roots: scope.roots)
    ///     }
    /// })
    /// ```
    ///
    /// - Note: No runtime is included. A host adds one explicitly — linking
    ///   `PluginKitInProcess` and passing `InProcessPluginRuntime` is a decision
    ///   about isolation, and defaulting it would hide the most consequential
    ///   choice in the framework behind a convenience initialiser.
    public static func standard(
        appIdentifier: String,
        appVersion: SemanticVersion,
        appName: String? = nil,
        bundle: Bundle = .main,
        consent: any ConsentStore = DenyingConsentStore(),
        configure: (inout HostConfiguration) -> Void = { _ in }
    ) -> HostConfiguration {
        let resolvedName = appName ?? appIdentifier.split(separator: ".").last.map(String.init)
            ?? appIdentifier

        var sources: [any PluginSource] = []
        // Descending precedence: managed deployments outrank the app's own
        // bundled plugins, which outrank whatever a user dropped in.
        sources.append(DirectoryPluginSource.machine(appName: resolvedName))
        if let builtIn = DirectoryPluginSource.builtIn(bundle: bundle) { sources.append(builtIn) }
        sources.append(DirectoryPluginSource.user(appName: resolvedName))
        if let development = DirectoryPluginSource.development() { sources.append(development) }

        let dataRoot = PluginBundleLayout.pluginDataDirectory(appName: resolvedName)

        var configuration = HostConfiguration(
            appIdentifier: appIdentifier,
            appName: resolvedName,
            appVersion: appVersion,
            sources: sources,
            capabilityPolicy: .promptForSensitive,
            consent: consent,
            configurationStores: FileConfigurationStoreFactory(root: dataRoot),
            storage: FileSystemStorageFactory(root: dataRoot),
            enablement: UserDefaultsEnablementStore(),
            // Safe mode on a held Shift at launch is the convention users already
            // know from other extensible Mac apps.
            safeMode: ProcessInfo.processInfo.environment["PLUGINKIT_SAFE_MODE"] == "1"
        )
        configure(&configuration)
        return configuration
    }

    /// A configuration with nothing real in it, for tests and previews.
    public static func inMemory(
        appIdentifier: String = "com.example.host",
        appVersion: SemanticVersion = "1.0.0",
        configure: (inout HostConfiguration) -> Void = { _ in }
    ) -> HostConfiguration {
        var configuration = HostConfiguration(
            appIdentifier: appIdentifier,
            appVersion: appVersion,
            capabilityPolicy: .allowAll,
            consent: AllowingConsentStore(),
            crashBudget: .lenient
        )
        configure(&configuration)
        return configuration
    }
}
