import Foundation
import SnapzyPluginAPI
import SnapzyPluginProtocol

// Both SnapzyPluginProtocol and (transitively, via SnapzyPluginAPI's
// @_exported PluginKitCore) export a type named JSONValue. The wire layer
// always means the protocol's own — the vocabulary's stays host-internal.
public typealias WireJSON = SnapzyPluginProtocol.JSONValue

/// The `activate` payload: the plugin's configuration as authored in the
/// settings schema — never a host-typed value.
struct ActivatePayload: Codable, Sendable, Equatable {
  var pluginID: String
  var options: WireJSON
}

/// Typed messages the host sends. Payload types are exactly the vocabulary
/// the script runtime already speaks, so `PluginServiceBroker.process(_:)`
/// and the document bridge can be reused verbatim (decision D5).
public enum HostMessage: Sendable, Equatable {
  case handshake(HandshakeRequest)
  case activate(pluginID: String, options: WireJSON)
  case invoke(SnapzyPluginIPC.CommandRequest)
  case cancel(SnapzyPluginIPC.CancelRequest)
  case deactivate(SnapzyPluginIPC.DeactivateRequest)
  case healthCheck(SnapzyPluginIPC.HealthRequest)

  public var kind: String {
    switch self {
    case .handshake: return MessageKind.handshake
    case .activate: return MessageKind.activate
    case .invoke: return MessageKind.invoke
    case .cancel: return MessageKind.cancel
    case .deactivate: return MessageKind.deactivate
    case .healthCheck: return MessageKind.healthCheck
    }
  }

  /// Encodes to the wire shape `(kind, payload)` where payload is JSON.
  /// Throws `ProtocolError.malformedJSON` if a payload cannot encode —
  /// which should be impossible for the vocabulary types, so it is a
  /// programming error worth surfacing loudly rather than papering over.
  public func encode() throws -> (kind: String, payload: WireJSON) {
    switch self {
    case .handshake(let request):
      return (kind, try JSONValueCodec.encode(request))
    case .activate(let pluginID, let options):
      return (kind, try JSONValueCodec.encode(ActivatePayload(pluginID: pluginID, options: options)))
    case .invoke(let request):
      return (kind, try JSONValueCodec.encode(request))
    case .cancel(let request):
      return (kind, try JSONValueCodec.encode(request))
    case .deactivate(let request):
      return (kind, try JSONValueCodec.encode(request))
    case .healthCheck(let request):
      return (kind, try JSONValueCodec.encode(request))
    }
  }

  /// Decodes an incoming envelope payload. Unknown kinds throw
  /// `ProtocolError.unknownMessageKind` so the caller can log-and-ignore
  /// (forward compatibility) rather than crash.
  public static func decode(kind: String, payload: WireJSON) throws -> HostMessage {
    switch kind {
    case MessageKind.handshake:
      return .handshake(try JSONValueCodec.decode(HandshakeRequest.self, from: payload))
    case MessageKind.activate:
      let decoded = try JSONValueCodec.decode(ActivatePayload.self, from: payload)
      return .activate(pluginID: decoded.pluginID, options: decoded.options)
    case MessageKind.invoke:
      return .invoke(try JSONValueCodec.decode(SnapzyPluginIPC.CommandRequest.self, from: payload))
    case MessageKind.cancel:
      return .cancel(try JSONValueCodec.decode(SnapzyPluginIPC.CancelRequest.self, from: payload))
    case MessageKind.deactivate:
      return .deactivate(try JSONValueCodec.decode(SnapzyPluginIPC.DeactivateRequest.self, from: payload))
    case MessageKind.healthCheck:
      return .healthCheck(try JSONValueCodec.decode(SnapzyPluginIPC.HealthRequest.self, from: payload))
    default:
      throw ProtocolError.unknownMessageKind(kind)
    }
  }
}

/// Messages the plugin sends.
public enum PluginMessage: Sendable, Equatable {
  case handshakeAck(HandshakeAck)
  case hostCall(SnapzyPluginIPC.HostCall)
  case progress(SnapzyPluginIPC.ProgressUpdate)
  case log(PluginLogEntry)
  case result(SnapzyPluginIPC.CommandResponse)
  case hostCallReply(SnapzyPluginIPC.HostCallResult)

  public var kind: String {
    switch self {
    case .handshakeAck: return MessageKind.handshakeAck
    case .hostCall: return MessageKind.hostCall
    case .progress: return MessageKind.progress
    case .log: return MessageKind.log
    case .result: return MessageKind.result
    case .hostCallReply: return MessageKind.hostCallReply
    }
  }

  public func encode() throws -> (kind: String, payload: WireJSON) {
    switch self {
    case .handshakeAck(let ack):
      return (kind, try JSONValueCodec.encode(ack))
    case .hostCall(let call):
      return (kind, try JSONValueCodec.encode(call))
    case .progress(let update):
      return (kind, try JSONValueCodec.encode(update))
    case .log(let entry):
      return (kind, try JSONValueCodec.encode(entry))
    case .result(let response):
      return (kind, try JSONValueCodec.encode(response))
    case .hostCallReply(let result):
      return (kind, try JSONValueCodec.encode(result))
    }
  }

  public static func decode(kind: String, payload: WireJSON) throws -> PluginMessage {
    switch kind {
    case MessageKind.handshakeAck:
      return .handshakeAck(try JSONValueCodec.decode(HandshakeAck.self, from: payload))
    case MessageKind.hostCall:
      return .hostCall(try JSONValueCodec.decode(SnapzyPluginIPC.HostCall.self, from: payload))
    case MessageKind.progress:
      return .progress(try JSONValueCodec.decode(SnapzyPluginIPC.ProgressUpdate.self, from: payload))
    case MessageKind.log:
      return .log(try JSONValueCodec.decode(PluginLogEntry.self, from: payload))
    case MessageKind.result:
      return .result(try JSONValueCodec.decode(SnapzyPluginIPC.CommandResponse.self, from: payload))
    case MessageKind.hostCallReply:
      return .hostCallReply(try JSONValueCodec.decode(SnapzyPluginIPC.HostCallResult.self, from: payload))
    default:
      throw ProtocolError.unknownMessageKind(kind)
    }
  }
}
