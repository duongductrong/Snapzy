// swift-tools-version: 6.0
import PackageDescription

// SnapzyPluginAPI — the public plugin vocabulary.
//
// This package must NEVER import Snapzy: it is the only thing a third-party
// plugin author compiles against, and the dependency direction is
// Snapzy → SnapzyPluginAPI → PluginKitCore, one way only.
//
// It links PluginKitCore only (never PluginKitHost, never PluginKitSDK).
// The host builds this package as a local dependency; plugin authors can use
// the same package to author TypeScript against the JSON contracts.

let package = Package(
  name: "SnapzyPluginAPI",
  platforms: [
    .macOS(.v13),
  ],
  products: [
    .library(name: "SnapzyPluginAPI", targets: ["SnapzyPluginAPI"])
  ],
  dependencies: [
    .package(path: "../PluginKit")
  ],
  targets: [
    .target(
      name: "SnapzyPluginAPI",
      dependencies: [
        .product(name: "PluginKitCore", package: "PluginKit")
      ]
    ),
    .testTarget(
      name: "SnapzyPluginAPITests",
      dependencies: ["SnapzyPluginAPI"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
