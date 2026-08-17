import Foundation

/// A comparable `major.minor.patch` version.
///
/// Used for three distinct things that all need the same ordering rules: a
/// plugin's own version, an extension point's contract version, and a
/// vocabulary's version. Pre-release identifiers are captured for
/// round-tripping and compare *below* the same release version, as semver
/// requires. Build metadata round-trips but is ignored for comparison.
public struct SemanticVersion: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    public var prerelease: [String]
    public var build: String?

    public init(
        _ major: Int,
        _ minor: Int = 0,
        _ patch: Int = 0,
        prerelease: [String] = [],
        build: String? = nil
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
    }

    /// Parses `1`, `1.2`, `1.2.3`, `1.2.3-beta.1`, `1.2.3+sha.abc`.
    ///
    /// Lenient on component count because version strings in the wild are
    /// frequently two-component (`"2.4"`), and rejecting an app's own
    /// `CFBundleShortVersionString` would be unhelpful pedantry.
    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var remainder = Substring(trimmed)
        var build: String?
        if let plus = remainder.firstIndex(of: "+") {
            build = String(remainder[remainder.index(after: plus)...])
            remainder = remainder[..<plus]
        }

        var prerelease: [String] = []
        if let dash = remainder.firstIndex(of: "-") {
            prerelease = remainder[remainder.index(after: dash)...]
                .split(separator: ".")
                .map(String.init)
            remainder = remainder[..<dash]
        }

        let components = remainder.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }

        var numbers: [Int] = []
        for component in components {
            guard let value = Int(component), value >= 0 else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }

        self.init(numbers[0], numbers[1], numbers[2], prerelease: prerelease, build: build)
    }

    public var description: String {
        var result = "\(major).\(minor).\(patch)"
        if !prerelease.isEmpty { result += "-" + prerelease.joined(separator: ".") }
        if let build { result += "+" + build }
        return result
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // A version carrying a pre-release tag precedes the matching release.
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false
        case (false, true): return true
        case (false, false): break
        }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?): return leftNumber < rightNumber
            case (nil, _?): return false  // numeric identifiers sort below alphanumeric
            case (_?, nil): return true
            case (nil, nil): return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = SemanticVersion(string: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "'\(raw)' is not a valid semantic version."
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension SemanticVersion: ExpressibleByStringLiteral {
    /// Traps on a malformed literal: a hard-coded version is programmer input,
    /// and a silent `0.0.0` fallback would quietly widen a version bound.
    public init(stringLiteral value: String) {
        guard let parsed = SemanticVersion(string: value) else {
            preconditionFailure("'\(value)' is not a valid semantic version literal.")
        }
        self = parsed
    }
}

extension SemanticVersion {
    /// Reads `CFBundleShortVersionString` from a bundle.
    ///
    /// Returns `nil` outside a bundle (command-line tools, test runners) rather
    /// than guessing, so a version-bound check becomes inapplicable instead of
    /// being enforced against a fabricated number.
    public static func fromBundle(_ bundle: Bundle = .main) -> SemanticVersion? {
        guard let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return nil }
        return SemanticVersion(string: raw)
    }
}
