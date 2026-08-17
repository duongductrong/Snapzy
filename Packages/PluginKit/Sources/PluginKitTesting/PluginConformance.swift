import Foundation
import PluginKitCore
import PluginKitHost
import PluginKitSDK

/// One thing a plugin got wrong.
public struct ConformanceFinding: Sendable, Hashable, CustomStringConvertible {
    /// Which check produced it.
    public let check: String
    public let detail: String

    public init(check: String, detail: String) {
        self.check = check
        self.detail = detail
    }

    public var description: String { "\(check): \(detail)" }
}

/// The checks every plugin should pass, in one call.
///
/// These are the invariants a host relies on and a plugin author has no natural
/// reason to test, because each of them only matters in a situation the author does
/// not reproduce locally: a capability denied by policy, a second `deactivate()` on
/// quit after a failed activation, a manifest that has quietly drifted from the code.
///
/// ```swift
/// @Test("Word Count conforms")
/// func conformance() async throws {
///     let findings = await PluginConformance(
///         manifest: manifest, makePlugin: { WordCountPlugin() }
///     )
///     .grantingAll { harness in
///         await harness.grant((any FileReading).self, StubFileReader())
///     }
///     .run()
///
///     #expect(findings.isEmpty, "\(findings)")
/// }
/// ```
public struct PluginConformance: Sendable {
    private let manifest: PluginManifest
    private let makePlugin: @Sendable () -> any Plugin
    private let arrange: @Sendable (PluginHarness) async -> Void
    private let deactivationBudget: Duration

    /// - Parameters:
    ///   - manifest: the plugin's real manifest, so drift is checked against what
    ///     will actually ship.
    ///   - makePlugin: builds a fresh instance. Called once per check, because a
    ///     plugin that only passes when reused is a plugin with hidden state.
    ///   - deactivationBudget: the deadline `deactivate()` must respect. Match the
    ///     host's.
    public init(
        manifest: PluginManifest,
        makePlugin: @escaping @Sendable () -> any Plugin,
        deactivationBudget: Duration = .seconds(2)
    ) {
        self.manifest = manifest
        self.makePlugin = makePlugin
        self.arrange = { _ in }
        self.deactivationBudget = deactivationBudget
    }

    private init(
        manifest: PluginManifest,
        makePlugin: @escaping @Sendable () -> any Plugin,
        arrange: @escaping @Sendable (PluginHarness) async -> Void,
        deactivationBudget: Duration
    ) {
        self.manifest = manifest
        self.makePlugin = makePlugin
        self.arrange = arrange
        self.deactivationBudget = deactivationBudget
    }

    /// Supplies the capability stubs the plugin needs on its happy path.
    public func granting(
        _ arrange: @escaping @Sendable (PluginHarness) async -> Void
    ) -> PluginConformance {
        PluginConformance(
            manifest: manifest,
            makePlugin: makePlugin,
            arrange: arrange,
            deactivationBudget: deactivationBudget
        )
    }

    /// Runs every check and returns what failed. Empty means the plugin is sound.
    public func run() async -> [ConformanceFinding] {
        var findings: [ConformanceFinding] = []
        findings += await checkManifestStructure()
        findings += await checkHappyPath()
        findings += await checkOptionalDenials()
        findings += await checkRequiredDenials()
        findings += await checkIdempotentDeactivation()
        return findings
    }

    // MARK: - Checks

    private func checkManifestStructure() async -> [ConformanceFinding] {
        do {
            try manifest.validateStructure()
            return []
        } catch {
            return [
                ConformanceFinding(
                    check: "manifest",
                    detail: error.localizedDescription
                )
            ]
        }
    }

    private func checkHappyPath() async -> [ConformanceFinding] {
        let harness = PluginHarness(manifest: manifest)
        await arrange(harness)
        do {
            try await harness.activate(makePlugin())
        } catch {
            return [
                ConformanceFinding(
                    check: "activation",
                    detail: "Activation failed with everything granted: "
                        + error.localizedDescription
                )
            ]
        }

        var findings: [ConformanceFinding] = []
        for drift in await harness.drift() where drift.isFatal {
            findings.append(ConformanceFinding(check: "manifest-drift", detail: drift.description))
        }
        await harness.deactivate()
        return findings
    }

    /// Denies every *optional* capability at once.
    ///
    /// A plugin declaring `required: false` is promising it can cope. This is the
    /// only place that promise gets tested, and it is the failure users actually
    /// hit — they decline one prompt and the plugin stops loading entirely.
    private func checkOptionalDenials() async -> [ConformanceFinding] {
        let optional = manifest.capabilities.filter { !$0.required }
        guard !optional.isEmpty else { return [] }

        let harness = PluginHarness(manifest: manifest)
        await arrange(harness)
        for request in optional {
            await harness.deny(request.id, reason: "Conformance check.")
        }

        do {
            try await harness.activate(makePlugin())
            await harness.deactivate()
            return []
        } catch {
            return [
                ConformanceFinding(
                    check: "optional-capability-denied",
                    detail: "Activation failed when the optional capabilities "
                        + optional.map { "'\($0.id)'" }.joined(separator: ", ")
                        + " were denied, but the manifest marks them not required: "
                        + error.localizedDescription
                )
            ]
        }
    }

    /// Denies each *required* capability in turn.
    ///
    /// The plugin is expected to throw. A plugin that activates anyway has either
    /// mislabelled the capability or is about to fail later, somewhere with no
    /// context attached.
    private func checkRequiredDenials() async -> [ConformanceFinding] {
        var findings: [ConformanceFinding] = []

        for request in manifest.capabilities where request.required {
            let harness = PluginHarness(manifest: manifest)
            await arrange(harness)
            await harness.deny(request.id, reason: "Conformance check.")

            do {
                try await harness.activate(makePlugin())
                findings.append(
                    ConformanceFinding(
                        check: "required-capability-denied",
                        detail: "Activation succeeded with the required capability "
                            + "'\(request.id)' denied. Either it is not really required, "
                            + "or the plugin is deferring a failure to somewhere less "
                            + "diagnosable."
                    )
                )
                await harness.deactivate()
            } catch {
                // Correct: a required capability was denied and the plugin refused
                // to pretend otherwise.
            }
        }

        return findings
    }

    /// `deactivate()` is called on a failed activation, on user disable, and again
    /// on quit. It has to survive all three, and finish inside the budget.
    private func checkIdempotentDeactivation() async -> [ConformanceFinding] {
        let harness = PluginHarness(manifest: manifest)
        await arrange(harness)
        let plugin = makePlugin()
        _ = try? await harness.activate(plugin)

        let clock = ContinuousClock()
        let began = clock.now
        await harness.deactivate()
        await harness.deactivate()
        await harness.deactivate()
        let elapsed = clock.now - began

        guard elapsed <= deactivationBudget else {
            return [
                ConformanceFinding(
                    check: "deactivation-budget",
                    detail: "Three deactivations took \(elapsed), over the "
                        + "\(deactivationBudget) budget. A host will abandon the plugin "
                        + "in place rather than wait."
                )
            ]
        }
        return []
    }
}
