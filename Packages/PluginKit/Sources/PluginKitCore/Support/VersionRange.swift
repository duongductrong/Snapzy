import Foundation

/// A half-open range of versions: `lowerBound` inclusive, `upperBound`
/// exclusive, either side optionally unbounded.
///
/// Half-open rather than closed because every real compatibility statement is
/// "works with the 2.x series" — expressed exactly by `2.0.0 ..< 3.0.0`, and
/// only awkwardly by any closed range, since there is no greatest 2.x version.
///
/// Encodes as a single string so manifests stay readable:
///
/// ```text
/// "*"                 any version
/// "1.2.3"             exactly 1.2.3
/// ">=1.0.0"           1.0.0 and up
/// "<2.0.0"            anything below 2.0.0
/// ">=1.0.0 <2.0.0"    the 1.x series
/// "1.0.0..<2.0.0"     the 1.x series, Swift range syntax
/// ```
public struct VersionRange: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Inclusive. `nil` means unbounded below.
    public let lowerBound: SemanticVersion?
    /// Exclusive. `nil` means unbounded above.
    public let upperBound: SemanticVersion?

    public init(from lowerBound: SemanticVersion? = nil, upTo upperBound: SemanticVersion? = nil) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public init(_ range: Range<SemanticVersion>) {
        self.lowerBound = range.lowerBound
        self.upperBound = range.upperBound
    }

    /// Every version, including pre-releases.
    public static let any = VersionRange()

    /// Only this exact version. Used by a plugin pinning a contract it has
    /// verified against and nothing else.
    public static func exact(_ version: SemanticVersion) -> VersionRange {
        // The upper bound has to exclude only `version` itself, so bump the
        // patch. Pre-releases of the next patch sort below it and are excluded,
        // which is the conservative reading and the right one for a pin.
        VersionRange(
            from: version,
            upTo: SemanticVersion(version.major, version.minor, version.patch + 1)
        )
    }

    /// `version ..< (major + 1).0.0` — the usual "compatible with" statement.
    public static func upToNextMajor(from version: SemanticVersion) -> VersionRange {
        VersionRange(from: version, upTo: SemanticVersion(version.major + 1, 0, 0))
    }

    /// `version ..< major.(minor + 1).0` — for a vocabulary still in `0.x`,
    /// where minor bumps are allowed to break.
    public static func upToNextMinor(from version: SemanticVersion) -> VersionRange {
        VersionRange(
            from: version,
            upTo: SemanticVersion(version.major, version.minor + 1, 0)
        )
    }

    /// The next version allowed to break compatibility.
    ///
    /// For `0.x`, that is the next **minor**: semver explicitly permits a 0.x minor
    /// bump to break, and treating `0.1` and `0.9` as compatible would let a plugin
    /// built against an early prototype be loaded by a host that has since changed
    /// the contract underneath it.
    public static func nextBreaking(after version: SemanticVersion) -> SemanticVersion {
        version.major == 0
            ? SemanticVersion(0, version.minor + 1, 0)
            : SemanticVersion(version.major + 1, 0, 0)
    }

    /// `version ..< nextBreaking` — what a plugin *built against* `version` works
    /// with. Lower-bounded at `version` because the plugin may use features added
    /// in it.
    public static func compatible(with version: SemanticVersion) -> VersionRange {
        VersionRange(from: version, upTo: nextBreaking(after: version))
    }

    /// The whole compatibility series `version` belongs to — what a *host* accepts.
    ///
    /// Wider than ``compatible(with:)`` at the bottom: a host on 1.4 still accepts a
    /// plugin built against 1.0, because nothing breaking happened in between.
    public static func series(of version: SemanticVersion) -> VersionRange {
        let base = version.major == 0
            ? SemanticVersion(0, version.minor, 0)
            : SemanticVersion(version.major, 0, 0)
        return VersionRange(from: base, upTo: nextBreaking(after: version))
    }

    public func contains(_ version: SemanticVersion) -> Bool {
        if let lowerBound, version < lowerBound { return false }
        if let upperBound, version >= upperBound { return false }
        return true
    }

    /// Whether two ranges admit at least one version in common.
    ///
    /// Used when a plugin states the range it supports and the host states the
    /// range it accepts: if they overlap at all, some negotiated version exists.
    public func overlaps(_ other: VersionRange) -> Bool {
        if let a = upperBound, let b = other.lowerBound, b >= a { return false }
        if let a = other.upperBound, let b = lowerBound, b >= a { return false }
        return true
    }

    public var description: String {
        switch (lowerBound, upperBound) {
        case (nil, nil):
            return "*"
        case (let lower?, nil):
            return ">=\(lower)"
        case (nil, let upper?):
            return "<\(upper)"
        case (let lower?, let upper?):
            return ">=\(lower) <\(upper)"
        }
    }

    // MARK: - Parsing

    /// Parses any of the forms shown in the type's documentation.
    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "*" {
            self = .any
            return
        }

        if let separator = trimmed.range(of: "..<") {
            guard
                let lower = SemanticVersion(string: String(trimmed[..<separator.lowerBound])),
                let upper = SemanticVersion(string: String(trimmed[separator.upperBound...]))
            else { return nil }
            self.init(from: lower, upTo: upper)
            return
        }

        var lower: SemanticVersion?
        var upper: SemanticVersion?
        var sawComparator = false

        for token in trimmed.split(separator: " ").map(String.init) where !token.isEmpty {
            if token.hasPrefix(">=") {
                guard let version = SemanticVersion(string: String(token.dropFirst(2))) else { return nil }
                lower = version
                sawComparator = true
            } else if token.hasPrefix("<") {
                guard let version = SemanticVersion(string: String(token.dropFirst(1))) else { return nil }
                upper = version
                sawComparator = true
            } else if !sawComparator, let version = SemanticVersion(string: token) {
                self = .exact(version)
                return
            } else {
                return nil
            }
        }

        guard sawComparator else { return nil }
        self.init(from: lower, upTo: upper)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = VersionRange(string: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "'\(raw)' is not a valid version range."
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension VersionRange: ExpressibleByStringLiteral {
    /// Traps on a malformed literal, for the same reason ``SemanticVersion``
    /// does: silently widening a compatibility bound is worse than a crash at
    /// the first line of `main`.
    public init(stringLiteral value: String) {
        guard let parsed = VersionRange(string: value) else {
            preconditionFailure("'\(value)' is not a valid version range literal.")
        }
        self = parsed
    }
}
