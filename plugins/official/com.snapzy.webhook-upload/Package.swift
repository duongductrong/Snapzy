// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WebhookUpload",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(path: "../../../Packages/SnapzyPluginSDK")
  ],
  targets: [
    .executableTarget(
      name: "WebhookUpload",
      dependencies: [
        .product(name: "SnapzyPluginSDK", package: "SnapzyPluginSDK")
      ]
    ),
    .testTarget(
      name: "WebhookUploadTests",
      dependencies: [
        "WebhookUpload",
        .product(name: "SnapzyPluginTesting", package: "SnapzyPluginSDK")
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
