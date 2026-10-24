//
//  CLIRequestRouterTests.swift
//  SnapzyTests
//
//  Typed param decoding, error mapping and unknown methods in the CLI router.
//

@testable import Snapzy
import SnapzyCLIProtocol
import XCTest

final class CLIRequestRouterTests: XCTestCase {
  private struct EchoHandler: CLIRequestHandling {
    func handle(_ params: ListWindowsParams, context _: CLIRequestContext) async throws -> CLIWindowList {
      if params.app == "fail" {
        throw CLIError(.targetNotFound, "No app named fail", hint: "Run snapzy list apps")
      }
      if params.app == "crash" {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
      }
      return CLIWindowList(windows: [])
    }
  }

  private let context = CLIRequestContext(connectionID: UUID(), peerPID: nil)

  private func makeRouter() -> CLIRequestRouter {
    var router = CLIRequestRouter()
    router.register(.listWindows, EchoHandler())
    return router
  }

  private func respond(_ json: String) async throws -> CLIResponseEnvelope<CLIWindowList> {
    let payload = Data(json.utf8)
    let header = try CLIJSON.makeDecoder().decode(CLIRequestHeader.self, from: payload)
    let response = await makeRouter().response(for: payload, header: header, context: context)
    return try CLIJSON.makeDecoder().decode(CLIResponseEnvelope<CLIWindowList>.self, from: response)
  }

  func testTypedParamsReachHandler() async throws {
    let response =
      try await respond(#"{"id":4,"method":"list.windows","params":{"app":"Code","includeOffscreen":false}}"#)

    XCTAssertEqual(response.id, 4)
    XCTAssertEqual(response.result, CLIWindowList(windows: []))
    XCTAssertNil(response.error)
  }

  func testInvalidParamsAreInvalidArguments() async throws {
    let response = try await respond(#"{"id":5,"method":"list.windows","params":{"app":7}}"#)

    XCTAssertEqual(response.id, 5)
    XCTAssertEqual(response.error?.code, .invalidArguments)
    XCTAssertTrue(response.error?.message.contains("list.windows") == true)
  }

  func testCLIErrorPassesThroughWithHint() async throws {
    let response =
      try await respond(#"{"id":6,"method":"list.windows","params":{"app":"fail","includeOffscreen":false}}"#)

    XCTAssertEqual(response.error, CLIError(.targetNotFound, "No app named fail", hint: "Run snapzy list apps"))
  }

  func testUnexpectedErrorBecomesInternal() async throws {
    let response =
      try await respond(#"{"id":7,"method":"list.windows","params":{"app":"crash","includeOffscreen":false}}"#)

    XCTAssertEqual(response.error?.code, .internal)
    XCTAssertEqual(response.error?.message, "boom")
  }

  func testUnknownMethod() async throws {
    let response = try await respond(#"{"id":8,"method":"capture.everything","params":{}}"#)

    XCTAssertEqual(response.id, 8)
    XCTAssertEqual(response.error?.code, .unknownMethod)
  }

  func testServerRegistersEveryMethodButHello() {
    XCTAssertEqual(
      CLIServer.makeRouter().registeredMethods,
      Set(CLIMethod.allCases.filter { $0 != .hello }.map(\.rawValue))
    )
  }
}
