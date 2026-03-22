//
//  Data+MD5.swift
//  Snapzy
//
//  MD5 hash extension for S3 Content-MD5 header requirement
//

import CommonCrypto
import Foundation

extension Data {
  /// Compute MD5 digest and return as Base64 string (required by S3 for lifecycle PUT).
  func md5Base64() -> String {
    var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
    self.withUnsafeBytes { ptr in
      _ = CC_MD5(ptr.baseAddress, CC_LONG(self.count), &digest)
    }
    return Data(digest).base64EncodedString()
  }
}
