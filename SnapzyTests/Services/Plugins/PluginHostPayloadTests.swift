//
//  PluginHostPayloadTests.swift
//  SnapzyTests
//
//  The bytes-across-the-boundary contract. The helper marks binary with the
//  `{ "base64": … }` envelope, but `Data`'s own Codable conformance reads a
//  bare base64 string — so a payload carrying an image has to be unwrapped
//  before it decodes into its typed request. Getting this wrong turns
//  `ctx.ocr.recognize({ image })` into a silent type mismatch, which is
//  exactly the path the translate plugin lives on.
//

import Foundation
import SnapzyPluginAPI
import XCTest

@testable import Snapzy

final class PluginHostPayloadTests: XCTestCase {
  private let sampleBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

  // MARK: - The envelope itself

  func testBinaryEnvelopeRoundTrips() {
    let envelope = SnapzyPluginIPC.binary(sampleBytes)
    XCTAssertEqual(SnapzyPluginIPC.binaryData(envelope), sampleBytes)
  }

  func testAnObjectThatMerelyContainsABase64KeyIsNotAnEnvelope() {
    // Two keys: this is a plugin's own object, not bytes. Treating it as
    // binary would corrupt a payload that happens to use the name.
    let ambiguous = JSONValue.object([
      "base64": .string(sampleBytes.base64EncodedString()),
      "note": .string("not an envelope"),
    ])
    XCTAssertNil(SnapzyPluginIPC.binaryData(ambiguous))
    XCTAssertEqual(ambiguous.normalizedBinaryEnvelopes, ambiguous)
  }

  // MARK: - Decoding typed requests

  func testOCRRequestDecodesNestedImageBytes() throws {
    let payload = JSONValue.object([
      "image": SnapzyPluginIPC.binary(sampleBytes),
      "language": .string("zh-Hans"),
      "coordinateSize": .object(["width": .double(800), "height": .double(600)]),
    ])

    let request = try payload.decodeHostCallPayload(as: PluginOCRRequest.self)

    XCTAssertEqual(request.image, sampleBytes)
    XCTAssertEqual(request.language, "zh-Hans")
    XCTAssertEqual(request.coordinateSize, SnapzySize(width: 800, height: 600))
  }

  func testHTTPRequestDecodesAnEnvelopedBody() throws {
    let payload = JSONValue.object([
      "url": .string("https://api.openai.com/v1/chat/completions"),
      "method": .string("POST"),
      "headers": .object(["Content-Type": .string("application/json")]),
      "body": SnapzyPluginIPC.binary(Data("{\"model\":\"x\"}".utf8)),
    ])

    let request = try payload.decodeHostCallPayload(as: PluginHTTPRequest.self)

    XCTAssertEqual(request.method, "POST")
    XCTAssertEqual(request.body.map { String(decoding: $0, as: UTF8.self) }, "{\"model\":\"x\"}")
  }

  func testImageOperationDecodesEnvelopedImage() throws {
    let payload = JSONValue.object([
      "operation": .string("resize"),
      "image": SnapzyPluginIPC.binary(sampleBytes),
      "targetSize": .object(["width": .double(64), "height": .double(64)]),
    ])

    let operation = try payload.decodeHostCallPayload(as: PluginImageOperation.self)

    XCTAssertEqual(operation.operation, "resize")
    XCTAssertEqual(operation.image, sampleBytes)
    XCTAssertEqual(operation.targetSize, SnapzySize(width: 64, height: 64))
  }

  // MARK: - Normalisation shape

  func testNormalisationReachesIntoArraysAndNestedObjects() {
    let payload = JSONValue.object([
      "items": .array([
        .object(["bytes": SnapzyPluginIPC.binary(sampleBytes)]),
        .string("untouched"),
      ])
    ])

    let normalized = payload.normalizedBinaryEnvelopes

    let nested = normalized["items"]?[0]?["bytes"]?.stringValue
    XCTAssertEqual(nested, sampleBytes.base64EncodedString())
    XCTAssertEqual(normalized["items"]?[1]?.stringValue, "untouched")
  }

  func testNormalisationLeavesOrdinaryPayloadsIdentical() {
    let payload = JSONValue.object([
      "operation": .string("duration"),
      "time": .double(1.5),
      "flags": .array([.bool(true), .null]),
    ])
    XCTAssertEqual(payload.normalizedBinaryEnvelopes, payload)
  }

  // MARK: - Declarative UI, which crosses the same boundary

  func testUIRequestDecodesFromTheHelperShape() throws {
    let payload = JSONValue.object([
      "kind": .string("form"),
      "form": .object([
        "title": .string("Translate needs an API key"),
        "fields": .array([
          .object([
            "name": .string("apiKey"),
            "label": .string("API key"),
            "kind": .string("secret"),
            "required": .bool(true),
          ])
        ]),
      ]),
    ])

    let request = try payload.decodeHostCallPayload(as: PluginUIRequest.self)

    guard case .form(let form) = request else {
      return XCTFail("Expected a form request.")
    }
    XCTAssertEqual(form.fields.first?.name, "apiKey")
    // A `secret` field is how a plugin asks for a credential without ever
    // rendering a window of its own.
    XCTAssertEqual(form.fields.first?.kind, "secret")
  }
}
