//
//  MCPServerTests.swift
//  SnapzyCLICoreTests
//

import Foundation
@testable import SnapzyCLICore
import SnapzyCLIProtocol
import XCTest

final class MCPServerTests: XCTestCase {
  private final class FakeBackend: MCPToolBackend, @unchecked Sendable {
    var calls: [(String, String)] = []
    var callError: Error?
    var listError: Error?
    var image: AgentImage?

    func listTools() async throws -> [AgentToolDescriptor] {
      if let listError { throw listError }
      return [AgentToolDescriptor(
        name: "add_box",
        description: "Draw a box.",
        inputSchema: #"{"properties":{"target":{"type":"string"}},"type":"object"}"#
      )]
    }

    func callTool(name: String, arguments: String) async throws -> AgentCallResult {
      calls.append((name, arguments))
      if let callError { throw callError }
      return AgentCallResult(text: #"{"ok":true}"#, isError: false, image: image)
    }
  }

  private func rawRespond(_ backend: FakeBackend, _ message: String) async throws -> [String: Any]? {
    let handler = MCPMessageHandler(backend: backend, serverVersion: "9.9")
    guard let data = await handler.handle(Data(message.utf8)) else { return nil }
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func respond(_ backend: FakeBackend, _ message: String) async throws -> [String: Any] {
    let response = try await rawRespond(backend, message)
    return try XCTUnwrap(response)
  }

  func testInitializeEchoesKnownVersionAndOffersTools() async throws {
    let response = try await respond(
      FakeBackend(),
      #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#
    )
    let result = try XCTUnwrap(response["result"] as? [String: Any])
    XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
    XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
    XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "snapzy")
    XCTAssertEqual(response["id"] as? Int, 0)
  }

  func testInitializeWithUnknownVersionFallsBackToSupportedOne() async throws {
    let response = try await respond(
      FakeBackend(),
      #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#
    )
    let version = (response["result"] as? [String: Any])?["protocolVersion"] as? String
    XCTAssertTrue(MCPMessageHandler.supportedProtocolVersions.contains(version ?? ""))
    XCTAssertEqual(response["id"] as? String, "a")
  }

  func testNotificationsAndResponsesGetNoAnswer() async throws {
    let notification = try await rawRespond(FakeBackend(), #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
    XCTAssertNil(notification)
    let response = try await rawRespond(FakeBackend(), #"{"jsonrpc":"2.0","id":5,"result":{}}"#)
    XCTAssertNil(response)
  }

  func testToolsListDecodesSchema() async throws {
    let response = try await respond(FakeBackend(), #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    let tools = try XCTUnwrap((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
    XCTAssertEqual(tools.first?["name"] as? String, "add_box")
    XCTAssertEqual((tools.first?["inputSchema"] as? [String: Any])?["type"] as? String, "object")
  }

  func testToolsListFailureIsJSONRPCError() async throws {
    let backend = FakeBackend()
    backend.listError = CLIError(.appUnavailable, "Snapzy is gone")
    let response = try await respond(backend, #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    XCTAssertEqual((response["error"] as? [String: Any])?["message"] as? String, "Snapzy is gone")
  }

  func testToolsCallForwardsArgumentsAndImage() async throws {
    let backend = FakeBackend()
    backend.image = AgentImage(mimeType: "image/jpeg", base64: "AAAA")
    let response = try await respond(
      backend,
      #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"add_box","arguments":{"target":{"text":"Sign in"}}}}"#
    )
    XCTAssertEqual(backend.calls.first?.0, "add_box")
    XCTAssertEqual(backend.calls.first?.1, #"{"target":{"text":"Sign in"}}"#)
    let result = try XCTUnwrap(response["result"] as? [String: Any])
    XCTAssertEqual(result["isError"] as? Bool, false)
    let content = try XCTUnwrap(result["content"] as? [[String: Any]])
    XCTAssertEqual(content.map { $0["type"] as? String }, ["text", "image"])
    XCTAssertEqual(content[1]["data"] as? String, "AAAA")
  }

  func testExpiredSessionBecomesToolError() async throws {
    let backend = FakeBackend()
    backend.callError = CLIError(.notAuthorized, "Unknown session")
    let response = try await respond(
      backend,
      #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"add_box"}}"#
    )
    let result = try XCTUnwrap(response["result"] as? [String: Any])
    XCTAssertEqual(result["isError"] as? Bool, true)
    let text = (result["content"] as? [[String: Any]])?.first?["text"] as? String
    XCTAssertTrue(text?.contains("session has ended") == true)
    XCTAssertEqual(backend.calls.first?.1, "{}")
  }

  func testUnknownMethodAndParseError() async throws {
    let unknown = try await respond(FakeBackend(), #"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#)
    XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
    let garbage = try await respond(FakeBackend(), "not json")
    XCTAssertEqual((garbage["error"] as? [String: Any])?["code"] as? Int, -32700)
  }

  func testCommandIsParsedAndHidden() throws {
    let command = try SnapzyCommand.parseAsRoot(["mcp", "--session", "tok"])
    XCTAssertEqual((command as? MCPCommand)?.session, "tok")
    XCTAssertFalse(MCPCommand.configuration.shouldDisplay)
  }
}
