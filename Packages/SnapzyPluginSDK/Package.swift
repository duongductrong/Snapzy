// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SnapzyPluginSDK",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "SnapzyPluginSDK", targets: ["SnapzyPluginSDK"]),
    .library(name: "SnapzyPluginTesting", targets: ["SnapzyPluginTesting"]),
    .library(name: "SnapzyPluginCLICore", targets: ["SnapzyPluginCLICore"]),
    .executable(name: "snapzy-plugin", targets: ["SnapzyPluginCLI"])
  ],
  dependencies: [
    .package(path: "../PluginKit"),
    .package(path: "../SnapzyPluginAPI"),
    .package(path: "../SnapzyPluginProtocol")
  ],
  targets: [
    .target(
      name: "SnapzyPluginSDK",
      dependencies: [
        .product(name: "PluginKitCore", package: "PluginKit"),
        .product(name: "SnapzyPluginAPI", package: "SnapzyPluginAPI"),
        .product(name: "SnapzyPluginProtocol", package: "SnapzyPluginProtocol"),
        .product(name: "SnapzyPluginMessages", package: "SnapzyPluginProtocol")
      ]
    ),
    .target(
      name: "SnapzyPluginTesting",
      dependencies: [
        "SnapzyPluginSDK",
        .product(name: "SnapzyPluginAPI", package: "SnapzyPluginAPI"),
        .product(name: "SnapzyPluginProtocol", package: "SnapzyPluginProtocol")
      ]
    ),
    .target(
      name: "SnapzyPluginCLICore",
      dependencies: [
        "SnapzyPluginSDK",
        .product(name: "PluginKitCore", package: "PluginKit"),
        .product(name: "SnapzyPluginAPI", package: "SnapzyPluginAPI"),
        .product(name: "SnapzyPluginProtocol", package: "SnapzyPluginProtocol")
      ]
    ),
    .executableTarget(
      name: "SnapzyPluginCLI",
      dependencies: [
        "SnapzyPluginCLICore"
      ]
    ),
    .testTarget(
      name: "SnapzyPluginSDKTests",
      dependencies: [
        "SnapzyPluginSDK",
        "SnapzyPluginTesting",
        "SnapzyPluginCLICore",
        .product(name: "SnapzyPluginAPI", package: "SnapzyPluginAPI")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
