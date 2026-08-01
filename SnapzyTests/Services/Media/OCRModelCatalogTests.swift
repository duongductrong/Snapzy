//
//  OCRModelCatalogTests.swift
//  SnapzyTests
//
//  Catalog shape, URLs, and size accounting coverage.
//

import XCTest
@testable import Snapzy

final class OCRModelCatalogTests: XCTestCase {

  func testCatalogContainsThreeModelsInOrder() {
    XCTAssertEqual(
      OCRModelCatalog.all.map(\.id),
      ["ppocrv6-tiny", "ppocrv6-small", "ppocrv6-medium"]
    )
  }

  func testDefinitionsHaveExpectedMetadata() {
    let tiny = OCRModelCatalog.definition(for: "ppocrv6-tiny")
    XCTAssertEqual(tiny?.displayName, "PP-OCRv6 Tiny")
    XCTAssertEqual(tiny?.parameterCountLabel, "1.5M")
    XCTAssertEqual(tiny?.fp32SizeLabel, "6–8 MB")
    XCTAssertEqual(tiny?.int8SizeLabel, "2–4 MB")

    let small = OCRModelCatalog.definition(for: "ppocrv6-small")
    XCTAssertEqual(small?.displayName, "PP-OCRv6 Small")
    XCTAssertEqual(small?.parameterCountLabel, "7.7M")
    XCTAssertEqual(small?.fp32SizeLabel, "31–40 MB")
    XCTAssertEqual(small?.int8SizeLabel, "8–15 MB")

    let medium = OCRModelCatalog.definition(for: "ppocrv6-medium")
    XCTAssertEqual(medium?.displayName, "PP-OCRv6 Medium")
    XCTAssertEqual(medium?.parameterCountLabel, "34.5M")
    XCTAssertEqual(medium?.fp32SizeLabel, "138–160 MB")
    XCTAssertEqual(medium?.int8SizeLabel, "35–55 MB")
  }

  func testEveryModelShipsDetRecAndDictFiles() {
    for definition in OCRModelCatalog.all {
      XCTAssertEqual(definition.files.map(\.name), ["det.onnx", "rec.onnx", "dict.txt"], definition.id)
    }
  }

  func testAllFileURLsUseHTTPS() {
    for definition in OCRModelCatalog.all {
      for file in definition.files {
        XCTAssertEqual(file.url.scheme, "https", "\(definition.id)/\(file.name)")
      }
    }
  }

  func testONNXFilesDeclareSHA256AndByteSize() {
    for definition in OCRModelCatalog.all {
      for file in definition.files where file.name.hasSuffix(".onnx") {
        XCTAssertEqual(file.sha256?.count, 64, "\(definition.id)/\(file.name)")
        XCTAssertNotNil(file.expectedBytes, "\(definition.id)/\(file.name)")
      }
    }
  }

  func testDictFilesHaveNoChecksum() {
    for definition in OCRModelCatalog.all {
      let dict = definition.files.first { $0.name == "dict.txt" }
      XCTAssertNotNil(dict, definition.id)
      XCTAssertNil(dict?.sha256, definition.id)
    }
  }

  func testTotalDownloadBytesMatchesFileSizeSums() {
    XCTAssertEqual(
      OCRModelCatalog.definition(for: "ppocrv6-tiny")?.totalDownloadBytes,
      1_780_590 + 4_462_639
    )
    XCTAssertEqual(
      OCRModelCatalog.definition(for: "ppocrv6-small")?.totalDownloadBytes,
      9_880_512 + 21_159_378
    )
    XCTAssertEqual(
      OCRModelCatalog.definition(for: "ppocrv6-medium")?.totalDownloadBytes,
      62_032_837 + 76_554_979
    )
  }

  func testDefinitionLookupHitReturnsMatchingDefinition() {
    let definition = OCRModelCatalog.definition(for: "ppocrv6-small")
    XCTAssertEqual(definition?.id, "ppocrv6-small")
  }

  func testDefinitionLookupMissReturnsNil() {
    XCTAssertNil(OCRModelCatalog.definition(for: "ppocrv5-tiny"))
    XCTAssertNil(OCRModelCatalog.definition(for: ""))
  }
}
