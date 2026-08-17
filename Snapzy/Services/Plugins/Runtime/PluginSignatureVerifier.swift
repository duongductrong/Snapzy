import Foundation
import PluginKitHost
import Security

enum PluginSignatureError: Error, LocalizedError {
  case invalidExecutable(String)
  case unnotarizedOfficialPlugin(String)
  case missingSandboxEntitlement(String)
  case signatureVerificationFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidExecutable(let msg):
      return "Invalid plugin executable: \(msg)"
    case .unnotarizedOfficialPlugin(let msg):
      return "Official plugin requires valid Developer ID signature and notarization: \(msg)"
    case .missingSandboxEntitlement(let msg):
      return "Plugin binary missing app-sandbox entitlement: \(msg)"
    case .signatureVerificationFailed(let msg):
      return "Signature verification failed: \(msg)"
    }
  }
}

public struct PluginSignatureResult: Sendable {
  public let isSigned: Bool
  public let isAppSandboxed: Bool
  public let developerID: String?
  public let teamID: String?
}

enum PluginSignatureVerifier {
  static func verify(
    executableURL: URL,
    tier: PluginTier = .community,
    trustLevel: TrustLevel = .sandboxedOnly
  ) throws -> PluginSignatureResult {
    var staticCode: SecStaticCode?
    let createStatus = SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode)
    guard createStatus == errSecSuccess, let code = staticCode else {
      if tier == .official || trustLevel == .firstParty {
        throw PluginSignatureError.invalidExecutable("Could not inspect static code at \(executableURL.path)")
      }
      return PluginSignatureResult(isSigned: false, isAppSandboxed: false, developerID: nil, teamID: nil)
    }

    var cfDict: CFDictionary?
    let infoStatus = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &cfDict)
    guard infoStatus == errSecSuccess, let info = cfDict as? [String: Any] else {
      if tier == .official || trustLevel == .firstParty {
        throw PluginSignatureError.signatureVerificationFailed("Could not copy signing information")
      }
      return PluginSignatureResult(isSigned: false, isAppSandboxed: false, developerID: nil, teamID: nil)
    }

    var isSandboxed = false
    if let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
      if let sandboxVal = entitlements["com.apple.security.app-sandbox"] as? Bool {
        isSandboxed = sandboxVal
      }
    }

    let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
    let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
    let developerID = certs?.first.flatMap { cert -> String? in
      var commonName: CFString?
      SecCertificateCopyCommonName(cert, &commonName)
      return commonName as String?
    }

    if tier == .official || trustLevel == .firstParty {
      guard isSandboxed else {
        throw PluginSignatureError.missingSandboxEntitlement("Official plugin executable is missing com.apple.security.app-sandbox entitlement.")
      }
      let flags = SecCSFlags(rawValue: 0)
      let validityStatus = SecStaticCodeCheckValidity(code, flags, nil)
      guard validityStatus == errSecSuccess else {
        throw PluginSignatureError.unnotarizedOfficialPlugin("Static code check failed with status \(validityStatus)")
      }
    }

    return PluginSignatureResult(
      isSigned: true,
      isAppSandboxed: isSandboxed,
      developerID: developerID,
      teamID: teamID
    )
  }
}
