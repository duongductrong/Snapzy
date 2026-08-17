import CryptoKit
import Foundation

public enum StableID {
  /// Generates a deterministic stable ID for a text string, e.g. for idempotent document edits.
  public static func stableID(_ text: String, prefix: String = "item") -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(12)
    return "\(prefix)-\(hex)"
  }
}

public func stableID(_ text: String, prefix: String = "item") -> String {
  StableID.stableID(text, prefix: prefix)
}
