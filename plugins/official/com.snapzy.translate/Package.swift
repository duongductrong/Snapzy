// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Translate",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(path: "../../../Packages/SnapzyPluginSDK")
  ],
  targets: [
    .executableTarget(
      name: "Translate",
      dependencies: [
        .product(name: "SnapzyPluginSDK", package: "SnapzyPluginSDK")
      ]
    ),
    .testTarget(
      name: "TranslateTests",
      dependencies: [
        "Translate",
        .product(name: "SnapzyPluginTesting", package: "SnapzyPluginSDK")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
