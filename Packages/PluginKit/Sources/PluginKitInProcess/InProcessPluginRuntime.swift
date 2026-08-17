import Foundation
import PluginKitCore
import PluginKitHost

/// Runs plugins in the host's own address space.
///
/// Two supply modes, one lifecycle:
///
/// - **Registered** — the plugin type is compiled into the host and supplied by a
///   factory. How first-party plugins ship, and how tests work.
/// - **Bundle** — a `.plugin` on disk, loaded through `Bundle.principalClass`.
///
/// Both get identical treatment: the same manifest authority, the same capability
/// brokering, the same phases. "First-party" must not become a synonym for
/// "unaudited", so the only thing that differs is where the code came from.
///
/// - Important: This runtime provides **no isolation**. A plugin loaded here can
///   call any API the host can, ignore the capability broker entirely, and take the
///   process down with it. That is not a flaw to be fixed — it is the trade being
///   made, and it is why ``DefaultRuntimeSelector`` refuses to put low-trust
///   plugins here unless a host explicitly opts in.
public struct InProcessPluginRuntime: PluginRuntime {
    public let runtimeID: RuntimeID = .inProcess

    /// Factories for plugins compiled into the host.
    private let factories: [PluginID: @Sendable () -> any Plugin]

    /// Whether to attempt `Bundle` loading for plugins found on disk.
    ///
    /// Defaults to `true`, but note that a host with the hardened runtime enabled
    /// can only load code signed by its own team unless it carries
    /// `com.apple.security.cs.disable-library-validation` — an entitlement that is
    /// not realistically approvable for the App Store. A host in that position
    /// should set this to `false` and ship registered plugins only.
    private let loadsBundles: Bool

    public init(
        factories: [PluginID: @Sendable () -> any Plugin] = [:],
        loadsBundles: Bool = true
    ) {
        self.factories = factories
        self.loadsBundles = loadsBundles
    }

    /// Convenience for the common first-party case.
    ///
    /// ```swift
    /// InProcessPluginRuntime.registering([
    ///     "com.acme.editor.markdown": { MarkdownPlugin() },
    ///     "com.acme.editor.git": { GitPlugin() },
    /// ])
    /// ```
    public static func registering(
        _ factories: [PluginID: @Sendable () -> any Plugin],
        loadsBundles: Bool = false
    ) -> InProcessPluginRuntime {
        InProcessPluginRuntime(factories: factories, loadsBundles: loadsBundles)
    }

    public func canHost(_ manifest: PluginManifest, at location: PluginLocation) -> Bool {
        switch location {
        case .registered:
            return factories[manifest.id] != nil
        case .bundle:
            guard loadsBundles else { return false }
            if case .inProcess = manifest.runtime { return true }
            // A manifest asking for isolation is not hosted here even though it
            // technically could be: honouring the request when the host has an
            // isolating runtime available is the point of asking.
            return false
        }
    }

    public func load(
        _ plugin: ResolvedPlugin,
        context: any PluginContext
    ) async throws -> any PluginInstance {
        let instance: any Plugin

        switch plugin.location {
        case .registered:
            guard let factory = factories[plugin.manifest.id] else {
                throw PluginKitError.runtime(
                    .instantiationFailed(
                        plugin.manifest.id,
                        reason: "No registered factory. Add it to InProcessPluginRuntime."
                    )
                )
            }
            instance = factory()

        case .bundle(let url):
            instance = try Self.loadFromBundle(at: url, manifest: plugin.manifest)
        }

        return InProcessPluginInstance(
            identity: plugin.identity,
            plugin: instance,
            context: context
        )
    }

    /// Loads a plugin bundle and instantiates its principal class.
    ///
    /// The contract-version handshake happens **before** `makePlugin()`. A plugin
    /// linked against an incompatible contract can fail in ways indistinguishable
    /// from memory corruption once its code is running, so the check has to happen
    /// while backing out is still clean.
    private static func loadFromBundle(
        at url: URL,
        manifest: PluginManifest
    ) throws -> any Plugin {
        guard let bundle = Bundle(url: url) else {
            throw PluginKitError.runtime(
                .bundleLoadFailed(url, reason: "Not a loadable bundle.")
            )
        }

        if !bundle.isLoaded {
            do {
                try bundle.loadAndReturnError()
            } catch {
                throw PluginKitError.runtime(
                    .bundleLoadFailed(url, reason: error.localizedDescription)
                )
            }
        }

        guard let principal = bundle.principalClass else {
            throw PluginKitError.runtime(
                .entryPointNotFound(manifest.id, symbol: "NSPrincipalClass")
            )
        }

        guard let entryPoint = principal as? any PluginEntryPoint.Type else {
            throw PluginKitError.runtime(
                .instantiationFailed(
                    manifest.id,
                    reason: "\(principal) does not conform to PluginEntryPoint. "
                        + "Subclass PluginPrincipal from PluginKitSDK."
                )
            )
        }

        try verifyContracts(declared: entryPoint.declaredContracts, against: manifest)
        return entryPoint.makePlugin()
    }

    /// Cross-checks the binary's linked contract versions against the manifest.
    ///
    /// The manifest is data an author can edit without recompiling; the binary's
    /// answer is not. When they disagree, the manifest is the one that lied, and
    /// loading anyway would mean trusting the document that is easier to forge.
    private static func verifyContracts(
        declared: [ContractDependency],
        against manifest: PluginManifest
    ) throws {
        for contract in declared {
            let vocabulary = contract.vocabulary
            let linked = contract.builtAgainst
            guard let stated = manifest.contracts.first(where: { $0.vocabulary == vocabulary })
            else {
                throw PluginKitError.manifest(
                    .invalid(
                        reason: "The binary links '\(vocabulary)' \(linked), which the manifest "
                            + "does not declare."
                    )
                )
            }
            guard stated.builtAgainst == linked else {
                throw PluginKitError.manifest(
                    .invalid(
                        reason: "The manifest says '\(vocabulary)' \(stated.builtAgainst) but the "
                            + "binary links \(linked)."
                    )
                )
            }
        }
    }
}

/// A plugin living in the host's address space.
///
/// Thin by design. All it does is call through to the ``Plugin``, normalise the
/// errors, and read registrations back out of the context. Anything more would be
/// logic the out-of-process runtime would then have to reimplement identically.
final class InProcessPluginInstance: UpgradeAwareInstance {
    let identity: PluginIdentity
    private let plugin: any Plugin
    private let context: any PluginContext

    init(identity: PluginIdentity, plugin: any Plugin, context: any PluginContext) {
        self.identity = identity
        self.plugin = plugin
        self.context = context
    }

    func activate() async throws {
        do {
            try await plugin.activate(context)
        } catch let error as CapabilityError {
            // Re-wrapped rather than passed through so a host can switch on one
            // error type. A plugin author's `throw` should not decide the shape of
            // the host's error handling.
            throw PluginKitError.capability(error)
        } catch let error as ExtensionPointError {
            throw PluginKitError.extensionPoint(error)
        } catch let error as PluginKitError {
            throw error
        } catch {
            throw PluginKitError.runtime(
                .activationFailed(identity.id, reason: error.localizedDescription)
            )
        }
    }

    func deactivate() async {
        await plugin.deactivate()
    }

    func willUpgrade(
        from previousVersion: SemanticVersion,
        context: any PluginContext
    ) async throws {
        try await plugin.willUpgrade(from: previousVersion, context: context)
    }

    func contract(for point: ExtensionPointID, contribution name: String) async throws -> any Sendable {
        try await resolver().resolveContribution(point: point, name: name)
    }

    func service(_ id: ServiceID) async throws -> any Sendable {
        try await resolver().resolveProvidedService(id)
    }

    func health() async -> PluginHealth {
        await plugin.healthCheck()
    }

    private func resolver() throws -> any ContributionResolving {
        guard let resolving = context as? any ContributionResolving else {
            throw PluginKitError.misconfigured(
                reason: "The host context does not support contribution resolution."
            )
        }
        return resolving
    }
}
