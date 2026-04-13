//
//  CloudUsageService.swift
//  Snapzy
//
//  Fetches cloud bucket usage via S3-compatible API (ListObjectsV2 + lifecycle)
//  Works with both AWS S3 and Cloudflare R2 using existing credentials.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "CloudUsageService")

private struct CloudUsageCacheEntry: Codable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let configFingerprint: String
  let info: CloudUsageInfo
}

private actor CloudUsageWorker {
  func fetchUsage(
    config: CloudConfiguration,
    accessKey: String,
    secretKey: String
  ) async throws -> CloudUsageInfo {
    let context = makeRequestContext(config: config)

    let (totalBytes, objectCount) = try await listAllObjects(
      config: config,
      endpoint: context.endpoint,
      region: context.region,
      accessKey: accessKey,
      secretKey: secretKey
    )
    let lifecycleDays = try? await getLifecycleRuleDays(
      config: config,
      endpoint: context.endpoint,
      region: context.region,
      accessKey: accessKey,
      secretKey: secretKey
    )

    return CloudUsageInfo(
      providerType: config.providerType,
      totalStorageBytes: totalBytes,
      objectCount: objectCount,
      lifecycleRuleDays: lifecycleDays,
      fetchedAt: Date()
    )
  }

  private func listAllObjects(
    config: CloudConfiguration,
    endpoint: String,
    region: String,
    accessKey: String,
    secretKey: String
  ) async throws -> (Int64, Int) {
    var totalBytes: Int64 = 0
    var objectCount = 0
    var continuationToken: String?

    repeat {
      var queryString = "list-type=2&prefix=snapzy/&max-keys=1000"
      if let token = continuationToken {
        let encodedToken =
          token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        queryString += "&continuation-token=\(encodedToken)"
      }

      let url = URL(string: "\(endpoint)/\(config.bucket)?\(queryString)")!
      var request = URLRequest(url: url)
      request.httpMethod = "GET"

      let signedRequest = try AWSV4Signer.sign(
        request: request,
        accessKey: accessKey,
        secretKey: secretKey,
        region: region,
        payloadHash: AWSV4Signer.sha256Hex("")
      )

      let (data, response) = try await URLSession.shared.data(for: signedRequest)

      guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
      else {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        logger.error(
          "ListObjectsV2 failed: status=\(statusCode), provider=\(config.providerType.rawValue), region=\(region), endpoint=\(endpoint), body=\(body)"
        )
        throw CloudError.uploadFailed(
          statusCode: statusCode,
          message: usageErrorMessage(
            statusCode: statusCode,
            body: body,
            providerType: config.providerType
          )
        )
      }

      let parsed = ListObjectsV2Parser.parse(data: data)
      totalBytes += parsed.totalSize
      objectCount += parsed.objectCount
      continuationToken = parsed.nextContinuationToken
    } while continuationToken != nil

    return (totalBytes, objectCount)
  }

  private func getLifecycleRuleDays(
    config: CloudConfiguration,
    endpoint: String,
    region: String,
    accessKey: String,
    secretKey: String
  ) async throws -> Int? {
    let url = URL(string: "\(endpoint)/\(config.bucket)?lifecycle")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    let signedRequest = try AWSV4Signer.sign(
      request: request,
      accessKey: accessKey,
      secretKey: secretKey,
      region: region,
      payloadHash: AWSV4Signer.sha256Hex("")
    )

    let (data, response) = try await URLSession.shared.data(for: signedRequest)

    guard let httpResponse = response as? HTTPURLResponse else { return nil }
    if httpResponse.statusCode == 404 { return nil }
    guard (200...299).contains(httpResponse.statusCode) else { return nil }

    return LifecycleRuleParser.parseSnapzyExpireDays(from: data)
  }

  private struct RequestContext {
    let endpoint: String
    let region: String
  }

  private func makeRequestContext(config: CloudConfiguration) -> RequestContext {
    let region: String
    switch config.providerType {
    case .cloudflareR2:
      // R2 requires region=auto for Signature V4.
      region = "auto"
    case .awsS3:
      let configuredRegion = config.region.trimmingCharacters(in: .whitespacesAndNewlines)
      region = configuredRegion.isEmpty ? "us-east-1" : configuredRegion
    }

    let endpoint: String
    if let configuredEndpoint = config.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
      !configuredEndpoint.isEmpty
    {
      endpoint = normalizeEndpoint(configuredEndpoint)
    } else {
      endpoint = "https://s3.\(region).amazonaws.com"
    }

    return RequestContext(endpoint: endpoint, region: region)
  }

  private func normalizeEndpoint(_ endpoint: String) -> String {
    var value = endpoint
    if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
      value = "https://\(value)"
    }
    while value.hasSuffix("/") {
      value.removeLast()
    }
    return value
  }

  private func usageErrorMessage(
    statusCode: Int,
    body: String,
    providerType: CloudProviderType
  ) -> String {
    let lowercasedBody = body.lowercased()

    if statusCode == 403 || lowercasedBody.contains("accessdenied") {
      return L10n.CloudUsage.missingBucketListPermission
    }

    if statusCode == 401 || lowercasedBody.contains("signature") || lowercasedBody.contains("unauthorized") {
      if providerType == .cloudflareR2 {
        return L10n.CloudUsage.unauthorizedR2
      }
      return L10n.CloudUsage.unauthorizedGeneric
    }

    return L10n.CloudUsage.listObjectsFailed(body)
  }
}

/// Fetches and caches bucket usage statistics using S3-compatible API.
@MainActor
final class CloudUsageService: ObservableObject {

  static let shared = CloudUsageService()

  // MARK: - Published State

  @Published private(set) var usageInfo: CloudUsageInfo?
  @Published private(set) var isLoading = false
  @Published private(set) var error: String?

  // MARK: - Pricing Constants (per GB-month)

  private static let r2PricePerGB: Double = 0.015
  private static let s3PricePerGB: Double = 0.023
  private static let r2FreeStorageBytes: Int64 = 10 * 1_073_741_824  // 10 GB
  private static let s3FreeStorageBytes: Int64 = 5 * 1_073_741_824   // 5 GB (year 1)
  private static let cacheTTL: TimeInterval = 10 * 60  // 10 minutes

  private let worker = CloudUsageWorker()
  private var inFlightTask: Task<Void, Never>?
  private var memoryCache: CloudUsageCacheEntry?
  private let defaults = UserDefaults.standard

  private init() {
    loadCacheIntoMemoryIfPossible()
  }

  // MARK: - Computed Properties

  /// Estimated monthly cost based on storage × unit price
  var estimatedMonthlyCost: String {
    guard let info = usageInfo else { return "—" }
    let providerType = info.providerType

    let storageGB = Double(info.totalStorageBytes) / 1_073_741_824.0
    let freeBytes = providerType == .cloudflareR2
      ? Self.r2FreeStorageBytes : Self.s3FreeStorageBytes
    let pricePerGB = providerType == .cloudflareR2
      ? Self.r2PricePerGB : Self.s3PricePerGB

    if info.totalStorageBytes <= freeBytes {
      return L10n.CloudUsage.freeTier
    }

    let billableGB = max(0.0, storageGB - Double(freeBytes) / 1_073_741_824.0)
    let cost = billableGB * pricePerGB

    if cost < 0.01 {
      return "< $0.01"
    }
    return String(format: "$%.2f", cost)
  }

  // MARK: - Fetch

  /// Fetch bucket usage by listing objects and checking lifecycle config.
  func fetchUsage(forceRefresh: Bool = false) async {
    guard let config = CloudManager.shared.loadConfiguration() else {
      usageInfo = nil
      error = L10n.CloudUsage.notConfigured
      return
    }
    guard let credentials = loadCredentials() else {
      usageInfo = nil
      error = L10n.CloudUsage.notConfigured
      return
    }

    let fingerprint = Self.makeConfigFingerprint(config: config)
    let hasFreshCache = applyCachedUsageIfAvailable(fingerprint: fingerprint)

    if hasFreshCache && !forceRefresh {
      error = nil
      return
    }

    if let inFlightTask {
      await inFlightTask.value
      return
    }

    isLoading = true
    error = nil

    let task = Task { [weak self] in
      guard let self else { return }
      defer {
        Task { @MainActor in
          self.isLoading = false
          self.inFlightTask = nil
        }
      }

      do {
        let info = try await self.worker.fetchUsage(
          config: config,
          accessKey: credentials.accessKey,
          secretKey: credentials.secretKey
        )
        await MainActor.run {
          self.usageInfo = info
          self.error = nil

          let cacheEntry = CloudUsageCacheEntry(
            schemaVersion: CloudUsageCacheEntry.currentSchemaVersion,
            configFingerprint: fingerprint,
            info: info
          )
          self.memoryCache = cacheEntry
          self.persistCacheEntry(cacheEntry)
          logger.info("Usage fetched: \(info.formattedStorage), \(info.objectCount) objects")
        }
      } catch is CancellationError {
        logger.debug("Usage fetch cancelled")
      } catch {
        await MainActor.run {
          if self.usageInfo == nil {
            self.error = Self.userFacingErrorMessage(from: error)
          } else {
            self.error = L10n.CloudUsage.couldntRefreshShowingCached
          }
          logger.error("Usage fetch failed: \(error.localizedDescription)")
        }
      }
    }

    inFlightTask = task
    await task.value
  }

  func invalidateCache() {
    inFlightTask?.cancel()
    inFlightTask = nil
    isLoading = false
    usageInfo = nil
    error = nil
    memoryCache = nil
    defaults.removeObject(forKey: PreferencesKeys.cloudUsageStatsCache)
  }

  // MARK: - Helpers

  func hydrateCachedUsageIfAvailable() {
    guard let config = CloudManager.shared.loadConfiguration() else {
      usageInfo = nil
      error = nil
      return
    }

    let fingerprint = Self.makeConfigFingerprint(config: config)
    _ = applyCachedUsageIfAvailable(fingerprint: fingerprint)
    error = nil
  }

  private func loadCredentials() -> (accessKey: String, secretKey: String)? {
    let accessKey = CloudManager.shared.loadAccessKey().trimmingCharacters(in: .whitespacesAndNewlines)
    let secretKey = CloudManager.shared.loadSecretKey().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !accessKey.isEmpty, !secretKey.isEmpty else { return nil }
    return (accessKey, secretKey)
  }

  @discardableResult
  private func applyCachedUsageIfAvailable(fingerprint: String) -> Bool {
    guard let entry = loadCacheEntry(fingerprint: fingerprint) else { return false }
    usageInfo = entry.info
    memoryCache = entry

    let age = Date().timeIntervalSince(entry.info.fetchedAt)
    return age <= Self.cacheTTL
  }

  private func loadCacheIntoMemoryIfPossible() {
    guard let data = defaults.data(forKey: PreferencesKeys.cloudUsageStatsCache) else { return }
    do {
      let entry = try JSONDecoder().decode(CloudUsageCacheEntry.self, from: data)
      guard entry.schemaVersion == CloudUsageCacheEntry.currentSchemaVersion else {
        defaults.removeObject(forKey: PreferencesKeys.cloudUsageStatsCache)
        return
      }
      memoryCache = entry
    } catch {
      defaults.removeObject(forKey: PreferencesKeys.cloudUsageStatsCache)
      logger.error("Failed to decode usage cache at startup: \(error.localizedDescription)")
    }
  }

  private func loadCacheEntry(fingerprint: String) -> CloudUsageCacheEntry? {
    if let memoryCache,
      memoryCache.schemaVersion == CloudUsageCacheEntry.currentSchemaVersion,
      memoryCache.configFingerprint == fingerprint
    {
      return memoryCache
    }

    guard let data = defaults.data(forKey: PreferencesKeys.cloudUsageStatsCache) else { return nil }
    do {
      let entry = try JSONDecoder().decode(CloudUsageCacheEntry.self, from: data)
      guard entry.schemaVersion == CloudUsageCacheEntry.currentSchemaVersion else {
        defaults.removeObject(forKey: PreferencesKeys.cloudUsageStatsCache)
        return nil
      }
      guard entry.configFingerprint == fingerprint else { return nil }
      memoryCache = entry
      return entry
    } catch {
      defaults.removeObject(forKey: PreferencesKeys.cloudUsageStatsCache)
      logger.error("Failed to decode usage cache: \(error.localizedDescription)")
      return nil
    }
  }

  private func persistCacheEntry(_ entry: CloudUsageCacheEntry) {
    do {
      let data = try JSONEncoder().encode(entry)
      defaults.set(data, forKey: PreferencesKeys.cloudUsageStatsCache)
    } catch {
      logger.error("Failed to encode usage cache: \(error.localizedDescription)")
    }
  }

  private static func makeConfigFingerprint(config: CloudConfiguration) -> String {
    let bucket = config.bucket.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let region: String
    switch config.providerType {
    case .cloudflareR2:
      region = "auto"
    case .awsS3:
      let configuredRegion = config.region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      region = configuredRegion.isEmpty ? "us-east-1" : configuredRegion
    }
    let endpoint = (config.endpoint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return "\(config.providerType.rawValue)|\(bucket)|\(region)|\(endpoint)"
  }

  private static func userFacingErrorMessage(from error: Error) -> String {
    if let cloudError = error as? CloudError {
      switch cloudError {
      case .uploadFailed(_, let message):
        return message
      default:
        break
      }
    }
    return error.localizedDescription
  }
}

// MARK: - ListObjectsV2 XML Parser

/// Lightweight XML parser for ListObjectsV2 response.
/// Extracts <Size> values, <KeyCount>, and <NextContinuationToken>.
final class ListObjectsV2Parser: NSObject, XMLParserDelegate {

  struct Result {
    var totalSize: Int64 = 0
    var objectCount: Int = 0
    var nextContinuationToken: String? = nil
  }

  private var result = Result()
  private var currentElement = ""
  private var currentText = ""

  static func parse(data: Data) -> Result {
    let handler = ListObjectsV2Parser()
    let parser = XMLParser(data: data)
    parser.delegate = handler
    parser.parse()
    return handler.result
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    currentElement = elementName
    currentText = ""
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    currentText += string
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
    switch elementName {
    case "Size":
      if let size = Int64(text) {
        result.totalSize += size
        result.objectCount += 1
      }
    case "NextContinuationToken":
      if !text.isEmpty {
        result.nextContinuationToken = text
      }
    default:
      break
    }
  }
}

// MARK: - Lifecycle Rule Parser

/// Parses lifecycle configuration XML to find the Snapzy auto-expire rule.
final class LifecycleRuleParser: NSObject, XMLParserDelegate {

  private var insideRule = false
  private var currentElement = ""
  private var currentText = ""
  private var currentRuleID = ""
  private var currentDays: Int? = nil
  private var foundDays: Int? = nil

  static func parseSnapzyExpireDays(from data: Data) -> Int? {
    let handler = LifecycleRuleParser()
    let parser = XMLParser(data: data)
    parser.delegate = handler
    parser.parse()
    return handler.foundDays
  }

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    currentElement = elementName
    currentText = ""
    if elementName == "Rule" {
      insideRule = true
      currentRuleID = ""
      currentDays = nil
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    currentText += string
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
    if insideRule {
      switch elementName {
      case "ID":
        currentRuleID = text
      case "Days":
        currentDays = Int(text)
      case "Rule":
        if currentRuleID == "snapzy-auto-expire", let days = currentDays {
          foundDays = days
        }
        insideRule = false
      default:
        break
      }
    }
  }
}
