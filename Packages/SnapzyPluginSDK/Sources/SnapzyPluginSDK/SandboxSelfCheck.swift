import CoreGraphics
import Foundation
import Security
import SnapzyPluginProtocol

public enum SandboxSelfCheck {
  public static func run() -> SandboxSelfCheckReport {
    var diagnostics: [String] = []

    // 1. Network: socket connect should fail without network entitlement
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    let networkDenied: Bool
    if socketFD < 0 {
      networkDenied = true
      diagnostics.append("socket() failed with errno \(errno)")
    } else {
      var address = sockaddr_in()
      address.sin_family = sa_family_t(AF_INET)
      address.sin_port = in_port_t(53).bigEndian
      address.sin_addr.s_addr = inet_addr("1.1.1.1")
      let connectResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
          connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
      close(socketFD)
      networkDenied = connectResult != 0
      if networkDenied {
        diagnostics.append("connect() returned \(connectResult) errno \(errno)")
      } else {
        diagnostics.append("connect() unexpectedly succeeded")
      }
    }

    // 2. Filesystem: reading ~/Desktop must fail
    let fileManager = FileManager.default
    let desktop = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    let desktopContents = try? fileManager.contentsOfDirectory(at: desktop, includingPropertiesForKeys: nil)
    let fileSystemDenied = (desktopContents == nil)
    if !fileSystemDenied {
      diagnostics.append("reading ~/Desktop unexpectedly succeeded")
    }

    // 3. Screen capture
    let screenImage = CGWindowListCreateImage(.null, .optionAll, 0, [.boundsIgnoreFraming])
    let screenCaptureDenied = (screenImage == nil)
    if !screenCaptureDenied {
      diagnostics.append("CGWindowListCreateImage returned an image")
    }

    // 4. Keychain
    let keychainQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.snapzy.plugin.sandbox-check",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var keychainResult: CFTypeRef?
    let keychainStatus = SecItemCopyMatching(keychainQuery as CFDictionary, &keychainResult)
    let keychainDenied = (keychainStatus != errSecSuccess)
    if !keychainDenied {
      diagnostics.append("SecItemCopyMatching returned \(keychainStatus)")
    }

    return SandboxSelfCheckReport(
      networkDenied: networkDenied,
      fileSystemDenied: fileSystemDenied,
      screenCaptureDenied: screenCaptureDenied,
      keychainDenied: keychainDenied,
      jsGlobalClean: nil,
      diagnostics: diagnostics
    )
  }
}
