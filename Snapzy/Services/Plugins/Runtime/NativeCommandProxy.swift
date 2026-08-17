import Foundation
import PluginKitCore
import SnapzyPluginAPI
import SnapzyPluginMessages
import SnapzyPluginProtocol

enum PluginCommandError: Error, LocalizedError {
  case pluginFailed(code: String, message: String)
  case timedOut
  case cancelled

  var userMessage: String {
    switch self {
    case .pluginFailed(_, let message):
      return message
    case .timedOut:
      return "The plugin command timed out."
    case .cancelled:
      return "The plugin command was cancelled."
    }
  }

  var errorDescription: String? {
    switch self {
    case .pluginFailed(let code, let message):
      return "\(message) (\(code))"
    case .timedOut:
      return "The plugin command timed out."
    case .cancelled:
      return "The plugin command was cancelled."
    }
  }
}

final class NativeCommandProxy: SnapzyCommand, @unchecked Sendable {
  private let pluginID: String
  private let channel: FrameChannel
  private let isLongRunning: Bool

  init(
    pluginID: String,
    channel: FrameChannel,
    isLongRunning: Bool = false
  ) {
    self.pluginID = pluginID
    self.channel = channel
    self.isLongRunning = isLongRunning
  }

  func cancel(invocationID: UUID) {
    let cancelMsg = HostMessage.cancel(SnapzyPluginIPC.CancelRequest(invocationID: invocationID))
    if let (cKind, cPayload) = try? cancelMsg.encode() {
      Task {
        _ = try? await self.channel.fire(cKind, payload: cPayload)
      }
    }
  }

  func handle(_ request: SnapzyCommandRequest) async throws -> SnapzyCommandResponse {
    let deadline = isLongRunning ? PluginProcessLimits.longRunningDeadline : PluginProcessLimits.defaultDeadline

    let reqData = try JSONEncoder().encode(request)
    let reqJSON = try JSONDecoder().decode(PluginKitCore.JSONValue.self, from: reqData)
    let cmdRequest = SnapzyPluginIPC.CommandRequest(
      invocationID: request.invocationID,
      request: reqJSON
    )
    let hostMsg = HostMessage.invoke(cmdRequest)
    let (kind, payload) = try hostMsg.encode()

    return try await withThrowingTaskGroup(of: SnapzyCommandResponse.self) { group in
      group.addTask {
        let replyEnvelope = try await self.channel.request(kind, payload: payload)
        let replyMsg = try PluginMessage.decode(kind: replyEnvelope.kind, payload: replyEnvelope.payload)
        guard case .result(let response) = replyMsg else {
          throw PluginCommandError.pluginFailed(code: "protocol", message: "Expected command result envelope")
        }
        switch response.outcome {
        case .success(let json):
          let data = try JSONEncoder().encode(json)
          return try JSONDecoder().decode(SnapzyCommandResponse.self, from: data)
        case .failure(let code, let message):
          throw PluginCommandError.pluginFailed(code: code, message: message)
        }
      }
      group.addTask {
        try await Task.sleep(for: deadline)
        throw PluginCommandError.timedOut
      }

      do {
        let result = try await group.next()!
        group.cancelAll()
        return result
      } catch {
        group.cancelAll()
        let cancelMsg = HostMessage.cancel(SnapzyPluginIPC.CancelRequest(invocationID: request.invocationID))
        if let (cKind, cPayload) = try? cancelMsg.encode() {
          _ = try? await self.channel.fire(cKind, payload: cPayload)
        }
        throw error
      }
    }
  }
}
