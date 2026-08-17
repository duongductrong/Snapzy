// swift-tools-version: 6.0
import PackageDescription
import Foundation

// MARK: - Distribution mode
//
// `xcodebuild archive` only emits a real `.framework` for a *dynamic* library
// product; a static one archives to a bare `.o` that cannot be packaged. The
// binary tier therefore sets PLUGINKIT_XCFRAMEWORK=1 to flip products to
// dynamic and passes MACH_O_TYPE=staticlib to get static frameworks back out.
//
// This is linkage only — it never changes the API, the sources, or the language
// mode, so both tiers build from one manifest with no patching or copying.
//
// Library evolution is deliberately *not* set here. `.unsafeFlags` would make
// this package unusable as a git dependency, and evolution mode only matters for
// the binary tier — where the distribution script passes
// `-Xswiftc -enable-library-evolution` for PluginKitCore and PluginKitSDK. Those
// two are the only targets that sit on a binary boundary between a host and a
// separately-compiled plugin; see README, "Binary compatibility".
let buildingXCFrameworks = ProcessInfo.processInfo.environment["PLUGINKIT_XCFRAMEWORK"] == "1"
let libraryType: Product.Library.LibraryType? = buildingXCFrameworks ? .dynamic : nil

let package = Package(
    name: "PluginKit",
    platforms: [
        // macOS-only by design. The trust model (code signing, library
        // validation), the runtime backends (XPC, ExtensionKit), and the
        // filesystem conventions have no meaningful analogue elsewhere, and
        // pretending otherwise would produce a lowest-common-denominator API.
        .macOS(.v13),
    ],
    products: [
        // ── Shared contract layer ────────────────────────────────────────────
        // Both a host and a plugin link exactly this. One build, one copy.
        .library(name: "PluginKitCore", type: libraryType, targets: ["PluginKitCore"]),

        // ── Plugin author's surface ──────────────────────────────────────────
        // Never link this into a host app: it carries authoring and manifest
        // tooling a host has no use for.
        .library(name: "PluginKitSDK", type: libraryType, targets: ["PluginKitSDK"]),

        // ── Host's surface ───────────────────────────────────────────────────
        // Never link this into a plugin: it carries discovery, trust evaluation,
        // and brokering, none of which a plugin may perform for itself.
        .library(name: "PluginKitHost", type: libraryType, targets: ["PluginKitHost"]),

        // ── Runtime backends. A host links only the ones it ships. ───────────
        .library(name: "PluginKitInProcess", type: libraryType, targets: ["PluginKitInProcess"]),

        // ── Test-only. Never link into a shipping product. ───────────────────
        .library(name: "PluginKitTesting", type: libraryType, targets: ["PluginKitTesting"]),

        .executable(name: "pluginkit", targets: ["PluginKitCLI"]),
    ],
    targets: [
        // Layer 0 — the shared contract. Pure domain plus the protocol seams a
        // host implements and a plugin consumes. No discovery, no loading, no
        // brokering, no AppKit. This is the *only* target that appears in both
        // a host's and a plugin's dependency graph, which is what stops the two
        // from being built twice or drifting apart.
        .target(name: "PluginKitCore"),

        // Layer 1 — the two consumer-facing surfaces. Deliberately siblings:
        // neither depends on the other, so nothing host-only can reach a plugin
        // and nothing author-only can reach a shipping app.
        .target(name: "PluginKitSDK", dependencies: ["PluginKitCore"]),
        .target(name: "PluginKitHost", dependencies: ["PluginKitCore"]),

        // Layer 2 — runtime backends. Each knows Core (to speak the contract)
        // and Host (to conform to the runtime seam), never the SDK.
        .target(name: "PluginKitInProcess", dependencies: ["PluginKitCore", "PluginKitHost"]),

        // Layer 3 — harnesses. The one place that legitimately sees every layer,
        // because it fakes whichever side is not under test.
        .target(
            name: "PluginKitTesting",
            dependencies: ["PluginKitCore", "PluginKitSDK", "PluginKitHost", "PluginKitInProcess"]
        ),

        // Authoring tooling. Depends on Core only: it reads manifests and
        // catalogs as data and never loads plugin code, so it stays fast and
        // cannot drag the host machinery into an author's toolchain.
        .executableTarget(name: "PluginKitCLI", dependencies: ["PluginKitCore"]),

        .testTarget(name: "PluginKitTests", dependencies: ["PluginKitTesting"]),
    ],
    swiftLanguageModes: [.v6]
)
