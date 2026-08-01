//
//  OCRKeychainStoreTests.swift
//  SnapzyTests
//
//  Real Keychain round-trip coverage for custom OCR endpoint API keys.
//

import XCTest
@testable import Snapzy

final class OCRKeychainStoreTests: XCTestCase {
  private let store = OCRKeychainStore()
  private var usedModelIDs: [UUID] = []

  override func tearDown() {
    for id in usedModelIDs {
      store.deleteKey(for: id)
    }
    usedModelIDs = []
    super.tearDown()
  }

  private func makeModelID() -> UUID {
    let id = UUID()
    usedModelIDs.append(id)
    return id
  }

  func testSaveReadDeleteRoundTrip() throws {
    let id = makeModelID()
    XCTAssertNil(store.readKey(for: id))

    try store.saveKey("sk-test-secret", for: id)
    XCTAssertEqual(store.readKey(for: id), "sk-test-secret")

    store.deleteKey(for: id)
    XCTAssertNil(store.readKey(for: id))
  }

  func testSaveOverwritesExistingKey() throws {
    let id = makeModelID()

    try store.saveKey("sk-first", for: id)
    try store.saveKey("sk-second", for: id)

    XCTAssertEqual(store.readKey(for: id), "sk-second")
  }

  func testKeysAreIsolatedPerModel() throws {
    let first = makeModelID()
    let second = makeModelID()

    try store.saveKey("sk-one", for: first)
    try store.saveKey("sk-two", for: second)

    XCTAssertEqual(store.readKey(for: first), "sk-one")
    XCTAssertEqual(store.readKey(for: second), "sk-two")

    store.deleteKey(for: first)
    XCTAssertNil(store.readKey(for: first))
    XCTAssertEqual(store.readKey(for: second), "sk-two")
  }
}
