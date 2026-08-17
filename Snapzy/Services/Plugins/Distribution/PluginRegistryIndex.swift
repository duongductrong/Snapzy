import Foundation
import SnapzyPluginAPI

/// The published plugin index: `index.json` served from `plugins.snapzy.app`
/// with fallback to GitHub Pages. Forward-compatible decoding: unknown fields
/// are ignored, so a newer index parses on an older client.
struct PluginRegistryIndex: Codable, Sendable {
  let indexVersion: Int
  let plugins: [PluginIndexEntry]

  static func decode(_ data: Data) throws -> PluginRegistryIndex {
    try JSONDecoder().decode(PluginRegistryIndex.self, from: data)
  }

  static func decodeForwardCompatibly(_ data: Data) -> PluginRegistryIndex? {
    try? decode(data)
  }
}

struct PluginIndexEntry: Codable, Sendable, Identifiable {
  let id: String
  let version: String
  let displayName: String
  let summary: String?
  let tier: String // "official" | "verified" | "community"
  let minAppVersion: String
  let contractVersion: String
  let documentSchema: Int
  let capabilities: [IndexCapability]
  let bundleURL: String
  let bundleSHA256: String
  let signature: String?
  let revoked: Bool
  let revokedReason: String?

  // Native plugin distribution fields (Phase 06)
  let runtime: String? // "script" | "process"
  let protocolVersion: String? // "1.0.0"
  let architectures: [String]? // ["arm64", "x86_64"]
  let teamIdentifier: String? // e.g. "XMHV5GH2Z7"

  /// The index uses snapshot-style entries; decoding tolerates missing
  /// optional metadata from older index versions.
  init(
    id: String,
    version: String,
    displayName: String,
    summary: String? = nil,
    tier: String,
    minAppVersion: String,
    contractVersion: String,
    documentSchema: Int,
    capabilities: [IndexCapability],
    bundleURL: String,
    bundleSHA256: String,
    signature: String? = nil,
    revoked: Bool = false,
    revokedReason: String? = nil,
    runtime: String? = "script",
    protocolVersion: String? = nil,
    architectures: [String]? = nil,
    teamIdentifier: String? = nil
  ) {
    self.id = id
    self.version = version
    self.displayName = displayName
    self.summary = summary
    self.tier = tier
    self.minAppVersion = minAppVersion
    self.contractVersion = contractVersion
    self.documentSchema = documentSchema
    self.capabilities = capabilities
    self.bundleURL = bundleURL
    self.bundleSHA256 = bundleSHA256
    self.signature = signature
    self.revoked = revoked
    self.revokedReason = revokedReason
    self.runtime = runtime
    self.protocolVersion = protocolVersion
    self.architectures = architectures
    self.teamIdentifier = teamIdentifier
  }

  enum CodingKeys: String, CodingKey {
    case id, version, displayName, summary, tier, minAppVersion
    case contractVersion, documentSchema, capabilities
    case bundleURL, bundleSHA256, signature, revoked, revokedReason
    case runtime, protocolVersion, architectures, teamIdentifier
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    version = try container.decode(String.self, forKey: .version)
    displayName = try container.decode(String.self, forKey: .displayName)
    summary = try container.decodeIfPresent(String.self, forKey: .summary)
    tier = try container.decodeIfPresent(String.self, forKey: .tier) ?? "community"
    minAppVersion = try container.decodeIfPresent(String.self, forKey: .minAppVersion) ?? "0.0.0"
    contractVersion = try container.decodeIfPresent(String.self, forKey: .contractVersion) ?? "1.0.0"
    documentSchema = try container.decodeIfPresent(Int.self, forKey: .documentSchema) ?? 1
    capabilities = try container.decodeIfPresent([IndexCapability].self, forKey: .capabilities) ?? []
    bundleURL = try container.decode(String.self, forKey: .bundleURL)
    bundleSHA256 = try container.decode(String.self, forKey: .bundleSHA256)
    signature = try container.decodeIfPresent(String.self, forKey: .signature)
    revoked = try container.decodeIfPresent(Bool.self, forKey: .revoked) ?? false
    revokedReason = try container.decodeIfPresent(String.self, forKey: .revokedReason)
    runtime = try container.decodeIfPresent(String.self, forKey: .runtime) ?? "script"
    protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion)
    architectures = try container.decodeIfPresent([String].self, forKey: .architectures)
    teamIdentifier = try container.decodeIfPresent(String.self, forKey: .teamIdentifier)
  }
}

struct IndexCapability: Codable, Sendable, Hashable {
  let id: String
  let scope: [String: [String]]? // e.g. {"hosts": ["api.openai.com"]}

  init(id: String, scope: [String: [String]]? = nil) {
    self.id = id
    self.scope = scope
  }

  enum CodingKeys: String, CodingKey { case id, scope }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    scope = try container.decodeIfPresent([String: [String]].self, forKey: .scope)
  }
}

/// The registry client: ETag + 24 h TTL + on-disk cache + offline banner. The
/// index fetch is the only network call the plugin system adds, and it is
/// user-initiated (or opt-in daily).
@PluginEngine
final class PluginRegistryClient {
  static let shared = PluginRegistryClient()

  static let primaryIndexURL = URL(string: "https://plugins.snapzy.app/index.json")!
  static let fallbackIndexURL = URL(string: "https://duongductrong.github.io/SnapzyPlugins/index.json")!
  static let indexURL = primaryIndexURL
  static let cacheTTL: TimeInterval = 24 * 3_600

  enum State {
    case notLoaded
    case loaded(PluginRegistryIndex, source: Source)
    case offline(PluginRegistryIndex?)
    case failed(String)

    enum Source: Equatable {
      case network
      case cache
    }
  }

  private(set) var state: State = .notLoaded

  func fetch(force: Bool = false) async {
    // On-disk cache, when fresh enough and not forced.
    if !force {
      let attributes = try? FileManager.default.attributesOfItem(
        atPath: PluginDirectory.registryCacheURL.path
      )
      if let date = attributes?[.modificationDate] as? Date,
        Date().timeIntervalSince(date) < Self.cacheTTL,
        let data = try? Data(contentsOf: PluginDirectory.registryCacheURL),
        let index = PluginRegistryIndex.decodeForwardCompatibly(data)
      {
        state = .loaded(index, source: .cache)
        return
      }
    }

    // Try primary, then fallback
    for url in [Self.primaryIndexURL, Self.fallbackIndexURL] {
      var request = URLRequest(url: url)
      request.timeoutInterval = 15
      request.cachePolicy = .reloadIgnoringLocalCacheData
      let cachedETag = UserDefaults.standard.string(forKey: "Snapzy.pluginIndexETag")
      if let cachedETag {
        request.setValue(cachedETag, forHTTPHeaderField: "If-None-Match")
      }

      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
          if http.statusCode == 304, let cachedData = try? Data(contentsOf: PluginDirectory.registryCacheURL),
            let index = PluginRegistryIndex.decodeForwardCompatibly(cachedData)
          {
            state = .loaded(index, source: .cache)
            return
          }
          if http.statusCode != 200 {
            continue
          }
          if let etag = http.value(forHTTPHeaderField: "ETag") {
            UserDefaults.standard.set(etag, forKey: "Snapzy.pluginIndexETag")
          }
        }
        guard let index = PluginRegistryIndex.decodeForwardCompatibly(data) else {
          continue
        }
        try cache(data)
        state = .loaded(index, source: .network)
        return
      } catch {
        continue
      }
    }

    let cached = (try? Data(contentsOf: PluginDirectory.registryCacheURL))
      .flatMap(PluginRegistryIndex.decodeForwardCompatibly)
    state = cached.map { .offline($0) } ?? .failed("Failed to connect to plugin registry.")
  }

  private func cache(_ data: Data) throws {
    try FileManager.default.createDirectory(
      at: PluginDirectory.registryCacheURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: PluginDirectory.registryCacheURL, options: .atomic)
  }
}
