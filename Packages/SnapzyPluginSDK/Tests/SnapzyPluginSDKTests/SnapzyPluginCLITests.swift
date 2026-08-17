import Foundation
import PluginKitCore
import SnapzyPluginAPI
import SnapzyPluginCLICore
import SnapzyPluginSDK
import Testing

@Suite struct SnapzyPluginCLITests {
  @Test func templateGenerationProducesValidProject() throws {
    let packageContent = Templates.packageSwift(pluginName: "AwesomePlugin")
    #expect(packageContent.contains("name: \"AwesomePlugin\""))
    #expect(packageContent.contains("SnapzyPluginSDK"))

    let manifestContent = Templates.pluginJson(
      id: "com.example.awesome",
      name: "AwesomePlugin",
      executable: "AwesomePlugin"
    )
    let manifestData = Data(manifestContent.utf8)
    let manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData)
    #expect(manifest.id == PluginID("com.example.awesome"))
    #expect(manifest.displayName == "AwesomePlugin")
    #expect(manifest.runtime.preferredRuntime == RuntimeID("process"))
  }

  @Test func entitlementsValidationAllowsAppSandbox() throws {
    let allowedPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
"""
    #expect(throws: Never.self) {
      try Entitlements.validateEntitlementsData(Data(allowedPlist.utf8))
    }
  }

  @Test func entitlementsValidationRefusesDirectNetworkClient() throws {
    let forbiddenPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
"""
    #expect(throws: CLIError.self) {
      try Entitlements.validateEntitlementsData(Data(forbiddenPlist.utf8))
    }
  }

  @Test func manifestValidationEnforcesSizeCap() throws {
    let hugeData = Data(repeating: 0x20, count: 65 * 1024)
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("huge_plugin.json")
    try hugeData.write(to: tempFile)
    defer { try? FileManager.default.removeItem(at: tempFile) }

    #expect(throws: CLIError.self) {
      try ValidateCommand.validateManifest(at: tempFile)
    }
  }
}
