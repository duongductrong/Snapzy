//
//  SimpleTOMLParserTests.swift
//  SnapzyTests
//
//  Unit tests for the focused TOML parser used by config import.
//

import XCTest
@testable import Snapzy

@MainActor
final class SimpleTOMLParserTests: XCTestCase {
  func testParsesNestedTablesArraysAndComments() throws {
    let source = """
    schema_version = 1

    [general]
    language = "system" # comment
    play_sounds = true

    [shortcuts.global.fullscreen]
    key = "3"
    modifiers = ["command", "shift"]
    enabled = true
    """

    let document = try SimpleTOMLParser.parse(source)

    XCTAssertEqual(document.value(at: "schema_version")?.intValue, 1)
    XCTAssertEqual(document.value(at: "general", "language")?.stringValue, "system")
    XCTAssertEqual(document.value(at: "general", "play_sounds")?.boolValue, true)
    XCTAssertEqual(
      document.value(at: "shortcuts", "global", "fullscreen", "modifiers")?.stringArrayValue,
      ["command", "shift"]
    )
  }

  func testTableDeclarationPreservesExistingDottedKeys() throws {
    let source = """
    general.language = "system"

    [general]
    play_sounds = false
    """

    let document = try SimpleTOMLParser.parse(source)

    XCTAssertEqual(document.value(at: "general", "language")?.stringValue, "system")
    XCTAssertEqual(document.value(at: "general", "play_sounds")?.boolValue, false)
  }

  func testInvalidValueReportsLine() {
    XCTAssertThrowsError(try SimpleTOMLParser.parse("schema_version = nope")) { error in
      XCTAssertEqual(error as? SimpleTOMLError, .invalidValue(1, "nope"))
    }
  }

  func testUnescapePreservesBackslashFollowedByN() throws {
    // In TOML, `\\` is an escaped backslash, so the quoted literal "a\\nb"
    // decodes to the 4-char value a, \, n, b — NOT "a" + newline + "b".
    let document = try SimpleTOMLParser.parse(#"key = "a\\nb""#)

    XCTAssertEqual(document.value(at: "key")?.stringValue, "a\\nb")
    XCTAssertEqual(document.value(at: "key")?.stringValue?.count, 4)
  }

  func testUnescapePreservesBackslashFollowedByT() throws {
    // Mirror of the above for `\t`: the literal "a\\tb" decodes to a, \, t, b.
    let document = try SimpleTOMLParser.parse(#"key = "a\\tb""#)

    XCTAssertEqual(document.value(at: "key")?.stringValue, "a\\tb")
    XCTAssertEqual(document.value(at: "key")?.stringValue?.count, 4)
  }

  func testRoundTripPreservesBackslashFollowedByNAndT() throws {
    // A stored value that literally contains a backslash followed by n/t must
    // survive a writer → parser round-trip. Real newline/tab are mixed in to
    // prove the legitimate `\n` / `\t` escapes still round-trip too.
    let original = "a\\nb\nc\td" // a, \, n, b, <newline>, c, <tab>, d
    var writer = SimpleTOMLWriter()
    writer.value("key", original)

    let document = try SimpleTOMLParser.parse(writer.output)

    XCTAssertEqual(document.value(at: "key")?.stringValue, original)
    XCTAssertEqual(document.value(at: "key")?.stringValue?.count, original.count)
  }

  func testRoundTripPreservesEmbeddedDoubleQuote() throws {
    // An embedded double quote is the one remaining escape `quote()` emits
    // (`\"`); guard that the `\"` → `"` branch round-trips so it cannot be
    // silently removed.
    let original = "a\"b" // a, ", b
    var writer = SimpleTOMLWriter()
    writer.value("key", original)

    let document = try SimpleTOMLParser.parse(writer.output)

    XCTAssertEqual(document.value(at: "key")?.stringValue, original)
    XCTAssertEqual(document.value(at: "key")?.stringValue?.count, 3)
  }
}
