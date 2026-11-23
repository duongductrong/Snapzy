//
//  CustomUploaderTemplateTests.swift
//  SnapzyTests
//
//  JSONPath subset, regex, template rendering, response extraction, URL validation,
//  request building and multipart body layout for custom uploaders. No network.
//

import Foundation
import XCTest
@testable import Snapzy

final class CustomUploaderTemplateTests: XCTestCase {

  private var tempDirectory: URL!

  override func setUpWithError() throws {
    tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("CustomUploaderTemplateTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
  }

  // MARK: - Fixtures

  private let imgurResponse = Data("""
    {"data":{"id":"aBcD123","link":"https://i.imgur.com/aBcD123.png","deletehash":"xYz789",
    "size":68,"animated":false},"success":true,"status":200}
    """.utf8)

  private let ziplineResponse = Data("""
    {"files":[{"id":"clx1","url":"https://zipline.example.com/u/clx1.png","type":"image/png"}],"deletesAt":null}
    """.utf8)

  private let arrayResponse = Data("""
    [{"url":"https://cdn.example.com/a.png"},{"url":"https://cdn.example.com/b.png"}]
    """.utf8)

  private func response(_ body: Data, status: Int = 200, headers: [String: String] = [:]) -> CustomUploaderResponse {
    CustomUploaderResponse(statusCode: status, headers: headers, body: body)
  }

  private func response(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> CustomUploaderResponse {
    response(Data(text.utf8), status: status, headers: headers)
  }

  // MARK: - JSONPath

  func testJSONPath_parsesSupportedForms() {
    XCTAssertEqual(CustomUploaderJSONPath.parse("data.url"), [.key("data"), .key("url")])
    XCTAssertEqual(CustomUploaderJSONPath.parse("$.data.url"), [.key("data"), .key("url")])
    XCTAssertEqual(CustomUploaderJSONPath.parse("[0].url"), [.index(0), .key("url")])
    XCTAssertEqual(CustomUploaderJSONPath.parse("files[0][1]"), [.key("files"), .index(0), .index(1)])
    XCTAssertEqual(CustomUploaderJSONPath.parse(#"data["odd key"].x"#), [.key("data"), .key("odd key"), .key("x")])
    XCTAssertEqual(CustomUploaderJSONPath.parse("data['k']"), [.key("data"), .key("k")])
  }

  func testJSONPath_rejectsMalformedPaths() {
    XCTAssertNil(CustomUploaderJSONPath.parse("a..b"))
    XCTAssertNil(CustomUploaderJSONPath.parse("a."))
    XCTAssertNil(CustomUploaderJSONPath.parse("a[0"))
    XCTAssertNil(CustomUploaderJSONPath.parse("a]"))
    XCTAssertNil(CustomUploaderJSONPath.parse("a[-1]"))
    XCTAssertNil(CustomUploaderJSONPath.parse("a[x]"))
  }

  func testJSONPath_evaluatesFixtures() {
    XCTAssertEqual(CustomUploaderJSONPath.string(at: "data.link", inJSON: imgurResponse), "https://i.imgur.com/aBcD123.png")
    XCTAssertEqual(CustomUploaderJSONPath.string(at: "data.size", inJSON: imgurResponse), "68")
    XCTAssertEqual(CustomUploaderJSONPath.string(at: "data.animated", inJSON: imgurResponse), "false")
    XCTAssertEqual(CustomUploaderJSONPath.string(at: "files[0].url", inJSON: ziplineResponse), "https://zipline.example.com/u/clx1.png")
    XCTAssertEqual(CustomUploaderJSONPath.string(at: "[1].url", inJSON: arrayResponse), "https://cdn.example.com/b.png")
    XCTAssertNil(CustomUploaderJSONPath.string(at: "files[3].url", inJSON: ziplineResponse))
    XCTAssertNil(CustomUploaderJSONPath.string(at: "deletesAt", inJSON: ziplineResponse), "JSON null reads as missing")
    XCTAssertNil(CustomUploaderJSONPath.string(at: "data.link", inJSON: Data("not json".utf8)))
  }

  // MARK: - Regex

  func testRegex_firstGroupElseWholeMatch() throws {
    let text = #"<a href="https://host.example/i/42.png">done</a>"#
    XCTAssertEqual(try CustomUploaderRegex.firstMatch(#"href="([^"]+)""#, in: text), "https://host.example/i/42.png")
    XCTAssertEqual(try CustomUploaderRegex.firstMatch(#"https://\S+?\.png"#, in: text), "https://host.example/i/42.png")
    XCTAssertEqual(try CustomUploaderRegex.firstMatch(#"(https)://(\S+?)""#, in: text, group: 2), "host.example/i/42.png")
    XCTAssertNil(try CustomUploaderRegex.firstMatch("nomatch", in: text))
    XCTAssertNil(try CustomUploaderRegex.firstMatch("(a)", in: "a", group: 5))
  }

  func testRegex_invalidPatternThrows() {
    XCTAssertThrowsError(try CustomUploaderRegex.firstMatch("([", in: "x")) { error in
      XCTAssertEqual(error as? CustomUploaderError, .invalidRegex("(["))
    }
  }

  func testRegex_splitArgumentKeepsAlternation() {
    XCTAssertEqual(CustomUploaderRegex.splitArgument("url=(\\S+)|1").pattern, "url=(\\S+)")
    XCTAssertEqual(CustomUploaderRegex.splitArgument("url=(\\S+)|1").group, 1)
    XCTAssertEqual(CustomUploaderRegex.splitArgument("png|jpg").pattern, "png|jpg")
    XCTAssertNil(CustomUploaderRegex.splitArgument("png|jpg").group)
  }

  // MARK: - Template

  func testTemplate_parsesTokensEscapesAndNestedBraces() {
    let segments = CustomUploaderTemplate.parse(#"https://x/{json:id}?n=\{literal\}&r={regex:\d{3}}"#)
    XCTAssertEqual(segments, [
      .literal("https://x/"),
      .token(name: "json", argument: "id"),
      .literal("?n={literal}&r="),
      .token(name: "regex", argument: #"\d{3}"#),
    ])
    XCTAssertEqual(CustomUploaderTemplate.parse("{ not a token }"), [.literal("{ not a token }")])
    XCTAssertEqual(CustomUploaderTemplate.parse("{unclosed"), [.literal("{unclosed")])
  }

  func testTemplateExtractor_combinesJSONHeaderAndFilename() throws {
    let extractor = CustomUploader.ResponseExtractor.template(
      "https://imgur.com/delete/{json:data.deletehash}?f={filename}&r={header:X-Request-Id}"
    )
    let value = try CustomUploaderResponseParser.extract(
      extractor,
      from: response(imgurResponse, headers: ["X-Request-Id": "req-9"]),
      fileName: "shot.png"
    )
    XCTAssertEqual(value, "https://imgur.com/delete/xYz789?f=shot.png&r=req-9")
  }

  func testTemplateExtractor_regexWithGroupAndResponseToken() throws {
    let text = "OK url=https://files.example/abc.png id=abc"
    XCTAssertEqual(
      try CustomUploaderResponseParser.extract(.template("{regex:url=(\\S+)|1}"), from: response(text)),
      "https://files.example/abc.png"
    )
    XCTAssertEqual(try CustomUploaderResponseParser.extract(.template("{response}"), from: response("  hi \n")), "hi")
  }

  func testExtractor_errorsForMissingValueBadPathAndUnknownToken() {
    XCTAssertThrowsError(try CustomUploaderResponseParser.extract(.jsonPath("data.nope"), from: response(imgurResponse))) {
      XCTAssertEqual($0 as? CustomUploaderError, .valueNotFound(field: "URL"))
    }
    XCTAssertThrowsError(try CustomUploaderResponseParser.extract(.jsonPath("data..link"), from: response(imgurResponse))) {
      XCTAssertEqual($0 as? CustomUploaderError, .invalidJSONPath("data..link"))
    }
    XCTAssertThrowsError(try CustomUploaderResponseParser.extract(.template("{random:a|b}"), from: response("x"))) {
      XCTAssertEqual($0 as? CustomUploaderError, .unsupportedToken("{random:a|b}"))
    }
    XCTAssertThrowsError(try CustomUploaderResponseParser.extract(.plainText, from: response("   "))) {
      XCTAssertEqual($0 as? CustomUploaderError, .valueNotFound(field: "URL"))
    }
  }

  // MARK: - URL validation

  func testURLValidator_acceptsOnlyAbsoluteWebURLs() {
    XCTAssertNotNil(CustomUploaderURLValidator.validatedWebURL("https://i.example.com/a.png"))
    XCTAssertNotNil(CustomUploaderURLValidator.validatedWebURL("  http://localhost:8080/a  "))
    XCTAssertNil(CustomUploaderURLValidator.validatedWebURL("file:///etc/passwd"))
    XCTAssertNil(CustomUploaderURLValidator.validatedWebURL("javascript:alert(1)"))
    XCTAssertNil(CustomUploaderURLValidator.validatedWebURL("JavaScript:alert(1)"))
    XCTAssertNil(CustomUploaderURLValidator.validatedWebURL("data:text/html,hi"))
    XCTAssertNil(CustomUploaderURLValidator.validatedWebURL("ftp://example.com/a"))
    XCTAssertNil(CustomUploaderURLValidator.validatedWebURL("/relative/path.png"))
    XCTAssertNil(CustomUploaderURLValidator.validatedWebURL("https://"))
  }

  func testExtraction_rejectsNonWebResultAndDropsBadOptionalLinks() throws {
    let uploader = CustomUploader(
      name: "t", url: "https://x", responseURL: .jsonPath("url"), deletionURL: .jsonPath("del")
    )
    XCTAssertThrowsError(
      try CustomUploaderResponseParser.extraction(
        from: response(#"{"url":"javascript:alert(1)"}"#), uploader: uploader, fileName: "a.png"
      )
    ) {
      XCTAssertEqual($0 as? CustomUploaderError, .invalidResultURL(field: "URL"))
    }
    XCTAssertThrowsError(
      try CustomUploaderResponseParser.extraction(
        from: response(#"{"url":"file:///tmp/a.png"}"#), uploader: uploader, fileName: "a.png"
      )
    )

    let extraction = try CustomUploaderResponseParser.extraction(
      from: response(#"{"url":"https://h/a.png","del":"file:///x"}"#), uploader: uploader, fileName: "a.png"
    )
    XCTAssertEqual(extraction.url.absoluteString, "https://h/a.png")
    XCTAssertNil(extraction.deletionURL, "A non-web deletion link is dropped, not an error")
  }

  func testErrorMessage_prefersExtractorThenBodyThenStatusText() {
    let uploader = CustomUploader(name: "t", url: "https://x", errorMessage: .jsonPath("error.message"))
    XCTAssertEqual(
      CustomUploaderResponseParser.errorMessage(
        for: response(#"{"error":{"message":"Quota exceeded"}}"#, status: 429), uploader: uploader
      ),
      "Quota exceeded"
    )
    XCTAssertEqual(
      CustomUploaderResponseParser.errorMessage(for: response("Bad token", status: 401), uploader: uploader),
      "Bad token"
    )
    XCTAssertFalse(CustomUploaderResponseParser.errorMessage(for: response("", status: 500), uploader: uploader).isEmpty)
  }

  // MARK: - Request building

  func testResolve_rendersSecretsFilenameAndQuery() throws {
    let uploader = CustomUploader(
      name: "t",
      method: .put,
      url: "https://up.example.com/files/{filename}",
      headers: [.init("Authorization", "Bearer {secret:TOKEN}"), .init("  ", "ignored")],
      query: [.init("expires", "1+day"), .init("key", "{secret:TOKEN}")],
      body: .binary,
      timeout: 0
    )
    let resolved = try CustomUploaderRequestBuilder.resolve(
      uploader, fileName: "my shot.png", secrets: StubSecrets(["TOKEN": "s3cr&t"])
    )
    XCTAssertEqual(resolved.method, "PUT")
    XCTAssertEqual(resolved.headers, [.init("Authorization", "Bearer s3cr&t")])
    XCTAssertEqual(resolved.timeout, CustomUploader.defaultTimeout)
    XCTAssertEqual(resolved.url.path, "/files/my shot.png")
    XCTAssertTrue(resolved.url.absoluteString.contains("/files/my%20shot.png"))
    XCTAssertTrue(resolved.url.absoluteString.contains("expires=1%2Bday"))
    XCTAssertTrue(resolved.url.absoluteString.contains("key=s3cr%26t"))
  }

  func testResolve_wholeURLSecretStaysAURL() throws {
    let uploader = CustomUploader(name: "t", url: "{secret:WEBHOOK}")
    let resolved = try CustomUploaderRequestBuilder.resolve(
      uploader, fileName: "a.png", secrets: StubSecrets(["WEBHOOK": "https://hooks.example.com/x?y=1"])
    )
    XCTAssertEqual(resolved.url.absoluteString, "https://hooks.example.com/x?y=1")
  }

  func testResolve_unresolvedSecretFailsWithoutLiteral() {
    let uploader = CustomUploader(name: "t", url: "https://x.example.com", headers: [.init("Authorization", "{secret:MISSING}")])
    XCTAssertThrowsError(try CustomUploaderRequestBuilder.resolve(uploader, fileName: "a.png", secrets: StubSecrets([:]))) {
      XCTAssertEqual($0 as? CustomUploaderError, .unresolvedSecret("MISSING"))
    }
    XCTAssertThrowsError(try CustomUploaderRequestBuilder.resolve(uploader, fileName: "a.png", secrets: nil)) {
      XCTAssertEqual($0 as? CustomUploaderError, .unresolvedSecret("MISSING"))
    }
  }

  func testResolve_rejectsNonWebRequestURLsAndUnsupportedTokens() {
    for url in ["file:///tmp/x", "javascript:alert(1)", "ftp://x.example.com", "not a url", ""] {
      XCTAssertThrowsError(
        try CustomUploaderRequestBuilder.resolve(CustomUploader(name: "t", url: url), fileName: "a", secrets: nil),
        url
      ) {
        XCTAssertEqual($0 as? CustomUploaderError, .invalidRequestURL)
      }
    }
    XCTAssertThrowsError(
      try CustomUploaderRequestBuilder.resolve(
        CustomUploader(name: "t", url: "https://x.example.com/{random:a|b}"), fileName: "a", secrets: nil
      )
    ) {
      XCTAssertEqual($0 as? CustomUploaderError, .unsupportedToken("{random:a|b}"))
    }
  }

  func testFormURLEncoded_percentEncodesEverything() {
    let data = CustomUploaderRequestBuilder.formURLEncoded([.init("a b", "c&d=e"), .init("k", "ü+")])
    XCTAssertEqual(String(data: data, encoding: .utf8), "a%20b=c%26d%3De&k=%C3%BC%2B")
  }

  // MARK: - Multipart

  func testMultipart_writesFieldsInOrderThenFileThenClosing() throws {
    let file = tempDirectory.appendingPathComponent("shot.png")
    let fileBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
    try fileBytes.write(to: file)
    let destination = tempDirectory.appendingPathComponent("body.multipart")
    let boundary = "TestBoundary-123"

    let written = try CustomUploaderMultipartBody.write(
      fields: [.init("token", "abc"), .init("album", "2"), .init("x\"y", "v")],
      fileField: "image",
      fileURL: file,
      fileName: "my\"shot.png",
      contentType: "image/png",
      boundary: boundary,
      to: destination
    )
    let body = try Data(contentsOf: destination)
    XCTAssertEqual(Int64(body.count), written)

    let header = """
      --TestBoundary-123\r
      Content-Disposition: form-data; name="token"\r
      \r
      abc\r
      --TestBoundary-123\r
      Content-Disposition: form-data; name="album"\r
      \r
      2\r
      --TestBoundary-123\r
      Content-Disposition: form-data; name="x%22y"\r
      \r
      v\r
      --TestBoundary-123\r
      Content-Disposition: form-data; name="image"; filename="my%22shot.png"\r
      Content-Type: image/png\r
      \r

      """
    var expected = Data(header.utf8)
    expected.append(fileBytes)
    expected.append(Data("\r\n--TestBoundary-123--\r\n".utf8))
    XCTAssertEqual(body, expected)

    XCTAssertEqual(
      CustomUploaderMultipartBody.contentTypeHeader(boundary: boundary),
      "multipart/form-data; boundary=TestBoundary-123"
    )
    XCTAssertTrue(CustomUploaderMultipartBody.makeBoundary().hasPrefix("SnapzyBoundary-"))
  }

  // MARK: - Codable

  func testCodable_roundTripsAndToleratesMissingFields() throws {
    let uploader = CustomUploader(
      name: "Zipline",
      method: .patch,
      url: "https://z.example.com/api/upload",
      headers: [.init("Authorization", "{secret:Z}")],
      query: [.init("a", "1")],
      body: .formURLEncoded(fields: [.init("f", "v")]),
      responseURL: .regex("u=(\\S+)"),
      thumbnailURL: .plainText,
      deletionURL: .template("{json:d}"),
      errorMessage: .jsonPath("error"),
      timeout: 30
    )
    let decoded = try JSONDecoder().decode(CustomUploader.self, from: JSONEncoder().encode(uploader))
    XCTAssertEqual(decoded, uploader)

    let sparse = try JSONDecoder().decode(
      CustomUploader.self,
      from: Data(#"{"name":"S","url":"https://s","method":"delete","body":{"type":"weird"},"timeout":-5}"#.utf8)
    )
    XCTAssertEqual(sparse.method, .post)
    XCTAssertEqual(sparse.body, .multipart(fileField: "file", extraFields: []))
    XCTAssertEqual(sparse.responseURL, .plainText)
    XCTAssertEqual(sparse.timeout, CustomUploader.defaultTimeout)
  }
}

// MARK: - Secrets stub

final class StubSecrets: CustomUploaderSecretResolving {
  private(set) var values: [String: String]

  init(_ values: [String: String]) {
    self.values = values
  }

  func secretValue(named name: String) -> String? {
    values[name]
  }

  func storeSecret(name: String, value: String) throws {
    values[name] = value
  }
}
