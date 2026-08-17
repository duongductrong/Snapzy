import Foundation
import Testing
import PluginKitCore
import SnapzyPluginAPI
import SnapzyPluginMessages
import SnapzyPluginProtocol

// The API vocabulary carries PluginKitCore.JSONValue in its payload types;
// the wire carries SnapzyPluginProtocol.JSONValue. Never the twain, untyped.
private typealias APIJSON = PluginKitCore.JSONValue
private typealias WireJSON = SnapzyPluginProtocol.JSONValue

@Suite struct MessageCodecTests {
  private func roundTripHost(_ message: HostMessage) throws {
    let (kind, payload) = try message.encode()
    let decoded = try HostMessage.decode(kind: kind, payload: payload)
    #expect(decoded == message)
  }

  private func roundTripPlugin(_ message: PluginMessage) throws {
    let (kind, payload) = try message.encode()
    let decoded = try PluginMessage.decode(kind: kind, payload: payload)
    #expect(decoded == message)
  }

  @Test func hostMessageRoundTrips() throws {
    try roundTripHost(.handshake(HandshakeRequest(
      protocolVersion: .current,
      host: HostInfo(appVersion: "1.33.0", appBuild: "133", osVersion: "26.6", hostID: "test"),
      contracts: .object(["com.snapzy.api": .string("1.0.0")])
    )))
    try roundTripHost(.activate(pluginID: "com.example.x", options: .object(["tone": .string("formal")])))
    try roundTripHost(.invoke(SnapzyPluginIPC.CommandRequest(
      invocationID: UUID(),
      request: APIJSON.object(["annotate": APIJSON.object(["width": .int(1)])])
    )))
    try roundTripHost(.cancel(SnapzyPluginIPC.CancelRequest(invocationID: UUID())))
    try roundTripHost(.deactivate(SnapzyPluginIPC.DeactivateRequest(pluginID: "com.example.x")))
    try roundTripHost(.healthCheck(SnapzyPluginIPC.HealthRequest(pluginID: "com.example.x")))
  }

  @Test func pluginMessageRoundTrips() throws {
    try roundTripPlugin(.handshakeAck(HandshakeAck(
      protocolVersion: .current,
      sdkVersion: "1.0.0",
      declaredContracts: .array([.object(["vocabulary": .string("com.snapzy.api")])]),
      sandboxSelfCheck: SandboxSelfCheckReport(
        networkDenied: true, fileSystemDenied: true,
        screenCaptureDenied: false, keychainDenied: false,
        diagnostics: ["macOS 26 permits screen capture in sandbox"]
      )
    )))
    try roundTripPlugin(.hostCall(SnapzyPluginIPC.HostCall(
      callID: UUID(), pluginID: "com.example.x", invocationID: UUID(),
      service: "http.fetch", payload: APIJSON.object(["url": .string("https://example.com")])
    )))
    try roundTripPlugin(.progress(SnapzyPluginIPC.ProgressUpdate(
      invocationID: UUID(), fraction: 0.5, message: "half"
    )))
    try roundTripPlugin(.log(PluginLogEntry(level: "info", message: "hello", invocationID: UUID())))
    try roundTripPlugin(.result(SnapzyPluginIPC.CommandResponse(
      invocationID: UUID(), outcome: .success(APIJSON.object(["text": .string("ok")]))
    )))
    try roundTripPlugin(.result(SnapzyPluginIPC.CommandResponse(
      invocationID: UUID(), outcome: .failure(code: "denied", message: "no network grant")
    )))
    try roundTripPlugin(.hostCallReply(SnapzyPluginIPC.HostCallResult(
      callID: UUID(), outcome: .success(APIJSON.object(["status": .int(200)]))
    )))
  }

  @Test func hostCallShapeSurvivesByteForByte() throws {
    // D5: the broker switches on `call.service` and `call.args`. If this
    // payload shape drifts, the broker path breaks — this test is the
    // canary.
    let call = SnapzyPluginIPC.HostCall(
      callID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
      pluginID: "com.snapzy.translate",
      invocationID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
      service: "ocr.recognize",
      payload: APIJSON.object(["image": APIJSON.object(["base64": .string("QUJD")])])
    )
    let (kind, payload) = try PluginMessage.hostCall(call).encode()
    #expect(kind == MessageKind.hostCall)
    let decoded = try PluginMessage.decode(kind: kind, payload: payload)
    #expect(decoded == .hostCall(call))
    // The raw JSON keys the broker reads are present, spelled exactly.
    guard case .object(let entries) = payload else {
      Issue.record("payload not an object")
      return
    }
    #expect(entries["callID"] != nil)
    #expect(entries["pluginID"] == .string("com.snapzy.translate"))
    #expect(entries["service"] == .string("ocr.recognize"))
    #expect(entries["payload"] == .object(["image": .object(["base64": .string("QUJD")])]))
  }

  @Test func unknownKindsThrow() throws {
    #expect(throws: ProtocolError.unknownMessageKind("hostCallV2")) {
      try HostMessage.decode(kind: "hostCallV2", payload: .null)
    }
    #expect(throws: ProtocolError.unknownMessageKind("invokeV2")) {
      try PluginMessage.decode(kind: "invokeV2", payload: .null)
    }
  }

  @Test func malformedPayloadThrows() throws {
    #expect(throws: ProtocolError.malformedJSON) {
      try PluginMessage.decode(kind: MessageKind.hostCall, payload: .string("not-an-object"))
    }
  }
}
