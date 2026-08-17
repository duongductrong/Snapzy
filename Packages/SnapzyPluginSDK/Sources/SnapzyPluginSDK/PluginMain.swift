import Darwin
import Foundation
import PluginKitCore
import SnapzyPluginAPI
import SnapzyPluginMessages
import SnapzyPluginProtocol

public extension SnapzyPlugin {
  static func main() async {
    await PluginRunner<Self>.run()
  }
}

public enum PluginRunner<P: SnapzyPlugin> {
  public static func run(channelFD: Int32 = 3) async {
    let channel = FrameChannel(
      readFD: channelFD,
      writeFD: channelFD,
      parity: .odd,
      label: "plugin.runner"
    )
    await channel.start()

    let plugin = P()
    let registry = CommandRegistry()
    var activeTasks: [UUID: Task<Void, Never>] = [:]
    var pluginContext: SnapzyPluginContext?

    let dispatcher = WireHostCallDispatcher(channel: channel)

    var iterator = await channel.events.makeAsyncIterator()

    while let event = await iterator.next() {
      let envelope = event.envelope
      do {
        let message = try HostMessage.decode(kind: envelope.kind, payload: envelope.payload)
        switch message {
        case .handshake:
          let selfCheck = SandboxSelfCheck.run()
          let declaredContracts: SnapzyPluginProtocol.JSONValue = .array([
            .object([
              "vocabulary": .string("com.snapzy.api"),
              "version": .string("1.0.0")
            ])
          ])
          let ack = HandshakeAck(
            protocolVersion: ProtocolVersion.current,
            sdkVersion: "1.0.0",
            declaredContracts: declaredContracts,
            sandboxSelfCheck: selfCheck
          )
          let ackMsg = PluginMessage.handshakeAck(ack)
          let (kind, payload) = try ackMsg.encode()
          try await channel.reply(to: envelope.id, kind: kind, payload: payload)

        case .activate(let pluginID, let options):
          let hostInfo = SnapzyPluginProtocol.HostInfo(
            appVersion: "1.0.0",
            appBuild: "1",
            osVersion: "macOS",
            hostID: "snapzy"
          )
          let optionsData = try options.encodeData()
          let coreOptions = (try? JSONDecoder().decode(PluginKitCore.JSONValue.self, from: optionsData)) ?? .object([:])
          let ctx = SnapzyPluginContext(
            pluginID: pluginID,
            host: hostInfo,
            configuration: coreOptions,
            commandRegistry: registry
          )
          pluginContext = ctx
          try await plugin.activate(ctx)
          let replyMsg = PluginMessage.result(SnapzyPluginIPC.CommandResponse(
            invocationID: UUID(),
            outcome: .success(.object([:]))
          ))
          let (kind, payload) = try replyMsg.encode()
          try await channel.reply(to: envelope.id, kind: kind, payload: payload)

        case .invoke(let cmdReq):
          guard let ctx = pluginContext else {
            let replyMsg = PluginMessage.result(SnapzyPluginIPC.CommandResponse(
              invocationID: cmdReq.invocationID,
              outcome: .failure(code: "notActivated", message: "Plugin was not activated")
            ))
            let (kind, payload) = try replyMsg.encode()
            try await channel.reply(to: envelope.id, kind: kind, payload: payload)
            continue
          }

          let invocationID = cmdReq.invocationID
          let reqData = try JSONEncoder().encode(cmdReq.request)
          let snapzyReq = try JSONDecoder().decode(SnapzyCommandRequest.self, from: reqData)

          let task: Task<Void, Never> = Task {
            do {
              guard let handler = registry.defaultHandler else {
                throw SnapzyPluginError.failed("No handler registered for command")
              }
              let cmdCtx = CommandContext(
                pluginID: ctx.pluginID,
                invocationID: invocationID,
                request: snapzyReq,
                dispatcher: dispatcher
              )
              let outcome = try await handler(snapzyReq, cmdCtx)
              let resp = outcome.toResponse()
              let respJSON = try JSONDecoder().decode(PluginKitCore.JSONValue.self, from: JSONEncoder().encode(resp))
              let replyMsg = PluginMessage.result(SnapzyPluginIPC.CommandResponse(
                invocationID: invocationID,
                outcome: .success(respJSON)
              ))
              let (kind, payload) = try replyMsg.encode()
              try await channel.reply(to: envelope.id, kind: kind, payload: payload)
            } catch is CancellationError {
              let replyMsg = PluginMessage.result(SnapzyPluginIPC.CommandResponse(
                invocationID: invocationID,
                outcome: .failure(code: "cancelled", message: "Operation was cancelled")
              ))
              if let (kind, payload) = try? replyMsg.encode() {
                try? await channel.reply(to: envelope.id, kind: kind, payload: payload)
              }
            } catch {
              let replyMsg = PluginMessage.result(SnapzyPluginIPC.CommandResponse(
                invocationID: invocationID,
                outcome: .failure(code: "failed", message: error.localizedDescription)
              ))
              if let (kind, payload) = try? replyMsg.encode() {
                try? await channel.reply(to: envelope.id, kind: kind, payload: payload)
              }
            }
          }
          activeTasks[invocationID] = task

        case .cancel(let cancelReq):
          if let task = activeTasks.removeValue(forKey: cancelReq.invocationID) {
            task.cancel()
          }

        case .deactivate:
          await plugin.deactivate()
          await channel.close()
          return

        case .healthCheck:
          let healthy = await plugin.healthCheck()
          let resp = SnapzyPluginIPC.HealthResponse(status: healthy ? "ok" : "unresponsive")
          let respJSON = try JSONDecoder().decode(PluginKitCore.JSONValue.self, from: JSONEncoder().encode(resp))
          let replyMsg = PluginMessage.result(SnapzyPluginIPC.CommandResponse(
            invocationID: UUID(),
            outcome: .success(respJSON)
          ))
          let (kind, payload) = try replyMsg.encode()
          try await channel.reply(to: envelope.id, kind: kind, payload: payload)
        }
      } catch {
        // Ignore unhandled protocol envelope
      }
    }
  }
}

final class WireHostCallDispatcher: HostCallDispatcher {
  private let channel: FrameChannel

  init(channel: FrameChannel) {
    self.channel = channel
  }

  func call(
    pluginID: String,
    invocationID: UUID?,
    service: String,
    payload: PluginKitCore.JSONValue
  ) async throws -> PluginKitCore.JSONValue {
    let callID = UUID()
    let hostCall = SnapzyPluginIPC.HostCall(
      callID: callID,
      pluginID: pluginID,
      invocationID: invocationID,
      service: service,
      payload: payload
    )
    let callMsg = PluginMessage.hostCall(hostCall)
    let (kind, callPayload) = try callMsg.encode()
    let reply = try await channel.request(kind, payload: callPayload)
    let replyMsg = try PluginMessage.decode(kind: reply.kind, payload: reply.payload)
    guard case .hostCallReply(let result) = replyMsg else {
      throw SnapzyPluginError.hostCallFailed("Unexpected reply kind: \(reply.kind)")
    }
    switch result.outcome {
    case .success(let value):
      return value
    case .failure(let code, let message):
      if code == "denied" || code == "undeclared" {
        throw SnapzyPluginError.denied(capability: service, reason: message)
      } else {
        throw SnapzyPluginError.hostCallFailed(message)
      }
    }
  }

  func progress(invocationID: UUID, fraction: Double?, message: String?) async throws {
    let update = SnapzyPluginIPC.ProgressUpdate(
      invocationID: invocationID,
      fraction: fraction,
      message: message
    )
    let msg = PluginMessage.progress(update)
    let (kind, payload) = try msg.encode()
    try await channel.fire(kind, payload: payload)
  }

  func log(level: String, message: String, invocationID: UUID?) async throws {
    let entry = PluginLogEntry(level: level, message: message, invocationID: invocationID)
    let msg = PluginMessage.log(entry)
    let (kind, payload) = try msg.encode()
    try await channel.fire(kind, payload: payload)
  }
}
