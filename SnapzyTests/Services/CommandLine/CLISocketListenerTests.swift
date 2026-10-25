//
//  CLISocketListenerTests.swift
//  SnapzyTests
//
//  Drives the real listener over a Unix socket in a temp directory with a
//  minimal blocking client: permissions, handshake rules, stale sockets and
//  the connection cap.
//

import Darwin
@testable import Snapzy
import SnapzyCLIProtocol
import XCTest

final class CLISocketListenerTests: XCTestCase {
  private struct StubHandler: CLIRequestHandling {
    func handle(_: CLIEmpty, context _: CLIRequestContext) async throws -> CLIDisplayList {
      CLIDisplayList(displays: [])
    }
  }

  private struct AllowAllAuthorizer: CLIAuthorizing {
    func authorize(_: CLIRequestContext, method _: String) async -> CLIAuthorizationOutcome {
      .allowed
    }
  }

  /// Denies every method except `system.status`, like an app the user refused.
  private struct DenyingAuthorizer: CLIAuthorizing {
    func authorize(_: CLIRequestContext, method: String) async -> CLIAuthorizationOutcome {
      method == CLIMethod.systemStatus.rawValue ? .allowed : .denied(CLIError(.notAuthorized, "denied"))
    }
  }

  /// "Allow Once" on the first request, then records whether later requests
  /// on the same connection arrive already allowed.
  private final class AllowOnceAuthorizer: CLIAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Bool] = []

    /// Explicit and nonisolated: see #668 (main-actor deinit back-deploy abort on macOS 13-15).
    deinit {}

    var allowedForConnectionFlags: [Bool] {
      lock.withLock { calls }
    }

    func authorize(_ context: CLIRequestContext, method _: String) async -> CLIAuthorizationOutcome {
      lock.withLock { calls.append(context.isAllowedForConnection) }
      return context.isAllowedForConnection ? .allowed : .allowedForConnection
    }
  }

  /// Blocks until the request ID is answered; 2 s receive timeout.
  private final class TestClient {
    let descriptor: Int32
    private var decoder = FrameDecoder()

    init(path: String) throws {
      descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
      var address = sockaddr_un()
      address.sun_family = sa_family_t(AF_UNIX)
      withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        let bytes = Array(path.utf8)
        buffer.copyBytes(from: bytes)
        buffer[bytes.count] = 0
      }
      let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
      }
      guard connected == 0 else {
        close(descriptor)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      }
      var timeout = timeval(tv_sec: 2, tv_usec: 0)
      setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    deinit {
      close(descriptor)
    }

    func send(_ json: String) throws {
      let frame = try Frame.encode(Data(json.utf8))
      _ = frame.withUnsafeBytes { write(descriptor, $0.baseAddress, frame.count) }
    }

    func hello(protocolVersion: String = ProtocolVersion.current.description) throws -> Data? {
      try send(
        #"{"id":1,"method":"hello","params":{"cliVersion":"test","pid":1,"protocolVersion":"\#(protocolVersion)"}}"#
      )
      return receive()
    }

    /// `nil` when the server closed the connection or nothing arrived in time.
    func receive() -> Data? {
      var buffer = [UInt8](repeating: 0, count: 4096)
      while true {
        if let payload = try? decoder.nextPayload() {
          return payload
        }
        let count = read(descriptor, &buffer, buffer.count)
        guard count > 0 else { return nil }
        decoder.append(Data(buffer[0 ..< count]))
      }
    }

    func error(in payload: Data?) -> CLIError? {
      payload.flatMap { try? CLIJSON.makeDecoder().decode(CLIResponseEnvelope<CLIEmpty>.self, from: $0).error }
    }
  }

  private var directory: URL!
  private var listeners: [CLISocketListener] = []

  override func setUpWithError() throws {
    // Short path: sockaddr_un caps socket paths at 103 bytes.
    directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("sz-\(UUID().uuidString.prefix(8))", isDirectory: true)
  }

  override func tearDownWithError() throws {
    listeners.forEach { $0.stop() }
    try? FileManager.default.removeItem(at: directory)
  }

  private var socketPath: String {
    directory.appendingPathComponent("cli/test.sock").path
  }

  private func startListener(
    path: String? = nil,
    maxConnections: Int = 8,
    managesDirectory: Bool = true,
    authorizer: CLIAuthorizing = AllowAllAuthorizer()
  ) throws -> CLISocketListener {
    var router = CLIRequestRouter()
    router.register(.listDisplays, StubHandler())
    let listener = CLISocketListener(
      path: path ?? socketPath,
      hello: HelloResponse(appVersion: "9.9.9", appBuild: "1", bundleID: "com.trongduong.snapzy.tests"),
      router: router,
      authorizer: authorizer,
      resolveCaller: { _ in nil },
      maxConnections: maxConnections,
      managesDirectory: managesDirectory
    )
    try listener.start()
    listeners.append(listener)
    return listener
  }

  func testSocketAndDirectoryArePrivate() throws {
    _ = try startListener()

    let socketMode = try FileManager.default.attributesOfItem(atPath: socketPath)[.posixPermissions] as? Int
    let directoryMode = try FileManager.default
      .attributesOfItem(atPath: (socketPath as NSString).deletingLastPathComponent)[.posixPermissions] as? Int
    XCTAssertEqual(socketMode, 0o600)
    XCTAssertEqual(directoryMode, 0o700)
  }

  func testHandshakeThenRequest() throws {
    _ = try startListener()
    let client = try TestClient(path: socketPath)

    let hello = try XCTUnwrap(client.hello())
    let helloResponse = try CLIJSON.makeDecoder().decode(CLIResponseEnvelope<HelloResponse>.self, from: hello)
    XCTAssertEqual(helloResponse.result?.appVersion, "9.9.9")

    try client.send(#"{"id":2,"method":"list.displays","params":{}}"#)
    let response = try XCTUnwrap(client.receive())
    let decoded = try CLIJSON.makeDecoder().decode(CLIResponseEnvelope<CLIDisplayList>.self, from: response)
    XCTAssertEqual(decoded.id, 2)
    XCTAssertEqual(decoded.result, CLIDisplayList(displays: []))
  }

  func testRequestBeforeHelloIsRejectedAndClosed() throws {
    _ = try startListener()
    let client = try TestClient(path: socketPath)

    try client.send(#"{"id":1,"method":"list.displays","params":{}}"#)

    XCTAssertEqual(client.error(in: client.receive())?.code, .invalidArguments)
    XCTAssertNil(client.receive(), "connection should be closed")
  }

  func testMajorVersionMismatchIsRejected() throws {
    _ = try startListener()
    let client = try TestClient(path: socketPath)

    XCTAssertEqual(try client.error(in: client.hello(protocolVersion: "99.0"))?.code, .versionMismatch)
    XCTAssertNil(client.receive(), "connection should be closed")
  }

  func testMalformedRequestGetsIDZeroError() throws {
    _ = try startListener()
    let client = try TestClient(path: socketPath)
    _ = try client.hello()

    try client.send("not json")
    let payload = try XCTUnwrap(client.receive())
    let response = try CLIJSON.makeDecoder().decode(CLIResponseEnvelope<CLIEmpty>.self, from: payload)

    XCTAssertEqual(response.id, 0)
    XCTAssertEqual(response.error?.code, .invalidArguments)
  }

  func testStaleSocketIsReplaced() throws {
    let first = try startListener()
    first.stop()
    // Leave a dead socket file behind, like a crashed app would.
    let stale = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      let bytes = Array(socketPath.utf8)
      buffer.copyBytes(from: bytes)
      buffer[bytes.count] = 0
    }
    _ = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    Darwin.close(stale)
    XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))

    _ = try startListener()
    XCTAssertNotNil(try TestClient(path: socketPath).hello())
  }

  func testLiveSocketIsNotStolen() throws {
    _ = try startListener()
    let second = CLISocketListener(
      path: socketPath,
      hello: HelloResponse(appVersion: "", appBuild: "", bundleID: ""),
      router: CLIRequestRouter(),
      authorizer: AllowAllAuthorizer(),
      resolveCaller: { _ in nil }
    )

    XCTAssertThrowsError(try second.start()) { error in
      XCTAssertEqual(error as? CLISocketListener.StartError, .alreadyServed)
    }
    XCTAssertNotNil(try TestClient(path: socketPath).hello())
  }

  func testNonSocketFileIsNeverDeleted() throws {
    try FileManager.default.createDirectory(
      at: URL(fileURLWithPath: socketPath).deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("keep".utf8).write(to: URL(fileURLWithPath: socketPath))

    XCTAssertThrowsError(try startListener()) { error in
      XCTAssertEqual(error as? CLISocketListener.StartError, .notASocket)
    }
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: socketPath)), Data("keep".utf8))
  }

  func testOverCapacityClientGetsBusy() throws {
    _ = try startListener(maxConnections: 1)
    let first = try TestClient(path: socketPath)
    XCTAssertNotNil(try first.hello())

    let second = try TestClient(path: socketPath)
    let payload = try XCTUnwrap(second.receive())
    let response = try CLIJSON.makeDecoder().decode(CLIResponseEnvelope<CLIEmpty>.self, from: payload)

    XCTAssertEqual(response.id, 0)
    XCTAssertEqual(response.error?.code, .busy)
  }

  func testStopRemovesSocketFile() throws {
    let listener = try startListener()
    listener.stop()

    XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
  }

  func testStopLeavesSuccessorSocketAlone() throws {
    let first = try startListener()
    // Simulate the socket being replaced by another server at the same path.
    unlink(socketPath)
    let successor = try startListener()

    first.stop()

    XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))
    XCTAssertNotNil(try TestClient(path: socketPath).hello())
    successor.stop()
  }

  func testOverriddenDirectoryIsCheckedNotChanged() throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o755]
    )
    let path = directory.appendingPathComponent("override.sock").path

    _ = try startListener(path: path, managesDirectory: false)

    let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
    XCTAssertEqual(mode, 0o755, "an overridden socket directory must not be chmod-ed")
    XCTAssertNotNil(try TestClient(path: path).hello())
  }

  func testOverriddenDirectoryMustExist() {
    let path = directory.appendingPathComponent("missing/override.sock").path

    XCTAssertThrowsError(try startListener(path: path, managesDirectory: false)) { error in
      XCTAssertEqual(error as? CLISocketListener.StartError, .untrustedDirectory)
    }
  }

  func testFutureHelloShapeStillGetsVersionMismatch() throws {
    _ = try startListener()
    let client = try TestClient(path: socketPath)

    try client.send(#"{"id":1,"method":"hello","params":{"protocolVersion":"2.0","capabilities":[]}}"#)

    XCTAssertEqual(client.error(in: client.receive())?.code, .versionMismatch)
  }

  func testDeniedCallerGetsNotAuthorizedInsteadOfAResult() throws {
    _ = try startListener(authorizer: DenyingAuthorizer())
    let client = try TestClient(path: socketPath)
    _ = try client.hello()

    try client.send(#"{"id":2,"method":"list.displays","params":{}}"#)

    XCTAssertEqual(client.error(in: client.receive())?.code, .notAuthorized)
  }

  func testAllowOnceCoversTheRestOfTheConnection() throws {
    let authorizer = AllowOnceAuthorizer()
    _ = try startListener(authorizer: authorizer)
    let client = try TestClient(path: socketPath)
    _ = try client.hello()

    for id in 2 ... 3 {
      try client.send(#"{"id":\#(id),"method":"list.displays","params":{}}"#)
      XCTAssertNotNil(client.receive())
    }

    XCTAssertEqual(authorizer.allowedForConnectionFlags, [false, true])
  }

  func testUnknownMethodIsRejectedWithoutAuthorization() throws {
    _ = try startListener(authorizer: DenyingAuthorizer())
    let client = try TestClient(path: socketPath)
    _ = try client.hello()

    try client.send(#"{"id":2,"method":"capture.everything","params":{}}"#)

    XCTAssertEqual(client.error(in: client.receive())?.code, .unknownMethod)
  }
}
