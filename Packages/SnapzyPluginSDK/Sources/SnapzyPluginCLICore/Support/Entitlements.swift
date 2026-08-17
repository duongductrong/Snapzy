import Foundation

public enum Entitlements {
  public static let minimalAppSandboxPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
"""

  public static func validateEntitlementsData(_ data: Data) throws {
    guard let plist = try? PropertyListSerialization.propertyList(
      from: data,
      options: [],
      format: nil
    ) as? [String: Any] else {
      throw CLIError.validationFailed("Malformed entitlements plist data")
    }

    let forbiddenPrefixes = [
      "com.apple.security.network.client": "Plugins cannot declare direct network client entitlements; use ctx.http, which the host brokers.",
      "com.apple.security.network.server": "Plugins cannot open network server sockets.",
      "com.apple.security.files": "Plugins have no direct filesystem access; use ctx.storage or ctx.asset.",
      "com.apple.security.device": "Plugins cannot access hardware devices directly.",
      "keychain-access-groups": "Plugins cannot share keychain access groups; use ctx.secrets."
    ]

    for (key, reason) in forbiddenPrefixes {
      if plist[key] != nil {
        throw CLIError.validationFailed("Forbidden entitlement '\(key)': \(reason)")
      }
    }
  }
}
