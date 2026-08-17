// swift-tools-version: 6.0
import PackageDescription

// SnapzyPluginProtocol — the framed transport between Snapzy and a spawned
// plugin process. This is the entire third-party ABI: a plugin is anything
// that speaks this protocol, Swift or not.
//
// Target split, and why:
// - SnapzyPluginProtocol is Foundation-only on purpose. It must be reimplementable
//   by a Rust/Go/Node plugin author from PROTOCOL.md alone, so it may not drag
//   in SnapzyPluginAPI or PluginKit.
// - SnapzyPluginMessages is the typed Swift face over the wire: it maps the
//   message kinds to the existing Codable vocabulary (SnapzyCommandRequest,
//   HostCall, …) so the host runtime and the SDK share one codec.
//
// Placement during the migration: a local package under Packages/. Phase 03
// moves both targets into the SnapzyPluginSDK repository as products.

let package = Package(
  name: "SnapzyPluginProtocol",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "SnapzyPluginProtocol", targets: ["SnapzyPluginProtocol"]),
    .library(name: "SnapzyPluginMessages", targets: ["SnapzyPluginMessages"])
  ],
  dependencies: [
    .package(path: "../SnapzyPluginAPI")
  ],
  targets: [
    .target(
      name: "SnapzyPluginProtocol"
    ),
    .target(
      name: "SnapzyPluginMessages",
      dependencies: [
        "SnapzyPluginProtocol",
        .product(name: "SnapzyPluginAPI", package: "SnapzyPluginAPI")
      ]
    ),
    .testTarget(
      name: "SnapzyPluginProtocolTests",
      dependencies: ["SnapzyPluginProtocol"]
    ),
    .testTarget(
      name: "SnapzyPluginMessagesTests",
      dependencies: [
        "SnapzyPluginMessages",
        "SnapzyPluginProtocol",
        .product(name: "SnapzyPluginAPI", package: "SnapzyPluginAPI")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
