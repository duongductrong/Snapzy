//
//  AWSV4Signer.swift
//  Snapzy
//
//  AWS Signature Version 4 request signing (pure Foundation, no SDK)
//  Used by both S3 and R2 (Cloudflare R2 is S3-compatible)
//

import CommonCrypto
import Foundation

/// AWS Signature Version 4 request signer
enum AWSV4Signer {

  // MARK: - Public API

  /// Sign a URLRequest with AWS Signature V4.
  /// - Parameters:
  ///   - request: The request to sign (URL, method, headers, body must be set)
  ///   - accessKey: AWS Access Key ID
  ///   - secretKey: AWS Secret Access Key
  ///   - region: AWS region (e.g. "us-east-1", "auto" for R2)
  ///   - service: AWS service name (always "s3")
  ///   - payloadHash: SHA256 hash of the body, or "UNSIGNED-PAYLOAD"
  /// - Returns: Signed request with Authorization header
  static func sign(
    request: URLRequest,
    accessKey: String,
    secretKey: String,
    region: String,
    service: String = "s3",
    payloadHash: String
  ) throws -> URLRequest {
    guard let url = request.url,
      let host = url.host,
      let method = request.httpMethod
    else {
      throw CloudError.signingFailed(L10n.CloudOperation.invalidRequestURLOrMethod)
    }

    var signedRequest = request
    let now = Date()
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
    dateFormatter.timeZone = TimeZone(identifier: "UTC")

    let amzDate = amzDateString(from: now)
    let dateStamp = dateStampString(from: now)
    let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"

    // Set required headers
    signedRequest.setValue(host, forHTTPHeaderField: "Host")
    signedRequest.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
    signedRequest.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

    // Build canonical request
    let canonicalURI = url.path.isEmpty ? "/" : url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
    let canonicalQueryString = canonicalQueryString(from: url)
    let (signedHeaders, canonicalHeaders) = buildCanonicalHeaders(from: signedRequest)

    let canonicalRequest = [
      method,
      canonicalURI,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].joined(separator: "\n")

    // String to sign
    let stringToSign = [
      "AWS4-HMAC-SHA256",
      amzDate,
      credentialScope,
      sha256Hex(canonicalRequest),
    ].joined(separator: "\n")

    // Signing key
    let signingKey = deriveSigningKey(
      secretKey: secretKey,
      dateStamp: dateStamp,
      region: region,
      service: service
    )

    // Signature
    let signature = hmacSHA256Hex(key: signingKey, data: stringToSign)

    // Authorization header
    let authorization =
      "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    signedRequest.setValue(authorization, forHTTPHeaderField: "Authorization")

    return signedRequest
  }

  /// Generate a presigned URL for GET access.
  /// - Parameters:
  ///   - url: The S3/R2 object URL
  ///   - accessKey: AWS Access Key ID
  ///   - secretKey: AWS Secret Access Key
  ///   - region: AWS region
  ///   - expireSeconds: URL validity in seconds (max 604800 = 7 days)
  /// - Returns: Presigned URL string
  static func presignURL(
    url: URL,
    accessKey: String,
    secretKey: String,
    region: String,
    service: String = "s3",
    expireSeconds: Int = 3600
  ) throws -> URL {
    guard let host = url.host else {
      throw CloudError.signingFailed(L10n.CloudOperation.invalidURLForPresigning)
    }

    let now = Date()
    let amzDate = amzDateString(from: now)
    let dateStamp = dateStampString(from: now)
    let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
    let credential = "\(accessKey)/\(credentialScope)"

    let canonicalURI = url.path.isEmpty ? "/" : url.path

    // Build query parameters for presigning
    var queryItems: [(String, String)] = [
      ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
      ("X-Amz-Credential", credential),
      ("X-Amz-Date", amzDate),
      ("X-Amz-Expires", "\(expireSeconds)"),
      ("X-Amz-SignedHeaders", "host"),
    ]
    queryItems.sort { $0.0 < $1.0 }

    let canonicalQueryString = queryItems.map { key, value in
      "\(uriEncode(key))=\(uriEncode(value))"
    }.joined(separator: "&")

    let canonicalHeaders = "host:\(host)\n"
    let signedHeaders = "host"

    let canonicalRequest = [
      "GET",
      canonicalURI,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      "UNSIGNED-PAYLOAD",
    ].joined(separator: "\n")

    let stringToSign = [
      "AWS4-HMAC-SHA256",
      amzDate,
      credentialScope,
      sha256Hex(canonicalRequest),
    ].joined(separator: "\n")

    let signingKey = deriveSigningKey(
      secretKey: secretKey,
      dateStamp: dateStamp,
      region: region,
      service: service
    )

    let signature = hmacSHA256Hex(key: signingKey, data: stringToSign)

    let presignedURLString =
      "\(url.scheme ?? "https")://\(host)\(canonicalURI)?\(canonicalQueryString)&X-Amz-Signature=\(signature)"

    guard let presignedURL = URL(string: presignedURLString) else {
      throw CloudError.signingFailed(L10n.CloudOperation.failedToConstructPresignedURL)
    }
    return presignedURL
  }

  // MARK: - Date Formatting

  private static func amzDateString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
  }

  private static func dateStampString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
  }

  // MARK: - Canonical Components

  private static func canonicalQueryString(from url: URL) -> String {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems, !queryItems.isEmpty
    else {
      return ""
    }
    return queryItems
      .map { item in
        let name = uriEncode(item.name)
        let value = uriEncode(item.value ?? "")
        return "\(name)=\(value)"
      }
      .sorted()
      .joined(separator: "&")
  }

  private static func buildCanonicalHeaders(from request: URLRequest) -> (
    signedHeaders: String, canonicalHeaders: String
  ) {
    var headers: [(String, String)] = []

    if let allHeaders = request.allHTTPHeaderFields {
      for (key, value) in allHeaders {
        headers.append((key.lowercased(), value.trimmingCharacters(in: .whitespaces)))
      }
    }
    headers.sort { $0.0 < $1.0 }

    let signedHeaders = headers.map { $0.0 }.joined(separator: ";")
    let canonicalHeaders = headers.map { "\($0.0):\($0.1)\n" }.joined()

    return (signedHeaders, canonicalHeaders)
  }

  // MARK: - Crypto Helpers

  private static func deriveSigningKey(
    secretKey: String,
    dateStamp: String,
    region: String,
    service: String
  ) -> Data {
    let kSecret = "AWS4\(secretKey)".data(using: .utf8)!
    let kDate = hmacSHA256(key: kSecret, data: dateStamp)
    let kRegion = hmacSHA256(key: kDate, data: region)
    let kService = hmacSHA256(key: kRegion, data: service)
    let kSigning = hmacSHA256(key: kService, data: "aws4_request")
    return kSigning
  }

  private static func hmacSHA256(key: Data, data: String) -> Data {
    let dataBytes = data.data(using: .utf8)!
    var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    key.withUnsafeBytes { keyPtr in
      dataBytes.withUnsafeBytes { dataPtr in
        CCHmac(
          CCHmacAlgorithm(kCCHmacAlgSHA256),
          keyPtr.baseAddress,
          key.count,
          dataPtr.baseAddress,
          dataBytes.count,
          &result
        )
      }
    }
    return Data(result)
  }

  private static func hmacSHA256Hex(key: Data, data: String) -> String {
    let hash = hmacSHA256(key: key, data: data)
    return hash.map { String(format: "%02x", $0) }.joined()
  }

  static func sha256Hex(_ string: String) -> String {
    let data = string.data(using: .utf8)!
    return sha256Hex(data)
  }

  static func sha256Hex(_ data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { ptr in
      _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - URI Encoding

  private static func uriEncode(_ string: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
  }
}
