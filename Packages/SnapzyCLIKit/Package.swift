// swift-tools-version: 6.0
import PackageDescription

// SnapzyCLIKit — the `snapzy` command line client and its wire contract.
//
// Target split, and why:
// - SnapzyCLIProtocol is Foundation-only. Snapzy.app links it to serve the
//   socket, so it must never pull in the client or ArgumentParser.
// - SnapzyCLIClient owns the socket connection and finding/launching the app.
// - SnapzyCLICore is the ArgumentParser command tree, kept as a library so it
//   is testable without an executable.
// - snapzy-dev is a development-only executable (`swift run snapzy-dev …`).
//   The shipped binary is the SnapzyCLI Xcode target embedded in
//   Snapzy.app/Contents/Helpers.

let package = Package(
  name: "SnapzyCLIKit",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "SnapzyCLIProtocol", targets: ["SnapzyCLIProtocol"]),
    .library(name: "SnapzyCLIClient", targets: ["SnapzyCLIClient"]),
    .library(name: "SnapzyCLICore", targets: ["SnapzyCLICore"]),
    .executable(name: "snapzy-dev", targets: ["SnapzyCLIDev"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
  ],
  targets: [
    .target(name: "SnapzyCLIProtocol"),
    .target(
      name: "SnapzyCLIClient",
      dependencies: ["SnapzyCLIProtocol"]
    ),
    .target(
      name: "SnapzyCLICore",
      dependencies: [
        "SnapzyCLIClient",
        "SnapzyCLIProtocol",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .executableTarget(
      name: "SnapzyCLIDev",
      dependencies: ["SnapzyCLICore"]
    ),
    .testTarget(
      name: "SnapzyCLIProtocolTests",
      dependencies: ["SnapzyCLIProtocol"]
    ),
    .testTarget(
      name: "SnapzyCLICoreTests",
      dependencies: ["SnapzyCLICore", "SnapzyCLIClient", "SnapzyCLIProtocol"]
    ),
  ]
)
