//
//  CLIClientSocketTests.swift
//  SnapzyCLICoreTests
//
//  Drives SocketConnection + CLIClient against a minimal in-process Unix
//  socket server that answers each request from a handler.
//

import Darwin
import Foundation
@testable import SnapzyCLIClient
@testable import SnapzyCLIProtocol
import XCTest

/// Accepts one connection and answers every frame with `handler(header, payload)`.
/// Returning `nil` leaves the request unanswered.
private final class FakeSnapzyServer: @unchecked Sendable {
  let path: String
  private let listener: Int32
  private let handler: @Sendable (CLIRequestHeader, Data) -> Data?

  init(handler: @escaping @Sendable (CLIRequestHeader, Data) -> Data?) throws {
    path = FileManager.default.temporaryDirectory
      .appendingPathComponent("sz-\(UUID().uuidString.prefix(8)).sock").path
    self.handler = handler

    listener = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
      let bytes = Array(path.utf8)
      buffer.copyBytes(from: bytes)
      buffer[bytes.count] = 0
    }
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bound == 0, listen(listener, 1) == 0 else {
      throw SocketConnectionError.system(operation: "bind", errno: errno)
    }

    Thread { [self] in serve() }.start()
  }

  deinit {
    close(listener)
    unlink(path)
  }

  private func serve() {
    let client = accept(listener, nil, nil)
    guard client >= 0 else { return }
    defer { close(client) }

    var decoder = FrameDecoder()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = read(client, &buffer, buffer.count)
      guard count > 0 else { return }
      decoder.append(Data(buffer[0 ..< count]))

      while let payload = try? decoder.nextPayload() {
        guard
          let header = try? CLIJSON.makeDecoder().decode(CLIRequestHeader.self, from: payload),
          let response = handler(header, payload),
          let frame = try? Frame.encode(response)
        else { continue }
        _ = frame.withUnsafeBytes { write(client, $0.baseAddress, frame.count) }
      }
    }
  }

  static func encode(_ envelope: CLIResponseEnvelope<some Codable & Sendable>) -> Data {
    try! CLIJSON.makeEncoder().encode(envelope)
  }

  static func hello(id: UInt64, protocolVersion: ProtocolVersion = .current) -> Data {
    encode(CLIResponseEnvelope(
      id: id,
      result: HelloResponse(
        protocolVersion: protocolVersion,
        appVersion: "2.1.0",
        appBuild: "42",
        bundleID: "com.trongduong.snapzy"
      )
    ))
  }
}

final class CLIClientSocketTests: XCTestCase {
  func testConnect_missingSocket() {
    XCTAssertThrowsError(try SocketConnection.connect(path: "/tmp/snapzy-missing-\(UUID().uuidString).sock")) { error in
      XCTAssertEqual(error as? SocketConnectionError, .socketMissing)
    }
  }

  func testConnect_pathTooLong() {
    XCTAssertThrowsError(try SocketConnection.connect(path: "/tmp/" + String(repeating: "x", count: 120))) { error in
      XCTAssertEqual(error as? SocketConnectionError, .pathTooLong)
    }
  }

  func testHandshakeThenTypedCall() throws {
    let server = try FakeSnapzyServer { header, payload in
      switch header.method {
      case "hello":
        let request = try? CLIJSON.makeDecoder().decode(CLIRequestEnvelope<HelloRequest>.self, from: payload)
        XCTAssertEqual(request?.params.protocolVersion, .current)
        return FakeSnapzyServer.hello(id: header.id)
      case "list.windows":
        let request = try? CLIJSON.makeDecoder().decode(CLIRequestEnvelope<ListWindowsParams>.self, from: payload)
        XCTAssertEqual(request?.params, ListWindowsParams(app: "Code", includeOffscreen: true))
        return FakeSnapzyServer.encode(CLIResponseEnvelope(id: header.id, result: CLIWindowList(windows: [])))
      default:
        return nil
      }
    }

    let client = try CLIClient(
      connection: SocketConnection.connect(path: server.path),
      cliVersion: "test",
      requestTimeout: 2
    )
    defer { client.close() }

    XCTAssertEqual(client.hello.appVersion, "2.1.0")
    let list = try client.call(
      .listWindows,
      params: ListWindowsParams(app: "Code", includeOffscreen: true),
      as: CLIWindowList.self
    )
    XCTAssertEqual(list, CLIWindowList(windows: []))
  }

  func testErrorResponseSurfacesAsCLIError() throws {
    let server = try FakeSnapzyServer { header, _ in
      header.method == "hello"
        ? FakeSnapzyServer.hello(id: header.id)
        : FakeSnapzyServer.encode(CLIResponseEnvelope<CLIEmpty>(
          id: header.id,
          error: CLIError(.notAuthorized, "Terminal is not allowed")
        ))
    }
    let client = try CLIClient(
      connection: SocketConnection.connect(path: server.path),
      cliVersion: "test",
      requestTimeout: 2
    )
    defer { client.close() }

    XCTAssertThrowsError(try client.call(
      .captureScreen,
      params: CaptureScreenParams(),
      as: CLICaptureResult.self
    )) { error in
      XCTAssertEqual(error as? CLIError, CLIError(.notAuthorized, "Terminal is not allowed"))
    }
  }

  func testMajorVersionMismatchIsRejected() throws {
    let server = try FakeSnapzyServer { header, _ in
      FakeSnapzyServer.hello(id: header.id, protocolVersion: ProtocolVersion(major: 2, minor: 0))
    }

    XCTAssertThrowsError(
      try CLIClient(connection: SocketConnection.connect(path: server.path), cliVersion: "test", requestTimeout: 2)
    ) { error in
      XCTAssertEqual((error as? CLIError)?.code, .versionMismatch)
    }
  }

  func testUnansweredRequestTimesOut() throws {
    let server = try FakeSnapzyServer { header, _ in
      header.method == "hello" ? FakeSnapzyServer.hello(id: header.id) : nil
    }
    let client = try CLIClient(
      connection: SocketConnection.connect(path: server.path),
      cliVersion: "test",
      requestTimeout: 0.2
    )
    defer { client.close() }

    XCTAssertThrowsError(try client.call(.systemStatus, as: CLIStatus.self)) { error in
      XCTAssertEqual((error as? CLIError)?.code, .appUnavailable)
    }
  }

  func testMismatchedResponseIDIsRejected() throws {
    let server = try FakeSnapzyServer { header, _ in
      FakeSnapzyServer.hello(id: header.id + 100)
    }

    XCTAssertThrowsError(
      try CLIClient(connection: SocketConnection.connect(path: server.path), cliVersion: "test", requestTimeout: 2)
    ) { error in
      XCTAssertEqual((error as? CLIError)?.code, .internal)
    }
  }

  func testErrorWithIDZeroIsSurfaced() throws {
    let server = try FakeSnapzyServer { header, _ in
      header.method == "hello"
        ? FakeSnapzyServer.hello(id: header.id)
        : FakeSnapzyServer.encode(CLIResponseEnvelope<CLIEmpty>(
          id: 0,
          error: CLIError(.invalidArguments, "Unreadable request")
        ))
    }
    let client = try CLIClient(
      connection: SocketConnection.connect(path: server.path),
      cliVersion: "test",
      requestTimeout: 2
    )
    defer { client.close() }

    XCTAssertThrowsError(try client.call(.systemStatus, as: CLIStatus.self)) { error in
      XCTAssertEqual(error as? CLIError, CLIError(.invalidArguments, "Unreadable request"))
    }
  }
}
