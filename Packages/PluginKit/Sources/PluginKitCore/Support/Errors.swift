import Foundation

// Errors are structured rather than free-text throughout, for one reason: a
// plugin failure has three distinct audiences with three different needs. The
// *user* needs one sentence and a next step. The *host developer* needs to know
// which subsystem refused and why. The *plugin author* — who cannot attach a
// debugger to a shipped app — needs enough detail to fix the manifest or the
// code from a log line alone. A `String` serves none of them well.

/// Why a manifest could not be read or trusted.
public enum PluginManifestError: Error, Hashable, Sendable {
    case fileNotFound(URL)
    case unreadable(reason: String)
    case malformedValue(reason: String)
    case decodingFailed(reason: String)
    /// The manifest parsed, but says something structurally impossible —
    /// duplicate contribution names, an empty identifier, a plugin depending on
    /// itself. Caught here so the rest of the host can assume well-formedness.
    case invalid(reason: String)
    /// The plugin was built against a PluginKit generation this host cannot host.
    case incompatibleSDK(required: VersionRange, hostProvides: SemanticVersion)
}

/// Why a candidate was refused before any code was loaded.
public enum PluginTrustError: Error, Hashable, Sendable {
    case unsigned
    case signatureInvalid(status: Int)
    case untrustedTeam(found: String?, expected: [String])
    case quarantined
    /// The bundle carries its own copy of a contract framework the host also
    /// provides. Two copies of the same types in one address space make casts
    /// across the seam fail in ways that are near-impossible to diagnose later,
    /// so this is refused up front rather than debugged in the field.
    case duplicateContractFramework(name: String)
    case policyRefused(reason: String)
}

/// Why an extension point interaction failed.
public enum ExtensionPointError: Error, Hashable, Sendable {
    /// The plugin contributes to a point this host never registered. Usually a
    /// version skew or a typo in the manifest.
    case unknownExtensionPoint(ExtensionPointID)
    /// The contract version the plugin was built against is outside the range
    /// this host accepts.
    case contractVersionUnsupported(
        point: ExtensionPointID,
        pluginBuiltAgainst: SemanticVersion,
        hostAccepts: VersionRange
    )
    /// Declarative metadata did not match the point's metadata type.
    case metadataDecodingFailed(point: ExtensionPointID, reason: String)
    /// The point is in-process only, but the plugin's trust level forbids
    /// in-process hosting. Reported at validation, before loading.
    case localityViolation(point: ExtensionPointID, reason: String)
    /// The factory produced something that is not the point's contract type.
    /// A programmer error on the plugin side, surfaced with both type names
    /// because the author cannot see the host's stack.
    case contractTypeMismatch(point: ExtensionPointID, expected: String, found: String)
    /// A `.single`-arity point already has a contribution from another plugin.
    case arityExceeded(point: ExtensionPointID, incumbent: PluginID)
    case contributionNotFound(ContributionKey)
}

/// Why a capability was not vended.
public enum CapabilityError: Error, Hashable, Sendable {
    /// The plugin asked for something its manifest never declared. The manifest
    /// is authoritative, so this is refused rather than prompted for — a plugin
    /// must not be able to reach past its own disclosure.
    case undeclared(CapabilityID)
    /// No host service is registered under this identifier.
    case unavailable(CapabilityID)
    case deniedByPolicy(CapabilityID, reason: String)
    case deniedByManagedPolicy(CapabilityID, reason: String)
    case deniedByUser(CapabilityID)
    /// The requested scope has no overlap with what policy permits, so there is
    /// nothing left to grant.
    case scopeEmpty(CapabilityID)
    case scopeMalformed(CapabilityID, reason: String)
}

/// Why a runtime could not load, activate, or reach a plugin.
public enum PluginRuntimeError: Error, Hashable, Sendable {
    case noRuntimeAvailable(PluginID, requested: RuntimeID?)
    case unsupportedLocation(PluginID)
    case bundleLoadFailed(URL, reason: String)
    /// The bundle loaded but exposes no usable entry point.
    case entryPointNotFound(PluginID, symbol: String)
    case instantiationFailed(PluginID, reason: String)
    case activationFailed(PluginID, reason: String)
    /// `deactivate()` overran its budget. The host escalates: an out-of-process
    /// plugin is killed, an in-process one is abandoned in place — never
    /// unloaded, because its objects may still be live.
    case deactivationTimedOut(PluginID, budget: Duration)
    case notActive(PluginID)
    case crashed(PluginID)
    /// Auto-disabled after repeated crashes, so one bad plugin cannot make the
    /// app unusable.
    case quarantined(PluginID, crashCount: Int)
}

/// Why a plugin that parsed and was trusted still cannot run.
///
/// Distinct from an error because it is a *steady state*, not an event: the
/// plugin stays listed, stays visible in a manager UI, and carries this reason
/// until the situation changes. Nothing here is ever silent.
public enum UnsatisfiedReason: Hashable, Sendable {
    case missingDependency(PluginID)
    case dependencyVersionMismatch(PluginID, required: VersionRange, found: SemanticVersion)
    case dependencyCycle([PluginID])
    case requiredCapabilityDenied(CapabilityID, reason: String)
    case extensionPoint(ExtensionPointError)
    case vocabularyUnsupported(VocabularyID, required: VersionRange, hostProvides: SemanticVersion?)
    case noRuntimeAvailable(requested: RuntimeID?, trust: String)
    case disabledByUser
    case disabledByPolicy(reason: String)
}

/// The error surface presented by the host facade.
public enum PluginKitError: Error, Sendable {
    case manifest(PluginManifestError)
    case trust(PluginTrustError)
    case extensionPoint(ExtensionPointError)
    case capability(CapabilityError)
    case runtime(PluginRuntimeError)
    case unknownPlugin(PluginID)
    case unsatisfied(PluginID, UnsatisfiedReason)
    case misconfigured(reason: String)
}

// MARK: - Localised descriptions

extension PluginManifestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "No plugin manifest at \(url.path)."
        case .unreadable(let reason):
            return "Could not read the plugin manifest: \(reason)"
        case .malformedValue(let reason):
            return "Malformed value in the plugin manifest: \(reason)"
        case .decodingFailed(let reason):
            return "Could not decode the plugin manifest: \(reason)"
        case .invalid(let reason):
            return "The plugin manifest is not valid: \(reason)"
        case .incompatibleSDK(let required, let hostProvides):
            return "The plugin needs PluginKit \(required); this host provides \(hostProvides)."
        }
    }
}

extension PluginTrustError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsigned:
            return "The plugin is not code signed."
        case .signatureInvalid(let status):
            return "The plugin's code signature is not valid (OSStatus \(status))."
        case .untrustedTeam(let found, let expected):
            let foundText = found.map { "'\($0)'" } ?? "an unknown team"
            return "The plugin is signed by \(foundText), not by "
                + expected.map { "'\($0)'" }.joined(separator: " or ") + "."
        case .quarantined:
            return "The plugin is quarantined. Remove the quarantine attribute to load it."
        case .duplicateContractFramework(let name):
            return "The plugin embeds its own copy of '\(name)', which the host already provides."
        case .policyRefused(let reason):
            return reason
        }
    }
}

extension ExtensionPointError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknownExtensionPoint(let id):
            return "This host has no extension point '\(id)'."
        case .contractVersionUnsupported(let point, let built, let accepts):
            return "The plugin was built against '\(point)' contract \(built); "
                + "this host accepts \(accepts)."
        case .metadataDecodingFailed(let point, let reason):
            return "Contribution metadata for '\(point)' is not valid: \(reason)"
        case .localityViolation(let point, let reason):
            return "'\(point)' can only be hosted in-process: \(reason)"
        case .contractTypeMismatch(let point, let expected, let found):
            return "The contribution to '\(point)' produced \(found), but the contract is \(expected)."
        case .arityExceeded(let point, let incumbent):
            return "'\(point)' accepts one contribution, already provided by '\(incumbent)'."
        case .contributionNotFound(let key):
            return "No contribution '\(key)'."
        }
    }
}

extension CapabilityError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .undeclared(let id):
            return "The plugin requested '\(id)' without declaring it in its manifest."
        case .unavailable(let id):
            return "This host does not provide the capability '\(id)'."
        case .deniedByPolicy(let id, let reason):
            return "'\(id)' was denied: \(reason)"
        case .deniedByManagedPolicy(let id, let reason):
            return "'\(id)' is blocked by a managed policy: \(reason)"
        case .deniedByUser(let id):
            return "You declined '\(id)' for this plugin."
        case .scopeEmpty(let id):
            return "Nothing remains of the requested '\(id)' scope after applying policy limits."
        case .scopeMalformed(let id, let reason):
            return "The requested '\(id)' scope is not valid: \(reason)"
        }
    }
}

extension PluginRuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noRuntimeAvailable(let id, let requested):
            let requestedText = requested.map { " '\($0)'" } ?? ""
            return "No runtime\(requestedText) is available to host '\(id)'."
        case .unsupportedLocation(let id):
            return "No registered runtime can load '\(id)' from where it was found."
        case .bundleLoadFailed(let url, let reason):
            return "Could not load \(url.lastPathComponent): \(reason)"
        case .entryPointNotFound(let id, let symbol):
            return "'\(id)' does not expose the entry point '\(symbol)'."
        case .instantiationFailed(let id, let reason):
            return "Could not create '\(id)': \(reason)"
        case .activationFailed(let id, let reason):
            return "'\(id)' failed to activate: \(reason)"
        case .deactivationTimedOut(let id, let budget):
            return "'\(id)' did not deactivate within \(budget)."
        case .notActive(let id):
            return "'\(id)' is not active."
        case .crashed(let id):
            return "'\(id)' stopped unexpectedly."
        case .quarantined(let id, let crashCount):
            return "'\(id)' was disabled after stopping unexpectedly \(crashCount) time(s)."
        }
    }
}

extension UnsatisfiedReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingDependency(let id):
            return "Requires '\(id)', which is not installed."
        case .dependencyVersionMismatch(let id, let required, let found):
            return "Requires '\(id)' \(required), but \(found) is installed."
        case .dependencyCycle(let cycle):
            return "Circular dependency: " + cycle.map(\.rawValue).joined(separator: " → ")
        case .requiredCapabilityDenied(let id, let reason):
            return "Needs '\(id)', which was denied: \(reason)"
        case .extensionPoint(let error):
            return error.errorDescription ?? "Extension point mismatch."
        case .vocabularyUnsupported(let vocabulary, let required, let hostProvides):
            let provided = hostProvides.map(\.description) ?? "none"
            return "Built against '\(vocabulary)' \(required); this host provides \(provided)."
        case .noRuntimeAvailable(let requested, let trust):
            let requestedText = requested.map { "'\($0)'" } ?? "any runtime"
            return "No way to run this plugin: \(requestedText) is unavailable at trust level \(trust)."
        case .disabledByUser:
            return "Turned off."
        case .disabledByPolicy(let reason):
            return "Blocked by policy: \(reason)"
        }
    }
}

extension PluginKitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .manifest(let error): return error.errorDescription
        case .trust(let error): return error.errorDescription
        case .extensionPoint(let error): return error.errorDescription
        case .capability(let error): return error.errorDescription
        case .runtime(let error): return error.errorDescription
        case .unknownPlugin(let id): return "No plugin with identifier '\(id)'."
        case .unsatisfied(let id, let reason): return "'\(id)' cannot run. \(reason)"
        case .misconfigured(let reason): return "PluginKit is misconfigured: \(reason)"
        }
    }
}
