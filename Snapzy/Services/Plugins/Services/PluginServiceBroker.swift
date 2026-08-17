import AppKit
import Foundation
import PluginKitHost
import SnapzyPluginAPI

/// The service list is the permission model: every host call funnels through
/// here, no exceptions. Five steps, in order:
///
/// 1. resolve the capability for (plugin, service) — undeclared is refused
///    outright, the manifest is authoritative;
/// 2. policy ruling + consent gate (official: install-time; community:
///    first-use; sideloaded: per-session);
/// 3. per-call scope enforcement (host allowlist, invocation liveness, …);
/// 4. dispatch to the service;
/// 5. record a redacted entry in the request log.
///
/// Anything not routed here is unreachable from the helper: the sandbox stops
/// the process, the broker stops the plugin.
final class PluginServiceBroker {
  struct Environment {
    /// Reads a plugin record by ID — validates the caller is a loaded plugin.
    var pluginProvider: @Sendable (String) async -> PluginBrokerRecord?
    /// Policy + consent decision for a capability request.
    var decisionProvider: @Sendable (CapabilityRequest, PluginIdentity, TrustLevel) async -> CapabilityDecision
    /// The plugin's scoped storage container.
    var storageProvider: @Sendable (String) async throws -> PluginStorage
    /// Secrets storage.
    var secrets: PluginSecretsStore
    /// Current invocation assets.
    var invocations: PluginInvocationRegistry
  }

  /// The minimal plugin facts a service call needs.
  struct PluginBrokerRecord: Sendable {
    let identity: PluginIdentity
    let trust: TrustLevel
    let manifestCapabilities: [CapabilityRequest]

    func capabilityRequest(for id: CapabilityID) -> CapabilityRequest? {
      manifestCapabilities.first { $0.id == id }
    }
  }

  private let environment: Environment
  private let network = PluginNetworkService()
  private let ocr = PluginOCRService()
  private let image = PluginImageService()
  private let media = PluginMediaService()
  private let ui = PluginUIService()

  init(environment: Environment) {
    self.environment = environment
  }

  // MARK: - Entry point

  /// Processes one host call from the helper. Never throws: every failure
  /// returns a structured `HostCallResult` naming what was refused.
  func process(_ call: SnapzyPluginIPC.HostCall) async -> SnapzyPluginIPC.HostCallResult {
    let outcome: SnapzyPluginIPC.Outcome
    do {
      let result = try await dispatch(call)
      outcome = .success(result)
    } catch let error as PluginServiceError {
      outcome = .failure(code: error.code, message: error.message)
    } catch {
      outcome = .failure(code: "serviceError", message: "\(error)")
    }

    PluginRequestLog.shared.record(
      pluginID: call.pluginID,
      service: call.service,
      summary: redactedSummary(for: call),
      outcome: outcomeDescription(outcome)
    )

    return SnapzyPluginIPC.HostCallResult(callID: call.callID, outcome: outcome)
  }

  // MARK: - Dispatch

  private func dispatch(_ call: SnapzyPluginIPC.HostCall) async throws -> JSONValue {
    guard let record = await environment.pluginProvider(call.pluginID) else {
      throw PluginServiceError(code: "unknownPlugin", message: "The host does not know this plugin.")
    }

    let (capability, scopeFactory) = try capabilityMapping(for: call, record: record)

    // Manifest authority: the capability must be declared.
    guard let request = record.capabilityRequest(for: capability) else {
      throw PluginServiceError(
        code: "undeclared",
        message: "“\(record.identity.displayName)” did not declare the “\(capability.rawValue)” capability."
      )
    }

    // Policy + consent. The requested scope is the *declared* scope narrowed
    // by the call; the policy can only narrow it further.
    let callRequest = CapabilityRequest(
      id: request.id,
      scope: try scopeFactory(),
      required: request.required,
      reason: request.reason
    )
    let decision = await environment.decisionProvider(callRequest, record.identity, record.trust)
    guard let granted = decision.capability else {
      throw PluginServiceError(
        code: "denied",
        message: Self.denialMessage(for: decision, capability: capability)
      )
    }
    _ = granted

    // Per-call scope enforcement happens inside each service, which receives
    // the attenuated granted scope.
    return try await execute(call, record: record, grantedScope: grantedScope(of: decision))
  }

  private func grantedScope(of decision: CapabilityDecision) -> JSONValue {
    switch decision {
    case .granted: return .object([:])
    case .attenuated(_, _, let granted): return granted
    case .denied: return .object([:])
    }
  }

  private func capabilityMapping(
    for call: SnapzyPluginIPC.HostCall,
    record: PluginBrokerRecord
  ) throws -> (CapabilityID, () throws -> JSONValue) {
    switch call.service {
    case "http.fetch":
      let host = Self.hostForFetch(call.payload)
      return (
        SnapzyNetworkAccess.capabilityID,
        { .object(["hosts": .array([.string(host)])]) }
      )
    case "asset.read", "asset.thumbnail":
      guard let invocationID = call.invocationID else {
        throw PluginServiceError(code: "noInvocation", message: "Asset reads are only valid inside a command invocation.")
      }
      guard let kind = environment.invocations.kind(for: invocationID) else {
        throw PluginServiceError(code: "staleInvocation", message: "The invocation is no longer live.")
      }
      return (
        SnapzyAssetRead.capabilityID,
        { .object(["kinds": .array([.string(kind.rawValue)])]) }
      )
    case "ocr.recognize":
      return (SnapzyOCR.capabilityID, { .object([:]) })
    case "image.run":
      return (SnapzyImage.capabilityID, { .object([:]) })
    case "media.run":
      return (SnapzyMedia.capabilityID, { .object([:]) })
    case "ui.run":
      return (SnapzyUI.capabilityID, { .object([:]) })
    case "clipboard.writeText", "clipboard.writeImage":
      return (SnapzyClipboardWrite.capabilityID, { .object([:]) })
    case "storage.get", "storage.set":
      return (SnapzyStorage.capabilityID, { .object([:]) })
    case "secrets.get", "secrets.set":
      return (SnapzySecretsAccess.capabilityID, { .object([:]) })
    case "notify.post":
      return (SnapzyNotify.capabilityID, { .object([:]) })
    default:
      throw PluginServiceError(code: "unknownService", message: "“\(call.service)” is not a host service.")
    }
  }

  // MARK: - Execution

  private func execute(
    _ call: SnapzyPluginIPC.HostCall,
    record: PluginBrokerRecord,
    grantedScope: JSONValue
  ) async throws -> JSONValue {
    switch call.service {
    case "http.fetch":
      let request = try call.payload.decodeHostCallPayload(as: PluginHTTPRequest.self)
      let allowedHosts = Self.hosts(from: grantedScope)
      guard let response = try await network.fetch(request, allowedHosts: allowedHosts) else {
        throw PluginServiceError(code: "network", message: "The request could not be completed.")
      }
      return .object([
        "status": .int(response.status),
        "headers": .object(response.headers.mapValues { .string($0) }),
        "body": SnapzyPluginIPC.binary(response.body),
      ])

    case "asset.read":
      guard let invocationID = call.invocationID else {
        throw PluginServiceError(code: "noInvocation", message: "Asset reads are only valid inside a command invocation.")
      }
      let data = try await PluginAssetService.read(invocationID: invocationID, invocations: environment.invocations)
      return SnapzyPluginIPC.binary(data)

    case "asset.thumbnail":
      guard let invocationID = call.invocationID else {
        throw PluginServiceError(code: "noInvocation", message: "Asset reads are only valid inside a command invocation.")
      }
      let maxSize = call.payload.object?["maxSize"]?.int ?? 512
      let data = try await PluginAssetService.thumbnail(invocationID: invocationID, maxPixels: maxSize, invocations: environment.invocations)
      return SnapzyPluginIPC.binary(data)

    case "ocr.recognize":
      let request = try call.payload.decodeHostCallPayload(as: PluginOCRRequest.self)
      let result = try await ocr.recognize(request)
      let encoded = try JSONEncoder().encode(result)
      return try JSONDecoder().decode(JSONValue.self, from: encoded)

    case "image.run":
      let operation = try call.payload.decodeHostCallPayload(as: PluginImageOperation.self)
      let result = try await image.run(operation)
      // Built by hand rather than encoded: `Data` encodes as a bare base64
      // string, and the helper only converts the `{ "base64": … }` envelope
      // back into a Uint8Array.
      var payload: [String: JSONValue] = [
        "image": SnapzyPluginIPC.binary(result.image),
        "size": .object([
          "width": .double(result.size.width),
          "height": .double(result.size.height),
        ]),
      ]
      if let format = result.format {
        payload["format"] = .string(format)
      }
      return .object(payload)

    case "media.run":
      let operation = try call.payload.decodeHostCallPayload(as: PluginMediaOperation.self)
      guard let invocationID = call.invocationID,
        let assetURL = environment.invocations.assetURL(for: invocationID)
      else {
        throw PluginServiceError(code: "noInvocation", message: "Media operations are only valid inside a command invocation.")
      }
      let result = try await media.run(operation, assetURL: assetURL)
      var payload: [String: JSONValue] = [:]
      if let duration = result.duration { payload["duration"] = .double(duration) }
      if let size = result.size {
        payload["size"] = .object([
          "width": .double(size.width),
          "height": .double(size.height),
        ])
      }
      if let fps = result.fps { payload["fps"] = .double(fps) }
      if let image = result.image { payload["image"] = SnapzyPluginIPC.binary(image) }
      if let audio = result.audio { payload["audio"] = SnapzyPluginIPC.binary(audio) }
      return .object(payload)

    case "ui.run":
      let request = try call.payload.decodeHostCallPayload(as: PluginUIRequest.self)
      let result = try await ui.run(request)
      let encoded = try JSONEncoder().encode(result)
      return try JSONDecoder().decode(JSONValue.self, from: encoded)

    case "clipboard.writeText":
      let text = call.payload.string ?? ""
      try await MainActor.run {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
      }
      return .object([:])

    case "clipboard.writeImage":
      guard let data = SnapzyPluginIPC.binaryData(call.payload),
        let image = NSImage(data: data)
      else {
        throw PluginServiceError(code: "badPayload", message: "clipboard.writeImage needs image bytes.")
      }
      try await MainActor.run {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
      }
      return .object([:])

    case "storage.get":
      let key = call.payload.string ?? ""
      let storage = try await environment.storageProvider(call.pluginID)
      let data = try await storage.data(forKey: key)
      return data.map(SnapzyPluginIPC.binary) ?? .null

    case "storage.set":
      let key = call.payload.object?["key"]?.string ?? ""
      let value = call.payload.object?["value"].flatMap(SnapzyPluginIPC.binaryData)
      let storage = try await environment.storageProvider(call.pluginID)
      try await storage.setData(value, forKey: key)
      return .object([:])

    case "secrets.get":
      let name = call.payload.string ?? ""
      let value = try await environment.secrets.get(name: name, pluginID: call.pluginID)
      return value.map { .string($0) } ?? .null

    case "secrets.set":
      let name = call.payload.object?["name"]?.string ?? ""
      let value = call.payload.object?["value"]?.string
      try await environment.secrets.set(name: name, value: value, pluginID: call.pluginID)
      return .object([:])

    case "notify.post":
      let title = call.payload.object?["title"]?.string ?? ""
      let body = call.payload.object?["body"]?.string ?? ""
      _ = await SystemNotificationService.shared.post(title: title, body: body)
      return .object([:])

    default:
      throw PluginServiceError(code: "unknownService", message: "“\(call.service)” is not a host service.")
    }
  }

  // MARK: - Helpers

  private static func hostForFetch(_ payload: JSONValue) -> String {
    let raw = payload.object?["url"]?.string ?? ""
    return URL(string: raw)?.host?.lowercased() ?? raw.lowercased()
  }

  private static func hosts(from scope: JSONValue) -> [String] {
    guard case .object(let object) = scope, case .array(let values)? = object["hosts"] else { return [] }
    return values.compactMap { $0.string?.lowercased() }
  }

  private static func denialMessage(for decision: CapabilityDecision, capability: CapabilityID) -> String {
    switch decision {
    case .denied(.undeclared(let id)):
      return "The “\(id.rawValue)” capability was not declared."
    case .denied(.deniedByUser(let id)):
      return "You denied “\(id.rawValue)” for this plugin."
    case .denied(.deniedByPolicy(let id, let reason)):
      return "“\(id.rawValue)” is denied by policy: \(reason)"
    case .denied(.deniedByManagedPolicy(let id, let reason)):
      return "“\(id.rawValue)” is denied by managed policy: \(reason)"
    case .denied(.unavailable(let id)):
      return "The “\(id.rawValue)” capability does not exist on this host."
    case .denied(.scopeEmpty(let id)):
      return "Nothing of “\(id.rawValue)” remains after narrowing the request."
    case .denied(.scopeMalformed(let id, let reason)):
      return "The scope for “\(id.rawValue)” is malformed: \(reason)"
    default:
      return "The “\(capability.rawValue)” capability was denied."
    }
  }

  private func redactedSummary(for call: SnapzyPluginIPC.HostCall) -> String {
    switch call.service {
    case "http.fetch":
      let url = call.payload.object?["url"]?.string ?? "?"
      let method = call.payload.object?["method"]?.string ?? "GET"
      let headers = call.payload.object?["headers"]?.object?.keys.sorted().joined(separator: ",") ?? ""
      return "\(method) \(url) [headers: \(headers)]"
    case "asset.read", "asset.thumbnail":
      return "read the invocation asset"
    case "secrets.get", "secrets.set":
      return "<redacted>"
    case "storage.get", "storage.set":
      return "<redacted>"
    default:
      return call.service
    }
  }

  private func outcomeDescription(_ outcome: SnapzyPluginIPC.Outcome) -> String {
    switch outcome {
    case .success: return "ok"
    case .failure(let code, _): return code
    }
  }
}

struct PluginServiceError: Error {
  let code: String
  let message: String
}

// MARK: - JSONValue helpers

extension JSONValue {
  var string: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  var int: Int? {
    guard case .int(let value) = self else { return nil }
    return value
  }

  var object: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  /// Decodes a helper payload into its typed request.
  ///
  /// Named apart from PluginKitCore's own `decode(as:)` deliberately: this one
  /// unwraps binary envelopes first, and an overload that shadowed the
  /// framework's would apply that silently everywhere in the app.
  func decodeHostCallPayload<T: Decodable>(as type: T.Type) throws -> T {
    let data = try JSONEncoder().encode(normalizedBinaryEnvelopes)
    return try JSONDecoder().decode(type, from: data)
  }

  /// The helper marks bytes with the unambiguous `{ "base64": … }` envelope,
  /// but `Data`'s own `Codable` conformance reads a bare base64 string. This
  /// unwraps the envelope so a payload carrying bytes — `ocr.recognize`'s
  /// image, `http.fetch`'s body — decodes into its typed request instead of
  /// failing with a type mismatch.
  var normalizedBinaryEnvelopes: JSONValue {
    switch self {
    case .object(let members):
      if members.count == 1, case .string(let encoded)? = members["base64"] {
        return .string(encoded)
      }
      return .object(members.mapValues(\.normalizedBinaryEnvelopes))
    case .array(let items):
      return .array(items.map(\.normalizedBinaryEnvelopes))
    default:
      return self
    }
  }
}
