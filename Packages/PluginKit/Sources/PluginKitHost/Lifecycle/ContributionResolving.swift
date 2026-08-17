import Foundation
import PluginKitCore

/// Reads back what a plugin registered during activation.
///
/// A runtime backend needs two lookups — a contribution's contract and a published
/// service — but has no business reaching into the host's bookkeeping for them.
/// This is that narrow window, conformed to by ``HostPluginContext``.
///
/// Existing as a protocol rather than a concrete type is what lets a backend live
/// in its own target: `PluginKitInProcess` depends on `PluginKitHost` for this
/// seam and nothing more, so adding a runtime never means touching the manager.
public protocol ContributionResolving: Sendable {
    /// Produces the contract for one registered contribution. Memoised per
    /// contribution, so repeated calls return the same instance.
    func resolveContribution(point: ExtensionPointID, name: String) async throws -> any Sendable

    /// Produces a service the plugin published.
    func resolveProvidedService(_ id: ServiceID) async throws -> any Sendable
}

extension HostPluginContext: ContributionResolving {
    public func resolveContribution(point: ExtensionPointID, name: String) async throws -> any Sendable {
        try await registrar.contract(point: point, name: name)
    }

    public func resolveProvidedService(_ id: ServiceID) async throws -> any Sendable {
        try await registrar.service(id)
    }

    /// What the plugin actually registered and asked for, for drift reporting.
    ///
    /// Exposed on the host side because only the host observes the truth: the
    /// manifest is a claim, and this is what the code did.
    public func activationRecord() async -> PluginActivationRecord {
        PluginActivationRecord(
            contributions: await registrar.registeredContributions.map {
                ContributionKey(plugin: identity.id, extensionPoint: $0.point, name: $0.name)
            },
            services: await registrar.providedServices,
            capabilities: await registrar.requestedCapabilities
        )
    }
}

/// What a plugin did during activation, as observed by the host.
public struct PluginActivationRecord: Sendable, Hashable {
    public let contributions: [ContributionKey]
    public let services: [ServiceID]
    public let capabilities: Set<CapabilityID>

    public init(
        contributions: [ContributionKey],
        services: [ServiceID],
        capabilities: Set<CapabilityID>
    ) {
        self.contributions = contributions
        self.services = services
        self.capabilities = capabilities
    }
}
