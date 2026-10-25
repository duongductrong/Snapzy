//
//  EnvelopeContractTests.swift
//  SnapzyCLIProtocolTests
//
//  Golden JSON for the wire and output contract. A failure here means agents
//  or an older app would see a different shape: change it deliberately and
//  update docs/CLI.md.
//

@testable import SnapzyCLIProtocol
import XCTest

final class EnvelopeContractTests: XCTestCase {
  private func json(_ value: some Encodable) throws -> String {
    try String(decoding: CLIJSON.makeEncoder().encode(value), as: UTF8.self)
  }

  private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try CLIJSON.makeDecoder().decode(type, from: Data(json.utf8))
  }

  // MARK: - Requests

  func testHelloRequest() throws {
    let request = CLIRequestEnvelope(
      id: 1,
      method: .hello,
      params: HelloRequest(cliVersion: "2.1.0", pid: 42)
    )

    XCTAssertEqual(
      try json(request),
      #"{"id":1,"method":"hello","params":{"cliVersion":"2.1.0","pid":42,"protocolVersion":"1.0"}}"#
    )
  }

  func testCaptureWindowRequest_appSelector() throws {
    let request = CLIRequestEnvelope(
      id: 7,
      method: .captureWindow,
      params: CaptureWindowParams(
        window: .app(AppWindowQuery(app: "Safari", titlePattern: "^Docs", index: 1)),
        options: CaptureOptions(format: .jpeg, quality: 0.8, maxDimension: 1568)
      )
    )

    XCTAssertEqual(
      try json(request),
      #"{"id":7,"method":"capture.window","params":{"options":{"format":"jpeg","maxDimension":1568,"#
        + #""quality":0.8,"showCursor":false,"windowShadow":true},"#
        + #""window":{"app":"Safari","index":1,"titlePattern":"^Docs"}}}"#
    )
  }

  func testRequestHeader_decodesWithoutKnowingParams() throws {
    let header = try decode(
      CLIRequestHeader.self,
      #"{"id":3,"method":"capture.area","params":{"rect":{"x":0,"y":0,"width":10,"height":10}}}"#
    )

    XCTAssertEqual(header, CLIRequestHeader(id: 3, method: "capture.area"))
  }

  // MARK: - Selectors

  func testDisplaySelector_coding() throws {
    XCTAssertEqual(try json([DisplaySelector.main, .all, .id(69_733_382)]), #"["main","all",69733382]"#)
    XCTAssertEqual(try decode([DisplaySelector].self, #"["main","all",5]"#), [.main, .all, .id(5)])
    XCTAssertThrowsError(try decode(DisplaySelector.self, #""primary""#))
  }

  func testWindowSelector_coding() throws {
    XCTAssertEqual(try json(WindowSelector.id(9)), #"{"id":9}"#)
    XCTAssertEqual(try json(WindowSelector.active), #"{"active":true}"#)
    XCTAssertEqual(try json(WindowSelector.app(AppWindowQuery(app: "Code"))), #"{"app":"Code"}"#)

    XCTAssertEqual(try decode(WindowSelector.self, #"{"id":9}"#), .id(9))
    XCTAssertEqual(try decode(WindowSelector.self, #"{"active":true}"#), .active)
    XCTAssertEqual(
      try decode(WindowSelector.self, #"{"app":"Code","titlePattern":"README"}"#),
      .app(AppWindowQuery(app: "Code", titlePattern: "README"))
    )
  }

  func testWindowSelector_rejectsAmbiguousOrEmpty() {
    XCTAssertThrowsError(try decode(WindowSelector.self, #"{"id":9,"app":"Code"}"#))
    XCTAssertThrowsError(try decode(WindowSelector.self, #"{"id":9,"active":true}"#))
    XCTAssertThrowsError(try decode(WindowSelector.self, #"{"active":false}"#))
    XCTAssertThrowsError(try decode(WindowSelector.self, #"{}"#))
  }

  // MARK: - Responses

  func testCaptureResultResponse() throws {
    let response = CLIResponseEnvelope(
      id: 7,
      result: CLICaptureResult(
        files: [
          CLICapturedFile(
            path: "/tmp/snapzy cli/a.png",
            format: .png,
            width: 2880,
            height: 1800,
            scale: 2,
            bytes: 1024,
            displayID: 1
          ),
        ],
        durationMs: 84
      )
    )

    XCTAssertEqual(
      try json(response),
      #"{"id":7,"result":{"durationMs":84,"files":[{"bytes":1024,"displayID":1,"format":"png","#
        + #""height":1800,"path":"/tmp/snapzy cli/a.png","scale":2,"width":2880}]}}"#
    )
  }

  func testUnknownValuesFromNewerAppDecodeToFallbacks() throws {
    let response = try decode(
      CLIResponseEnvelope<CLIEmpty>.self,
      #"{"id":2,"error":{"code":"rateLimited","message":"Slow down","hint":"Retry in 1 s"}}"#
    )
    XCTAssertEqual(response.error, CLIError(.internal, "Slow down", hint: "Retry in 1 s"))

    let status = try decode(
      CLIStatus.self,
      #"{"appVersion":"2.2.0","authorization":"pending","cliEnabled":true,"#
        + #""onboardingCompleted":true,"screenRecordingPermission":"restricted"}"#
    )
    XCTAssertEqual(status.screenRecordingPermission, .unavailable)
    XCTAssertEqual(status.authorization, .undetermined)
  }

  func testErrorResponse_decodesWithAnyResultType() throws {
    let response = try decode(
      CLIResponseEnvelope<CLICaptureResult>.self,
      #"{"id":2,"error":{"code":"targetNotFound","message":"No window","hint":"Run snapzy list windows"}}"#
    )

    XCTAssertNil(response.result)
    XCTAssertEqual(response.error, CLIError(.targetNotFound, "No window", hint: "Run snapzy list windows"))
  }

  func testEmptyParamsEncodeAsEmptyObject() throws {
    XCTAssertEqual(
      try json(CLIRequestEnvelope(id: 1, method: .listDisplays, params: CLIEmpty())),
      #"{"id":1,"method":"list.displays","params":{}}"#
    )
  }

  func testStatusResult() throws {
    let status = CLIStatus(
      appVersion: "2.1.0",
      cliEnabled: true,
      onboardingCompleted: true,
      screenRecordingPermission: .granted,
      authorization: .undetermined
    )

    XCTAssertEqual(
      try json(status),
      #"{"appVersion":"2.1.0","authorization":"undetermined","cliEnabled":true,"#
        + #""onboardingCompleted":true,"screenRecordingPermission":"granted"}"#
    )
  }

  func testMethodNamesAreStable() {
    XCTAssertEqual(
      CLIMethod.allCases.map(\.rawValue),
      [
        "hello", "system.status", "list.displays", "list.windows", "list.apps",
        "capture.screen", "capture.window", "capture.area",
      ]
    )
  }
}
