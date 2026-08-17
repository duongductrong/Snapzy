import Foundation
import PluginKitCore
#if canImport(Security)
import Security
#endif

/// Decides how much a discovered plugin is trusted, before anything is loaded.
///
/// A protocol because the right answer is genuinely different per app: a
/// first-party-only host pins its own team ID, an open host accepts any notarised
/// developer, an enterprise host defers to a managed allowlist. None of those is
/// a sensible default for the others.
public protocol TrustPolicy: Sendable {
    func evaluate(_ candidate: DiscoveredPlugin) async -> TrustDecision
}

public enum TrustDecision: Sendable {
    case trusted(TrustLevel)
    /// Never loadable. Distinguished from a low trust level because "we will not
    /// run this" and "we will only run this in a sandbox" need different UI and
    /// different logging.
    case blocked(reason: PluginTrustError)
}

/// How much authority a plugin may be given.
///
/// The ordering is load-bearing: ``RuntimeSelector`` compares against it to decide
/// whether in-process hosting is permissible.
public enum TrustLevel: Int, Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    /// Third-party, and only acceptable under isolation. In-process hosting is
    /// refused, which in practice means a contribution to a
    /// ``LocalExtensionPoint`` makes such a plugin unsatisfiable.
    case sandboxedOnly = 0
    /// Signed by a known developer. May run in-process if the host allows it.
    case verifiedDeveloper = 1
    /// Same signing identity as the host, or compiled into it. Full authority —
    /// which is exactly what it has anyway once it shares the address space.
    case firstParty = 2

    public static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .sandboxedOnly: return "sandboxedOnly"
        case .verifiedDeveloper: return "verifiedDeveloper"
        case .firstParty: return "firstParty"
        }
    }
}

/// Trusts a plugin according to where it was found, without inspecting signatures.
///
/// The default, and correct for the common case of a host that only ships
/// first-party plugins compiled into it. It is **not** appropriate once untrusted
/// bundles can appear on disk — for that, use ``CodeSigningTrustPolicy``, which is
/// why this type says so in its own name rather than being called
/// `DefaultTrustPolicy`.
public struct LocationTrustPolicy: TrustPolicy {
    /// Trust granted to plugins found in a development location.
    ///
    /// Defaults to ``TrustLevel/sandboxedOnly`` even though development plugins
    /// are usually the author's own: a development path is an environment
    /// variable, and an environment variable is not an authentication mechanism.
    public let developmentTrust: TrustLevel

    public init(developmentTrust: TrustLevel = .sandboxedOnly) {
        self.developmentTrust = developmentTrust
    }

    public func evaluate(_ candidate: DiscoveredPlugin) async -> TrustDecision {
        switch candidate.trustHint {
        case .firstParty: return .trusted(.firstParty)
        case .managed: return .trusted(.verifiedDeveloper)
        case .userInstalled: return .trusted(.sandboxedOnly)
        case .development: return .trusted(developmentTrust)
        }
    }
}

/// Evaluates a plugin's code signature.
///
/// Checks, in order: a valid signature, the signing team against a pin list, the
/// quarantine flag, and whether the bundle carries its own copy of a framework the
/// host already provides.
///
/// That last check is the one people skip. Two copies of the same contract types
/// in one address space make `as?` across the seam fail while every version number
/// involved looks correct — a failure mode that costs days to diagnose in the
/// field and nothing to refuse here.
public struct CodeSigningTrustPolicy: TrustPolicy {
    /// Team IDs (the `OU` field of the signing leaf) granted
    /// ``TrustLevel/firstParty``. Normally just the host's own.
    public let firstPartyTeamIDs: [String]

    /// Team IDs granted ``TrustLevel/verifiedDeveloper``. Empty means any valid
    /// signature qualifies.
    public let trustedTeamIDs: [String]

    /// Whether an unsigned plugin is allowed, and at what level.
    ///
    /// `nil` — refuse — is the default. A development host that needs unsigned
    /// bundles should say so explicitly, in one place, rather than having the
    /// framework quietly permit it everywhere.
    public let unsignedTrust: TrustLevel?

    /// Refuse anything still carrying `com.apple.quarantine`.
    public let refusesQuarantined: Bool

    /// Framework names the host provides itself. A plugin embedding any of these
    /// is blocked.
    public let hostProvidedFrameworks: [String]

    public init(
        firstPartyTeamIDs: [String] = [],
        trustedTeamIDs: [String] = [],
        unsignedTrust: TrustLevel? = nil,
        refusesQuarantined: Bool = true,
        hostProvidedFrameworks: [String] = []
    ) {
        self.firstPartyTeamIDs = firstPartyTeamIDs
        self.trustedTeamIDs = trustedTeamIDs
        self.unsignedTrust = unsignedTrust
        self.refusesQuarantined = refusesQuarantined
        self.hostProvidedFrameworks = hostProvidedFrameworks
    }

    public func evaluate(_ candidate: DiscoveredPlugin) async -> TrustDecision {
        // Compiled-in code shares the host's signature by construction; there is
        // nothing separate to verify.
        guard case .bundle(let url) = candidate.location else {
            return .trusted(.firstParty)
        }

        if refusesQuarantined, Self.isQuarantined(url) {
            return .blocked(reason: .quarantined)
        }

        if let duplicate = duplicateFramework(in: url) {
            return .blocked(reason: .duplicateContractFramework(name: duplicate))
        }

        #if canImport(Security)
        switch Self.signingTeam(of: url) {
        case .valid(let team):
            if let team, firstPartyTeamIDs.contains(team) {
                return .trusted(.firstParty)
            }
            if trustedTeamIDs.isEmpty || (team.map(trustedTeamIDs.contains) ?? false) {
                return .trusted(.verifiedDeveloper)
            }
            return .blocked(reason: .untrustedTeam(found: team, expected: trustedTeamIDs))

        case .unsigned:
            guard let unsignedTrust else { return .blocked(reason: .unsigned) }
            return .trusted(unsignedTrust)

        case .invalid(let status):
            return .blocked(reason: .signatureInvalid(status: Int(status)))
        }
        #else
        guard let unsignedTrust else { return .blocked(reason: .unsigned) }
        return .trusted(unsignedTrust)
        #endif
    }

    private func duplicateFramework(in bundleURL: URL) -> String? {
        guard !hostProvidedFrameworks.isEmpty else { return nil }
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: frameworks, includingPropertiesForKeys: nil
        ) else { return nil }

        for url in contents {
            let name = url.deletingPathExtension().lastPathComponent
            if hostProvidedFrameworks.contains(name) { return name }
        }
        return nil
    }

    /// Whether the file still carries the Gatekeeper quarantine attribute.
    static func isQuarantined(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
        }
    }

    enum SigningResult {
        case valid(team: String?)
        case unsigned
        case invalid(status: OSStatus)
    }

    #if canImport(Security)
    /// Validates the signature and extracts the signing team identifier.
    ///
    /// Deliberately does **not** check a designated requirement string here: the
    /// team comparison is done in Swift above, so the pin list is inspectable and
    /// testable rather than encoded in a requirement DSL that fails opaquely.
    static func signingTeam(of url: URL) -> SigningResult {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return .invalid(status: createStatus)
        }

        let validity = SecStaticCodeCheckValidity(staticCode, [], nil)
        if validity == errSecCSUnsigned { return .unsigned }
        guard validity == errSecSuccess else { return .invalid(status: validity) }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        guard infoStatus == errSecSuccess,
              let dictionary = information as NSDictionary?
        else {
            // A valid signature whose details cannot be read is still valid; the
            // team is simply unknown, and the caller decides what that is worth.
            return .valid(team: nil)
        }

        let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        return .valid(team: team)
    }
    #endif
}
