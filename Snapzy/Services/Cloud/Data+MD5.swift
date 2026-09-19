//
//  Data+MD5.swift
//  Snapzy
//
//  MD5 hash extension for S3 Content-MD5 header requirement
//

import CryptoKit
import Foundation

extension Data {
  /// Compute MD5 digest and return as Base64 string (required by S3 for lifecycle PUT).
  func md5Base64() -> String {
    Data(Insecure.MD5.hash(data: self)).base64EncodedString()
  }
}
