import Foundation

public enum Templates {
  public static func packageSwift(pluginName: String) -> String {
    """
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "\(pluginName)",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    .package(url: "https://github.com/SnapzyApp/SnapzyPluginSDK.git", from: "1.0.0")
  ],
  targets: [
    .executableTarget(
      name: "\(pluginName)",
      dependencies: [
        .product(name: "SnapzyPluginSDK", package: "SnapzyPluginSDK")
      ]
    ),
    .testTarget(
      name: "\(pluginName)Tests",
      dependencies: [
        "\(pluginName)",
        .product(name: "SnapzyPluginTesting", package: "SnapzyPluginSDK")
      ]
    )
  ]
)
"""
  }

  public static func pluginJson(id: String, name: String, executable: String) -> String {
    """
{
  "id": "\(id)",
  "version": "1.0.0",
  "displayName": "\(name)",
  "description": "A native Swift plugin for Snapzy.",
  "sdkVersion": ">=1.0.0 <2.0.0",
  "runtime": {
    "kind": "custom",
    "runtimeID": "process",
    "options": {
      "executable": "\(executable)",
      "protocolVersion": "1.0.0"
    }
  },
  "activation": {
    "kind": "onDemand"
  },
  "capabilities": [
    {
      "id": "ui.toast",
      "reason": "Display notification upon command completion"
    }
  ],
  "contributions": [
    {
      "extensionPoint": "com.snapzy.command",
      "name": "run",
      "displayName": "\(name)",
      "contractVersion": "1.0.0",
      "metadata": {
        "title": "\(name)",
        "icon": "sparkles",
        "description": "Run \(name) command",
        "category": "utility"
      }
    }
  ]
}
"""
  }

  public static func sourceFile(pluginName: String) -> String {
    """
import Foundation
import SnapzyPluginSDK

@main
struct \(pluginName): SnapzyPlugin {
  static func configure(_ ctx: inout SnapzyPluginContext) {
    ctx.registerCommand("run") { cmd in
      try await cmd.ui.toast(message: "\(pluginName) executed successfully!")
      return .completed("Success")
    }
  }
}
"""
  }

  public static func testFile(pluginName: String) -> String {
    """
import Foundation
import SnapzyPluginTesting
import Testing

@testable import \(pluginName)

@Test func runCommandExecutes() async throws {
  let host = FakeHost()
  let harness = PluginHarness(\(pluginName).self, host: host)

  let result = try await harness.execute("run")
  #expect(result.isSuccess)
}
"""
  }

  public static func gitIgnore() -> String {
    """
.DS_Store
/.build
/Packages
*.xcodeproj
*.xcworkspace
"""
  }

  public static func readme(name: String, id: String) -> String {
    """
# \(name)

A native Swift plugin for Snapzy (`\(id)`).

## Development

Build and test locally with `snapzy-plugin`:

```bash
# Build plugin
snapzy-plugin build

# Run hot-reloading dev mode
snapzy-plugin dev

# Run unit tests
swift test
```

## Packaging

To package for distribution:

```bash
snapzy-plugin package --identity "Developer ID Application: Your Name (TEAMID)"
```
"""
  }
}
