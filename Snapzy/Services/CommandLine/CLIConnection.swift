//
//  CLIConnection.swift
//  Snapzy
//
//  One `snapzy` CLI client on the socket. Requires the same user ID as
//  Snapzy, a `hello` handshake first, and processes requests one at a time.
//  All state is confined to the connection's serial queue.
//

import Darwin
import Foundation
import SnapzyCLIProtocol

final nonisolated class CLIConnection: @unchecked Sendable {
  static let handshakeTimeout: TimeInterval = 5
  static let idleTimeout: TimeInterval = 60
  static let writeTimeout: TimeInterval = 5

  let id = UUID()

  private let descriptor: Int32
  private let hello: HelloResponse
  private let router: CLIRequestRouter
  private let authorizer: CLIAuthorizing
  private let resolveCaller: @Sendable (pid_t?) -> CLICallerIdentity?
  private let onClose: @Sendable (CLIConnection) -> Void
  private let queue: DispatchQueue

  private var readSource: DispatchSourceRead?
  private var timeoutTimer: DispatchSourceTimer?
  private var decoder = FrameDecoder()
  private var pendingPayloads: [Data] = []
  private var isProcessing = false
  private var isHandshaken = false
  private var isClosed = false
  private var peerPID: pid_t?
  private var caller: CLICallerIdentity?
  private var isAllowedForConnection = false
  /// The request being handled; cancelled on close so a pending approval
  /// prompt for a client that went away is never shown.
  private var inFlightRequest: Task<Void, Never>?

  init(
    descriptor: Int32,
    hello: HelloResponse,
    router: CLIRequestRouter,
    authorizer: CLIAuthorizing,
    resolveCaller: @escaping @Sendable (pid_t?) -> CLICallerIdentity?,
    onClose: @escaping @Sendable (CLIConnection) -> Void
  ) {
    self.descriptor = descriptor
    self.hello = hello
    self.router = router
    self.authorizer = authorizer
    self.resolveCaller = resolveCaller
    self.onClose = onClose
    queue = DispatchQueue(label: "com.trongduong.snapzy.cli.connection")
  }

  func start() {
    queue.async { self.startOnQueue() }
  }

  func close() {
    queue.async { self.closeOnQueue(reason: "server stopped") }
  }

  /// Answers an over-capacity client with `busy` instead of letting the
  /// listen backlog refuse it: the CLI reads ECONNREFUSED as "app not listening".
  static func rejectBusy(descriptor: Int32) {
    configure(descriptor)
    let error = CLIError(.busy, "Too many snapzy commands are running", hint: "Retry when the others finish")
    _ = write(CLIRequestRouter.encode(error, id: 0), to: descriptor)
    Darwin.close(descriptor)
  }

  // MARK: - Lifecycle

  private func startOnQueue() {
    var userID: uid_t = 0
    var groupID: gid_t = 0
    guard getpeereid(descriptor, &userID, &groupID) == 0, userID == getuid() else {
      DiagnosticLogger.shared.log(.warning, .cli, "Rejected CLI client from another user")
      Darwin.close(descriptor)
      isClosed = true
      onClose(self)
      return
    }

    Self.configure(descriptor)
    peerPID = Self.peerPID(of: descriptor)
    DiagnosticLogger.shared.log(
      .info,
      .cli,
      "CLI client connected",
      context: ["pid": peerPID.map(String.init) ?? "unknown"]
    )

    let descriptor = descriptor
    let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
    source.setEventHandler { [weak self] in self?.readAvailable() }
    source.setCancelHandler { Darwin.close(descriptor) }
    readSource = source
    source.resume()
    scheduleTimeout(Self.handshakeTimeout, reason: "no hello")
  }

  private func closeOnQueue(reason: String) {
    guard !isClosed else { return }
    isClosed = true
    inFlightRequest?.cancel()
    inFlightRequest = nil
    timeoutTimer?.cancel()
    timeoutTimer = nil
    if let readSource {
      readSource.cancel()
      self.readSource = nil
    } else {
      Darwin.close(descriptor)
    }
    pendingPayloads.removeAll()
    DiagnosticLogger.shared.log(.debug, .cli, "CLI client disconnected", context: ["reason": reason])
    onClose(self)
  }

  // MARK: - Reading

  private func readAvailable() {
    guard !isClosed else { return }
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    let count = read(descriptor, &buffer, buffer.count)
    if count < 0, errno == EINTR || errno == EAGAIN {
      return
    }
    guard count > 0 else {
      closeOnQueue(reason: count == 0 ? "client closed" : "read failed")
      return
    }

    decoder.append(Data(buffer[0 ..< count]))
    do {
      while let payload = try decoder.nextPayload() {
        pendingPayloads.append(payload)
      }
    } catch {
      closeOnQueue(reason: "invalid frame: \(error)")
      return
    }
    processNext()
  }

  private func processNext() {
    guard !isClosed, !isProcessing, !pendingPayloads.isEmpty else { return }
    let payload = pendingPayloads.removeFirst()

    guard let header = try? CLIJSON.makeDecoder().decode(CLIRequestHeader.self, from: payload) else {
      send(CLIRequestRouter.encode(CLIError(.invalidArguments, "Malformed request"), id: 0))
      processNext()
      return
    }

    guard isHandshaken else {
      handleHello(header: header, payload: payload)
      processNext()
      return
    }

    guard header.method != CLIMethod.hello.rawValue else {
      send(CLIRequestRouter.encode(CLIError(.invalidArguments, "Handshake already completed"), id: header.id))
      processNext()
      return
    }

    isProcessing = true
    timeoutTimer?.cancel()
    let router = router
    let authorizer = authorizer
    let context = CLIRequestContext(
      connectionID: id,
      peerPID: peerPID,
      caller: caller,
      isAllowedForConnection: isAllowedForConnection
    )
    // Unknown methods go straight to the router (unknownMethod) without a
    // prompt, so a client cannot put its own text in front of the user.
    let isKnownMethod = router.registeredMethods.contains(header.method)
    inFlightRequest = Task.detached { [weak self] in
      let response: Data
      let outcome = isKnownMethod
        ? await authorizer.authorize(context, method: header.method)
        : .allowed
      switch outcome {
      case .denied(let error):
        response = CLIRequestRouter.encode(error, id: header.id)
      case .allowedForConnection:
        self?.queue.async { self?.isAllowedForConnection = true }
        response = await router.response(for: payload, header: header, context: context)
      case .allowed:
        response = await router.response(for: payload, header: header, context: context)
      }
      self?.queue.async { self?.finish(response, requestID: header.id) }
    }
  }

  private func finish(_ response: Data, requestID: UInt64) {
    isProcessing = false
    inFlightRequest = nil
    guard !isClosed else { return }
    guard response.count <= Frame.maxPayloadByteCount else {
      let error = CLIError(.internal, "Snapzy's response is too large to send (\(response.count) bytes)")
      send(CLIRequestRouter.encode(error, id: requestID))
      scheduleTimeout(Self.idleTimeout, reason: "idle")
      processNext()
      return
    }
    send(response)
    scheduleTimeout(Self.idleTimeout, reason: "idle")
    processNext()
  }

  private func handleHello(header: CLIRequestHeader, payload: Data) {
    guard header.method == CLIMethod.hello.rawValue else {
      send(CLIRequestRouter.encode(CLIError(.invalidArguments, "Send hello before \(header.method)"), id: header.id))
      closeOnQueue(reason: "request before hello")
      return
    }
    // Check only the version first: a future major version may reshape the
    // rest of `hello`, and should still get `versionMismatch`.
    guard let probe = try? CLIJSON.makeDecoder().decode(HelloVersionProbe.self, from: payload) else {
      send(CLIRequestRouter.encode(CLIError(.invalidArguments, "Malformed hello"), id: header.id))
      closeOnQueue(reason: "malformed hello")
      return
    }
    guard probe.params.protocolVersion.isCompatible(with: .current) else {
      let error = CLIError(
        .versionMismatch,
        "This snapzy command speaks CLI protocol \(probe.params.protocolVersion), Snapzy speaks \(ProtocolVersion.current)",
        hint: "Use the snapzy command bundled with this Snapzy (Contents/Helpers/snapzy)"
      )
      send(CLIRequestRouter.encode(error, id: header.id))
      closeOnQueue(reason: "protocol mismatch")
      return
    }
    guard let request = try? CLIJSON.makeDecoder().decode(CLIRequestEnvelope<HelloRequest>.self, from: payload) else {
      send(CLIRequestRouter.encode(CLIError(.invalidArguments, "Malformed hello"), id: header.id))
      closeOnQueue(reason: "malformed hello")
      return
    }

    isHandshaken = true
    caller = resolveCaller(peerPID)
    send(CLIRequestRouter.encode(result: hello, id: header.id))
    scheduleTimeout(Self.idleTimeout, reason: "idle")
    DiagnosticLogger.shared.log(
      .debug,
      .cli,
      "CLI handshake completed",
      context: ["cliVersion": request.params.cliVersion, "protocol": request.params.protocolVersion.description]
    )
  }

  // MARK: - Writing

  private func send(_ payload: Data) {
    guard !isClosed else { return }
    if !Self.write(payload, to: descriptor) {
      closeOnQueue(reason: "write failed")
    }
  }

  @discardableResult
  private static func write(_ payload: Data, to descriptor: Int32) -> Bool {
    guard let frame = try? Frame.encode(payload) else { return false }
    var offset = 0
    while offset < frame.count {
      let written = frame.withUnsafeBytes { buffer in
        Darwin.write(descriptor, buffer.baseAddress! + offset, frame.count - offset)
      }
      if written < 0 {
        if errno == EINTR { continue }
        return false
      }
      offset += written
    }
    return true
  }

  // MARK: - Helpers

  private struct HelloVersionProbe: Decodable {
    struct Params: Decodable {
      let protocolVersion: ProtocolVersion
    }

    let params: Params
  }

  private func scheduleTimeout(_ interval: TimeInterval, reason: String) {
    timeoutTimer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + interval)
    timer.setEventHandler { [weak self] in self?.closeOnQueue(reason: "timeout: \(reason)") }
    timeoutTimer = timer
    timer.resume()
  }

  /// Blocking with a send timeout, no SIGPIPE: a stuck client can delay only
  /// its own connection queue, never the app.
  private static func configure(_ descriptor: Int32) {
    let flags = fcntl(descriptor, F_GETFL)
    if flags >= 0 {
      _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK)
    }
    var noSigPipe: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: Int(writeTimeout), tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  private static func peerPID(of descriptor: Int32) -> pid_t? {
    var pid: pid_t = 0
    var length = socklen_t(MemoryLayout<pid_t>.size)
    guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0, pid > 0 else { return nil }
    return pid
  }
}
