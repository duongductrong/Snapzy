import Foundation
import os
import PluginKitCore
import SnapzyPluginAPI
import SnapzyPluginMessages
import SnapzyPluginProtocol
import SnapzyPluginSDK

public final class FakeHost: HostCallDispatcher, @unchecked Sendable {
  public struct RecordedCall: Sendable, Equatable {
    public let service: String
    public let payload: PluginKitCore.JSONValue
    public let invocationID: UUID?

    public init(service: String, payload: PluginKitCore.JSONValue, invocationID: UUID?) {
      self.service = service
      self.payload = payload
      self.invocationID = invocationID
    }
  }

  public typealias StubHandler = @Sendable (PluginKitCore.JSONValue) async throws -> PluginKitCore.JSONValue

  private let lock = NSLock()
  private var stubs: [String: StubHandler] = [:]
  private var secrets: [String: String] = [:]
  private var storage: [String: String] = [:]
  private var recordedCalls: [RecordedCall] = []
  private var recordedProgress: [SnapzyPluginIPC.ProgressUpdate] = []
  private var recordedLogs: [PluginLogEntry] = []

  public init() {}

  private func withLock<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  public func stub(service: String, handler: @escaping StubHandler) {
    withLock {
      stubs[service] = handler
    }
  }

  public func registerAsset(_ data: Data) {
    stubAsset(data)
  }

  public func stubAsset(_ data: Data) {
    stub(service: "asset.read") { _ in
      SnapzyPluginIPC.binary(data)
    }
  }

  public func registerSecret(key: String, value: String) {
    withLock {
      secrets[key] = value
    }
  }

  public func getSecret(key: String) -> String? {
    withLock {
      secrets[key]
    }
  }

  public func registerUIFormResponse(_ response: [String: PluginKitCore.JSONValue]) {
    stub(service: "ui.run") { _ in
      let uiResult = PluginUIResult.submitted(.object(response))
      let data = try JSONEncoder().encode(uiResult)
      return try JSONDecoder().decode(PluginKitCore.JSONValue.self, from: data)
    }
  }

  public func stubOCR(lines: [String]) {
    stub(service: "ocr.recognize") { _ in
      let ocrLines = lines.enumerated().map { i, text in
        PluginOCRLine(
          text: text,
          box: SnapzyRect(x: 10, y: Double(i * 30 + 10), width: 200, height: 25),
          confidence: 0.99
        )
      }
      let result = PluginOCRResult(lines: ocrLines, text: lines.joined(separator: "\n"))
      let data = try JSONEncoder().encode(result)
      return try JSONDecoder().decode(PluginKitCore.JSONValue.self, from: data)
    }
  }

  public func registerHTTPResponse(status: Int = 200, headers: [String: String] = [:], body: Data) {
    stubHTTP(status: status, headers: headers, body: body)
  }

  public func stubHTTP(status: Int = 200, headers: [String: String] = [:], body: Data) {
    stub(service: "http.fetch") { _ in
      .object([
        "status": .int(status),
        "headers": .object(headers.mapValues { .string($0) }),
        "body": SnapzyPluginIPC.binary(body)
      ])
    }
  }

  public var calls: [RecordedCall] {
    withLock { recordedCalls }
  }

  public var progressUpdates: [SnapzyPluginIPC.ProgressUpdate] {
    withLock { recordedProgress }
  }

  public var logs: [PluginLogEntry] {
    withLock { recordedLogs }
  }

  // MARK: - HostCallDispatcher Conformance

  public func call(
    pluginID: String,
    invocationID: UUID?,
    service: String,
    payload: PluginKitCore.JSONValue
  ) async throws -> PluginKitCore.JSONValue {
    let handler = withLock { () -> StubHandler? in
      recordedCalls.append(RecordedCall(service: service, payload: payload, invocationID: invocationID))
      return stubs[service]
    }

    if let handler = handler {
      return try await handler(payload)
    }

    // Default stub implementations for basic services
    switch service {
    case "secrets.get":
      let key = payload["name"]?.stringValue ?? payload["key"]?.stringValue ?? ""
      let val = withLock { secrets[key] }
      return .object(["value": val.map { .string($0) } ?? .null])
    case "secrets.set":
      let key = payload["name"]?.stringValue ?? payload["key"]?.stringValue ?? ""
      let val = payload["value"]?.stringValue ?? ""
      withLock { secrets[key] = val }
      return .object([:])
    case "storage.get":
      let key = payload["key"]?.stringValue ?? ""
      let val = withLock { storage[key] }
      let binVal = val.flatMap { $0.data(using: .utf8) }.map { SnapzyPluginIPC.binary($0) } ?? .null
      return .object(["value": binVal])
    case "storage.set":
      let key = payload["key"]?.stringValue ?? ""
      let binVal = payload["value"]
      let val = binVal.flatMap { SnapzyPluginIPC.binaryData($0) }.flatMap { String(data: $0, encoding: .utf8) }
      withLock { storage[key] = val }
      return .object([:])
    case "clipboard.writeText", "clipboard.writeImage", "notify.post":
      return .object([:])
    default:
      throw SnapzyPluginError.denied(capability: service, reason: "No stub configured for \(service)")
    }
  }

  public func progress(invocationID: UUID, fraction: Double?, message: String?) async throws {
    withLock {
      recordedProgress.append(SnapzyPluginIPC.ProgressUpdate(
        invocationID: invocationID,
        fraction: fraction,
        message: message
      ))
    }
  }

  public func log(level: String, message: String, invocationID: UUID?) async throws {
    withLock {
      recordedLogs.append(PluginLogEntry(level: level, message: message, invocationID: invocationID))
    }
  }
}
