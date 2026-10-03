//
//  DataMD5Tests.swift
//  SnapzyTests
//
//  Regression tests for the S3 Content-MD5 Base64 contract.
//

import XCTest
@testable import Snapzy

final class DataMD5Tests: XCTestCase {
  func testMD5Base64_matchesRFC1321KnownVector() {
    XCTAssertEqual(
      Data("hello".utf8).md5Base64(),
      "XUFAKrxLKna5cZ2REBfFkg=="
    )
  }

  func testMD5Base64_handlesEmptyData() {
    XCTAssertEqual(
      Data().md5Base64(),
      "1B2M2Y8AsgTpgAmY7PhCfg=="
    )
  }
}
