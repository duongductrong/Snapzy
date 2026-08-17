import Foundation
import PluginKitCore

/// Holds what a plugin registered during activation, and memoises the contracts.
///
/// Shared between the context the plugin writes into and the instance the host
/// reads from — one object, so there is no window where the two disagree.
///
/// Memoisation is a semantic guarantee, not an optimisation: resolving the same
/// contribution twice must yield the *same* contract instance, or a plugin holding
/// per-contribution state would silently get a fresh copy on every menu click.
actor ContributionRegistrar {
    private struct Registration {
        let factory: @Sendable () async throws -> any Sendable
        var resolved: (any Sendable)?
    }

    private let manifest: PluginManifest
    private var registrations: [String: Registration] = [:]
    private var services: [ServiceID: Registration] = [:]

    /// Capabilities the plugin actually asked for, for drift detection.
    private(set) var requestedCapabilities: Set<CapabilityID> = []

    init(manifest: PluginManifest) {
        self.manifest = manifest
    }

    /// Records a contribution factory.
    ///
    /// - Throws: ``ExtensionPointError/contributionNotFound(_:)`` when the manifest
    ///   does not declare `(point, name)`. The manifest is authoritative: a plugin
    ///   that could register something it never disclosed would be able to
    ///   contribute past the list a user approved, so this is a refusal rather
    ///   than a warning.
    func register(
        point: ExtensionPointID,
        name: String,
        factory: @escaping @Sendable () async throws -> any Sendable
    ) throws {
        guard manifest.contribution(to: point, named: name) != nil else {
            throw ExtensionPointError.contributionNotFound(
                ContributionKey(plugin: manifest.id, extensionPoint: point, name: name)
            )
        }
        registrations[Self.key(point, name)] = Registration(factory: factory, resolved: nil)
    }

    func provide(
        service: ServiceID,
        factory: @escaping @Sendable () async throws -> any Sendable
    ) throws {
        guard manifest.declaresService(service) else {
            throw PluginKitError.misconfigured(
                reason: "'\(manifest.id)' published service '\(service)' without declaring it."
            )
        }
        services[service] = Registration(factory: factory, resolved: nil)
    }

    /// Resolves a contribution, calling its factory at most once.
    func contract(point: ExtensionPointID, name: String) async throws -> any Sendable {
        let key = Self.key(point, name)
        guard var registration = registrations[key] else {
            throw ExtensionPointError.contributionNotFound(
                ContributionKey(plugin: manifest.id, extensionPoint: point, name: name)
            )
        }
        if let resolved = registration.resolved { return resolved }

        let value = try await registration.factory()
        // Re-read: the factory suspended, so another caller may have resolved the
        // same contribution meanwhile. Whoever landed first wins, and both callers
        // get the same instance — which is the guarantee, not an optimisation.
        if let raced = registrations[key]?.resolved { return raced }
        registration.resolved = value
        registrations[key] = registration
        return value
    }

    func service(_ id: ServiceID) async throws -> any Sendable {
        guard var registration = services[id] else {
            throw PluginKitError.misconfigured(
                reason: "'\(manifest.id)' does not provide service '\(id)'."
            )
        }
        if let resolved = registration.resolved { return resolved }
        let value = try await registration.factory()
        if let raced = services[id]?.resolved { return raced }
        registration.resolved = value
        services[id] = registration
        return value
    }

    func noteCapabilityRequest(_ id: CapabilityID) {
        requestedCapabilities.insert(id)
    }

    /// `(point, name)` pairs the plugin registered. Used for drift reporting.
    var registeredContributions: [(point: ExtensionPointID, name: String)] {
        registrations.keys.compactMap { key in
            let parts = key.split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return (ExtensionPointID(String(parts[0])), String(parts[1]))
        }
    }

    var providedServices: [ServiceID] { Array(services.keys) }

    /// Drops resolved contracts so a re-activation starts clean.
    func reset() {
        registrations.removeAll()
        services.removeAll()
        requestedCapabilities.removeAll()
    }

    /// Separator is a control character so it cannot occur in a reverse-DNS point
    /// ID or an author-chosen contribution name.
    private static func key(_ point: ExtensionPointID, _ name: String) -> String {
        "\(point.rawValue)\u{1}\(name)"
    }
}
