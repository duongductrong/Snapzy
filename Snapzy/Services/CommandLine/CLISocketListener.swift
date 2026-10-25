//
//  CLISocketListener.swift
//  Snapzy
//
//  Unix domain socket the `snapzy` CLI connects to. The directory is 0700
//  and the socket 0600, so only the current user can reach it; each
//  connection is checked again with getpeereid.
//

import Darwin
import Foundation
import SnapzyCLIProtocol

final nonisolated class CLISocketListener: @unchecked Sendable {
  enum StartError: Error, Equatable {
    case pathTooLong
    /// Another live process (e.g. a second copy of Snapzy) is serving this socket.
    case alreadyServed
    /// Something other than a socket exists at the path; never delete it.
    case notASocket
    /// An overridden socket's parent directory is missing or not owned by this user.
    case untrustedDirectory
    case system(operation: String, errno: Int32)
  }

  static let defaultMaxConnections = 8

  let path: String

  private let hello: HelloResponse
  private let router: CLIRequestRouter
  private let authorizer: CLIAuthorizing
  private let resolveCaller: @Sendable (pid_t?) -> CLICallerIdentity?
  private let maxConnections: Int
  /// Whether the socket's parent directory is Snapzy's own (created and kept
  /// 0700) rather than one chosen through `SNAPZY_SOCKET`, which is only checked.
  private let managesDirectory: Bool
  private let queue = DispatchQueue(label: "com.trongduong.snapzy.cli.listener")
  private var acceptSource: DispatchSourceRead?
  private var listenDescriptor: Int32 = -1
  /// Identity of the socket file this listener bound, so `stop()` never
  /// unlinks a successor's socket at the same path.
  private var boundSocketInode: ino_t?
  private var isAcceptPaused = false
  private var connections: [UUID: CLIConnection] = [:]

  init(
    path: String,
    hello: HelloResponse,
    router: CLIRequestRouter,
    authorizer: CLIAuthorizing,
    resolveCaller: @escaping @Sendable (pid_t?) -> CLICallerIdentity?,
    maxConnections: Int = defaultMaxConnections,
    managesDirectory: Bool = true
  ) {
    self.path = path
    self.hello = hello
    self.router = router
    self.authorizer = authorizer
    self.resolveCaller = resolveCaller
    self.maxConnections = maxConnections
    self.managesDirectory = managesDirectory
  }

  deinit {
    acceptSource?.cancel()
  }

  func start() throws {
    try queue.sync { try startOnQueue() }
  }

  func stop() {
    queue.sync { stopOnQueue() }
  }

  var connectionCount: Int {
    queue.sync { connections.count }
  }

  // MARK: - Start / stop

  private func startOnQueue() throws {
    guard listenDescriptor < 0 else { return }
    guard path.utf8.count <= SocketLocation.maxPathByteCount else { throw StartError.pathTooLong }

    let directory = (path as NSString).deletingLastPathComponent
    if managesDirectory {
      try createPrivateDirectory(directory)
    } else {
      try verifyOwnedDirectory(directory)
    }
    try removeStaleSocket()

    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw StartError.system(operation: "socket", errno: errno) }

    var address = Self.address(for: path)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bound == 0 else {
      let bindErrno = errno
      Darwin.close(descriptor)
      throw StartError.system(operation: "bind", errno: bindErrno)
    }

    func failSetup(_ operation: String) -> StartError {
      let setupErrno = errno
      Darwin.close(descriptor)
      unlink(path)
      return StartError.system(operation: operation, errno: setupErrno)
    }
    guard chmod(path, 0o600) == 0 else { throw failSetup("chmod") }
    guard listen(descriptor, Int32(maxConnections * 2)) == 0 else { throw failSetup("listen") }
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { throw failSetup("fcntl") }

    var info = stat()
    boundSocketInode = lstat(path, &info) == 0 ? info.st_ino : nil

    let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
    source.setEventHandler { [weak self] in self?.acceptPending() }
    source.setCancelHandler { Darwin.close(descriptor) }
    listenDescriptor = descriptor
    acceptSource = source
    source.resume()
  }

  private func stopOnQueue() {
    guard listenDescriptor >= 0 else { return }
    acceptSource?.cancel()
    if isAcceptPaused {
      // Releasing a suspended dispatch source crashes; resume after cancel.
      acceptSource?.resume()
      isAcceptPaused = false
    }
    acceptSource = nil
    listenDescriptor = -1
    var info = stat()
    if let boundSocketInode, lstat(path, &info) == 0, info.st_ino == boundSocketInode {
      unlink(path)
    }
    boundSocketInode = nil
    connections.values.forEach { $0.close() }
    connections.removeAll()
  }

  private func createPrivateDirectory(_ directory: String) throws {
    do {
      try FileManager.default.createDirectory(
        atPath: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      let posixCode = ((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.code
      throw StartError.system(operation: "mkdir", errno: Int32(posixCode ?? Int(EIO)))
    }
    guard chmod(directory, 0o700) == 0 else {
      throw StartError.system(operation: "chmod", errno: errno)
    }
  }

  private func verifyOwnedDirectory(_ directory: String) throws {
    var info = stat()
    guard
      lstat(directory, &info) == 0,
      (info.st_mode & S_IFMT) == S_IFDIR,
      info.st_uid == getuid()
    else { throw StartError.untrustedDirectory }
  }

  /// A socket file left by a crashed Snapzy is removed; a socket someone is
  /// still listening on is not.
  private func removeStaleSocket() throws {
    var info = stat()
    guard lstat(path, &info) == 0 else { return }
    guard (info.st_mode & S_IFMT) == S_IFSOCK else { throw StartError.notASocket }

    let probe = socket(AF_UNIX, SOCK_STREAM, 0)
    if probe >= 0 {
      var address = Self.address(for: path)
      let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
      }
      Darwin.close(probe)
      if connected == 0 {
        throw StartError.alreadyServed
      }
    }
    unlink(path)
  }

  // MARK: - Accepting

  private func acceptPending() {
    while listenDescriptor >= 0 {
      let client = accept(listenDescriptor, nil, nil)
      if client < 0 {
        switch errno {
        case EINTR, ECONNABORTED:
          continue
        case EMFILE, ENFILE:
          pauseAccepting()
        default:
          break
        }
        return
      }

      guard connections.count < maxConnections else {
        DiagnosticLogger.shared.log(.warning, .cli, "Rejected CLI client: too many connections")
        CLIConnection.rejectBusy(descriptor: client)
        continue
      }

      let connection = CLIConnection(
        descriptor: client,
        hello: hello,
        router: router,
        authorizer: authorizer,
        resolveCaller: resolveCaller
      ) { [weak self] closed in
        self?.queue.async { self?.connections.removeValue(forKey: closed.id) }
      }
      connections[connection.id] = connection
      connection.start()
    }
  }

  /// Out of file descriptors: the level-triggered source would fire again at
  /// once and spin, so stop accepting for a moment.
  private func pauseAccepting() {
    guard let acceptSource, !isAcceptPaused else { return }
    DiagnosticLogger.shared.log(.warning, .cli, "CLI accept paused: out of file descriptors")
    acceptSource.suspend()
    isAcceptPaused = true
    queue.asyncAfter(deadline: .now() + 1) { [weak self] in
      guard let self, isAcceptPaused, self.acceptSource === acceptSource else { return }
      isAcceptPaused = false
      acceptSource.resume()
    }
  }

  private static func address(for path: String) -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(path.utf8)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      buffer.copyBytes(from: bytes.prefix(buffer.count - 1))
      buffer[min(bytes.count, buffer.count - 1)] = 0
    }
    return address
  }
}
