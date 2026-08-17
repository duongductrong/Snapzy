import Darwin
import Foundation
import PluginKitCore
import PluginKitHost
import SnapzyPluginAPI
import SnapzyPluginMessages
import SnapzyPluginProtocol

final class PluginProcessSupervisor: @unchecked Sendable {
  struct ProcessRecord {
    let pid: pid_t
    let channel: FrameChannel
    let workerTask: Task<Void, Never>
  }

  private let lock = NSLock()
  private var processes: [String: ProcessRecord] = [:]
  private let broker: PluginServiceBroker
  private let progressHandler: @Sendable (SnapzyPluginIPC.ProgressUpdate) -> Void

  init(
    broker: PluginServiceBroker,
    progressHandler: @escaping @Sendable (SnapzyPluginIPC.ProgressUpdate) -> Void
  ) {
    self.broker = broker
    self.progressHandler = progressHandler
  }

  func connection(
    for pluginID: String,
    executableURL: URL,
    manifest: PluginManifest,
    options: PluginKitCore.JSONValue
  ) async throws -> FrameChannel {
    lock.lock()
    if let existing = processes[pluginID] {
      lock.unlock()
      return existing.channel
    }
    lock.unlock()

    var fds: [Int32] = [0, 0]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
      throw PluginKitError.runtime(.instantiationFailed(
        PluginID(pluginID),
        reason: "socketpair failed with errno \(errno)"
      ))
    }

    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }

    // Close host fd in child, then duplicate child fd to fd 3
    posix_spawn_file_actions_addclose(&actions, fds[0])
    posix_spawn_file_actions_adddup2(&actions, fds[1], 3)

    let path = executableURL.path
    let cPath = path.cString(using: .utf8)!
    var argv: [UnsafeMutablePointer<CChar>?] = [
      strdup(cPath),
      nil
    ]
    defer {
      for ptr in argv where ptr != nil {
        free(ptr)
      }
    }

    var pid: pid_t = 0
    let spawnStatus = posix_spawn(&pid, cPath, &actions, &attr, &argv, environ)
    close(fds[1]) // Host closes child side

    guard spawnStatus == 0 else {
      close(fds[0])
      throw PluginKitError.runtime(.instantiationFailed(
        PluginID(pluginID),
        reason: "posix_spawn failed with error \(spawnStatus)"
      ))
    }

    // Set non-blocking on host fd
    let flags = fcntl(fds[0], F_GETFL, 0)
    _ = fcntl(fds[0], F_SETFL, flags | O_NONBLOCK)

    let channel = FrameChannel(
      readFD: fds[0],
      writeFD: fds[0],
      parity: .even,
      label: "host.process.\(pluginID)"
    )
    await channel.start()

    // Handshake
    let hostInfo = HostInfo(
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
      appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1",
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      hostID: "snapzy"
    )
    let contractsJSON: SnapzyPluginProtocol.JSONValue = .object([
      "com.snapzy.api": .string("1.0.0")
    ])
    let handshakeReq = HandshakeRequest(
      protocolVersion: ProtocolVersion.current,
      host: hostInfo,
      contracts: contractsJSON
    )
    let hostMsg = HostMessage.handshake(handshakeReq)
    let (kind, payload) = try hostMsg.encode()

    let ackEnvelope = try await channel.request(kind, payload: payload)
    let ackMsg = try PluginMessage.decode(kind: ackEnvelope.kind, payload: ackEnvelope.payload)
    guard case .handshakeAck(let ack) = ackMsg else {
      await channel.close()
      kill(pid, SIGTERM)
      throw PluginKitError.runtime(.activationFailed(
        PluginID(pluginID),
        reason: "Expected handshakeAck, received \(ackEnvelope.kind)"
      ))
    }
    _ = ack

    // Activate
    let activateOptionsData = try JSONEncoder().encode(options)
    let wireOptions = try SnapzyPluginProtocol.JSONValue.parse(activateOptionsData)
    let activateMsg = HostMessage.activate(pluginID: pluginID, options: wireOptions)
    let (actKind, actPayload) = try activateMsg.encode()
    _ = try await channel.request(actKind, payload: actPayload)

    // Message loop worker
    let broker = self.broker
    let progressHandler = self.progressHandler
    let workerTask = Task { [channel] in
      var iterator = await channel.events.makeAsyncIterator()
      while let event = await iterator.next() {
        let envelope = event.envelope
        guard let msg = try? PluginMessage.decode(kind: envelope.kind, payload: envelope.payload) else {
          continue
        }
        switch msg {
        case .hostCall(let call):
          let result = await broker.process(call)
          let replyMsg = PluginMessage.hostCallReply(result)
          if let (rKind, rPayload) = try? replyMsg.encode() {
            try? await channel.reply(to: envelope.id, kind: rKind, payload: rPayload)
          }
        case .progress(let update):
          progressHandler(update)
        case .log(let entry):
          DiagnosticLogger.shared.log(
            .info, .plugin,
            "[\(pluginID)] \(entry.message)"
          )
        default:
          break
        }
      }
    }

    let record = ProcessRecord(pid: pid, channel: channel, workerTask: workerTask)
    lock.lock()
    processes[pluginID] = record
    lock.unlock()

    return channel
  }

  func deactivate(pluginID: String) async {
    let record: ProcessRecord?
    lock.lock()
    record = processes.removeValue(forKey: pluginID)
    lock.unlock()

    guard let record else { return }
    record.workerTask.cancel()

    let deactMsg = HostMessage.deactivate(SnapzyPluginIPC.DeactivateRequest(pluginID: pluginID))
    if let (kind, payload) = try? deactMsg.encode() {
      _ = try? await record.channel.request(kind, payload: payload)
    }

    await record.channel.close()

    // Wait or SIGTERM
    kill(record.pid, SIGTERM)
    var status: Int32 = 0
    waitpid(record.pid, &status, WNOHANG)
  }

  func reapIdle() async {
    // Process reaping if needed
  }
}
