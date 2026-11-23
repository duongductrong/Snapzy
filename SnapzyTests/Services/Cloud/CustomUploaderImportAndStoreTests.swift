//
//  CustomUploaderImportAndStoreTests.swift
//  SnapzyTests
//
//  ShareX .sxcu import against realistic samples, secret candidates, and the
//  UserDefaults-backed uploader store (round-trip and 20-uploader limit).
//

import Foundation
import XCTest
@testable import Snapzy

final class CustomUploaderImportAndStoreTests: XCTestCase {

  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUpWithError() throws {
    suiteName = "CustomUploaderImportAndStoreTests-\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: suiteName)
  }

  // MARK: - Samples

  private let imgurSample = """
    {
      "Version": "13.1.0",
      "Name": "Imgur (anonymous)",
      "DestinationType": "ImageUploader",
      "RequestMethod": "POST",
      "RequestURL": "https://api.imgur.com/3/image",
      "Headers": {
        "Authorization": "Client-ID 1a2b3c4d5e6f7g8"
      },
      "Body": "MultipartFormData",
      "FileFormName": "image",
      "URL": "{json:data.link}",
      "DeletionURL": "https://imgur.com/delete/{json:data.deletehash}",
      "ErrorMessage": "{json:data.error}"
    }
    """

  private let cheveretoSample = """
    {
      "Version": "14.1.0",
      "Name": "Chevereto",
      "DestinationType": "ImageUploader, FileUploader",
      "RequestMethod": "POST",
      "RequestURL": "https://demo.chevereto.com/api/1/upload",
      "Parameters": {
        "key": "chv_T0pS3cr3t",
        "format": "json"
      },
      "Body": "MultipartFormData",
      "FileFormName": "source",
      "URL": "{json:image.url}",
      "ThumbnailURL": "{json:image.thumb.url}",
      "DeletionURL": "{json:image.delete_url}",
      "ErrorMessage": "{json:error.message}"
    }
    """

  private let ziplineSample = """
    {
      "Version": "14.1.0",
      "Name": "Zipline",
      "DestinationType": "ImageUploader, TextUploader, FileUploader",
      "RequestMethod": "POST",
      "RequestURL": "https://zipline.example.com/api/upload",
      "Headers": {
        "authorization": "zpl_token_abc123",
        "x-zipline-format": "random",
        "x-zipline-original-name": "true"
      },
      "Body": "MultipartFormData",
      "FileFormName": "file",
      "URL": "{json:files[0].url}",
      "ErrorMessage": "{json:error}"
    }
    """

  /// Older XBackBone export: legacy `$…$` syntax, no Name, credential in Arguments.
  private let xbackboneSample = """
    {
      "Version": "12.4.1",
      "DestinationType": "ImageUploader, TextUploader, FileUploader",
      "RequestType": "POST",
      "RequestURL": "https://xbackbone.example.com/upload",
      "FileFormName": "upload",
      "Arguments": {
        "file": "$filename$",
        "text": "$input$",
        "token": "token_5f3c9a1b2c"
      },
      "URL": "$json:url$"
    }
    """

  private let unsupportedSample = """
    {
      "Name": "Odd",
      "RequestMethod": "GET",
      "RequestURL": "https://odd.example.com/{random:a|b}/up",
      "Body": "JSON",
      "Data": "{\\"file\\":\\"{base64}\\"}",
      "ResponseType": "RedirectionURL",
      "URL": "$regex:1,1$",
      "RegexList": ["url=(\\\\S+)"]
    }
    """

  private func importSample(_ json: String, fallbackName: String = "") throws -> CustomUploaderImportResult {
    try CustomUploaderSXCUImporter.importUploader(from: Data(json.utf8), fallbackName: fallbackName)
  }

  // MARK: - Import

  func testImport_imgurLike() throws {
    let result = try importSample(imgurSample)
    let uploader = result.uploader
    XCTAssertEqual(uploader.name, "Imgur (anonymous)")
    XCTAssertEqual(uploader.method, .post)
    XCTAssertEqual(uploader.url, "https://api.imgur.com/3/image")
    XCTAssertEqual(uploader.headers, [.init("Authorization", "Client-ID 1a2b3c4d5e6f7g8")])
    XCTAssertEqual(uploader.body, .multipart(fileField: "image", extraFields: []))
    XCTAssertEqual(uploader.responseURL, .jsonPath("data.link"))
    XCTAssertEqual(uploader.deletionURL, .template("https://imgur.com/delete/{json:data.deletehash}"))
    XCTAssertEqual(uploader.errorMessage, .jsonPath("data.error"))
    XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
    XCTAssertEqual(result.secretCandidates.map(\.id), ["header:Authorization"])
    XCTAssertEqual(result.secretCandidates.first?.suggestedSecretName, "IMGUR_ANONYMOUS_AUTHORIZATION")

    // The imported definition works against a realistic response.
    let response = CustomUploaderResponse(
      statusCode: 200,
      body: Data(#"{"data":{"link":"https://i.imgur.com/Q1.png","deletehash":"dh1"},"success":true}"#.utf8)
    )
    let extraction = try CustomUploaderResponseParser.extraction(from: response, uploader: uploader, fileName: "a.png")
    XCTAssertEqual(extraction.url.absoluteString, "https://i.imgur.com/Q1.png")
    XCTAssertEqual(extraction.deletionURL?.absoluteString, "https://imgur.com/delete/dh1")
  }

  func testImport_chevereto() throws {
    let result = try importSample(cheveretoSample)
    XCTAssertEqual(result.uploader.query, [.init("key", "chv_T0pS3cr3t"), .init("format", "json")], "Source order is kept")
    XCTAssertEqual(result.uploader.body, .multipart(fileField: "source", extraFields: []))
    XCTAssertEqual(result.uploader.thumbnailURL, .jsonPath("image.thumb.url"))
    XCTAssertEqual(result.uploader.deletionURL, .jsonPath("image.delete_url"))
    XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
    XCTAssertEqual(result.secretCandidates.map(\.id), ["query:key"])
    XCTAssertEqual(result.secretCandidates.first?.suggestedSecretName, "CHEVERETO_KEY")
  }

  func testImport_zipline() throws {
    let result = try importSample(ziplineSample)
    XCTAssertEqual(
      result.uploader.headers.map(\.key),
      ["authorization", "x-zipline-format", "x-zipline-original-name"]
    )
    XCTAssertEqual(result.uploader.responseURL, .jsonPath("files[0].url"))
    XCTAssertTrue(result.warnings.isEmpty, "\(result.warnings)")
    XCTAssertEqual(result.secretCandidates.map(\.id), ["header:authorization"])
    XCTAssertEqual(result.secretCandidates.first?.suggestedSecretName, "ZIPLINE_AUTHORIZATION")
  }

  func testImport_xbackboneLegacySyntax() throws {
    let result = try importSample(xbackboneSample, fallbackName: "xbackbone-uploader")
    let uploader = result.uploader
    XCTAssertEqual(uploader.name, "xbackbone-uploader", "Missing Name falls back to the file name")
    XCTAssertEqual(uploader.method, .post)
    XCTAssertEqual(
      uploader.body,
      .multipart(
        fileField: "upload",
        extraFields: [.init("file", "{filename}"), .init("text", "{input}"), .init("token", "token_5f3c9a1b2c")]
      )
    )
    XCTAssertEqual(uploader.responseURL, .jsonPath("url"))
    XCTAssertEqual(result.warnings, [.unsupportedToken(field: "Arguments", token: "{input}")])
    XCTAssertEqual(result.secretCandidates.map(\.id), ["bodyField:token"])
    XCTAssertEqual(result.secretCandidates.first?.suggestedSecretName, "XBACKBONE_UPLOADER_TOKEN")
  }

  func testImport_reportsUnsupportedSyntaxAsWarnings() throws {
    let result = try importSample(unsupportedSample)
    XCTAssertEqual(result.uploader.method, .post)
    XCTAssertEqual(result.uploader.responseURL, .regex("url=(\\S+)|1"))
    XCTAssertTrue(result.warnings.contains(.unsupportedMethod("GET")))
    XCTAssertTrue(result.warnings.contains(.unsupportedBody("JSON")))
    XCTAssertTrue(result.warnings.contains(.ignoredField("Data")))
    XCTAssertTrue(result.warnings.contains(.ignoredField("ResponseType")))
    XCTAssertTrue(result.warnings.contains(.unsupportedToken(field: "RequestURL", token: "{random:a|b}")))
    XCTAssertTrue(result.warnings.allSatisfy { !$0.message.isEmpty })
  }

  func testImport_rejectsInvalidFiles() {
    for json in ["not json", "[]", #"{"Name":"No URL"}"#] {
      XCTAssertThrowsError(try importSample(json), json) {
        XCTAssertEqual($0 as? CustomUploaderError, .invalidImportFile)
      }
    }
  }

  func testStoreSecret_replacesValueWithReference() throws {
    let result = try importSample(ziplineSample)
    var uploader = result.uploader
    let secrets = StubSecrets([:])
    let candidate = try XCTUnwrap(result.secretCandidates.first)

    try CustomUploaderSXCUImporter.storeSecret(candidate, secretName: "ZIPLINE_TOKEN", in: &uploader, provider: secrets)

    XCTAssertEqual(secrets.values, ["ZIPLINE_TOKEN": "zpl_token_abc123"])
    XCTAssertEqual(uploader.headers.first, .init("authorization", "{secret:ZIPLINE_TOKEN}"))
    XCTAssertTrue(CustomUploaderSXCUImporter.secretCandidates(in: uploader).isEmpty)
    XCTAssertNil(try JSONEncoder().encode(uploader).range(of: Data("zpl_token_abc123".utf8)))

    // Invalid names are refused without touching anything.
    var untouched = result.uploader
    try CustomUploaderSXCUImporter.storeSecret(candidate, secretName: "bad name!", in: &untouched, provider: secrets)
    XCTAssertEqual(untouched, result.uploader)
  }

  func testSecretNames() {
    XCTAssertTrue(CustomUploaderSecrets.isValidName("ZIPLINE_TOKEN.v2-a"))
    XCTAssertFalse(CustomUploaderSecrets.isValidName(""))
    XCTAssertFalse(CustomUploaderSecrets.isValidName("has space"))
    XCTAssertFalse(CustomUploaderSecrets.isValidName(String(repeating: "A", count: 65)))
    XCTAssertEqual(CustomUploaderSecrets.suggestedName(uploaderName: "My Host!", fieldName: "x-api-key"), "MY_HOST_X_API_KEY")
    XCTAssertEqual(CustomUploaderSecrets.suggestedName(uploaderName: "", fieldName: ""), "SECRET")
  }

  // MARK: - Store

  func testStore_roundTripsThroughUserDefaults() throws {
    let store = CustomUploaderStore(defaults: defaults, storageKey: "test.uploaders")
    XCTAssertTrue(store.uploaders.isEmpty)

    let first = try store.add(CustomUploader(name: "One", url: "https://one.example.com"))
    let second = try store.add(CustomUploader(name: "Two", url: "https://two.example.com"))
    var edited = first
    edited.name = "One (edited)"
    XCTAssertTrue(store.update(edited))
    XCTAssertFalse(store.update(CustomUploader(name: "Ghost", url: "https://g")))
    let copy = try XCTUnwrap(store.duplicate(id: second.id, nameFormatter: { "\($0) copy" }))
    XCTAssertNotEqual(copy.id, second.id)

    let reloaded = CustomUploaderStore(defaults: defaults, storageKey: "test.uploaders")
    XCTAssertEqual(reloaded.uploaders.map(\.name), ["One (edited)", "Two", "Two copy"])
    XCTAssertEqual(reloaded.uploader(id: second.id)?.url, "https://two.example.com")

    reloaded.delete(id: first.id)
    XCTAssertEqual(CustomUploaderStore(defaults: defaults, storageKey: "test.uploaders").uploaders.count, 2)
  }

  func testStore_clashingIdGetsFreshId() throws {
    let store = CustomUploaderStore(defaults: defaults, storageKey: "test.uploaders")
    let original = try store.add(CustomUploader(name: "A", url: "https://a"))
    let clash = try store.add(CustomUploader(id: original.id, name: "B", url: "https://b"))
    XCTAssertNotEqual(clash.id, original.id)
    XCTAssertEqual(store.uploaders.count, 2)
  }

  func testStore_enforcesTwentyUploaderLimit() throws {
    let store = CustomUploaderStore(defaults: defaults, storageKey: "test.uploaders")
    for index in 0..<CustomUploaderStore.maxUploaders {
      try store.add(CustomUploader(name: "U\(index)", url: "https://u\(index).example.com"))
    }
    XCTAssertEqual(CustomUploaderStore.maxUploaders, 20)
    XCTAssertFalse(store.canAdd)
    XCTAssertThrowsError(try store.add(CustomUploader(name: "Extra", url: "https://x"))) {
      XCTAssertEqual($0 as? CustomUploaderError, .limitReached(20))
    }
    XCTAssertThrowsError(try store.duplicate(id: store.uploaders[0].id)) {
      XCTAssertEqual($0 as? CustomUploaderError, .limitReached(20))
    }
    XCTAssertEqual(CustomUploaderStore(defaults: defaults, storageKey: "test.uploaders").uploaders.count, 20)
  }

  func testStore_ignoresCorruptData() {
    defaults.set(Data("garbage".utf8), forKey: "test.uploaders")
    XCTAssertTrue(CustomUploaderStore(defaults: defaults, storageKey: "test.uploaders").uploaders.isEmpty)
  }
}
