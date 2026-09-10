//
//  FakeOCRKeychainStore.swift
//  SnapzyTests
//
//  In-memory OCRKeychainStoring fake for store and provider tests.
//

import Foundation
@testable import Snapzy

final class FakeOCRKeychainStore: OCRKeychainStoring, @unchecked Sendable {
  private let stateQueue = DispatchQueue(label: "com.snapzy.tests.fake-ocr-keychain")
  private var storage: [UUID: String] = [:]
  private var _deletedIDs: [UUID] = []
  private var _saveError: Error?

  var deletedIDs: [UUID] {
    stateQueue.sync { _deletedIDs }
  }

  /// When set, `saveKey` throws this error instead of storing the key.
  var saveError: Error? {
    get { stateQueue.sync { _saveError } }
    set { stateQueue.sync { _saveError = newValue } }
  }

  func readKey(for modelID: UUID) -> String? {
    stateQueue.sync { storage[modelID] }
  }

  func saveKey(_ key: String, for modelID: UUID) throws {
    try stateQueue.sync {
      if let saveError = _saveError { throw saveError }
      storage[modelID] = key
    }
  }

  func deleteKey(for modelID: UUID) {
    stateQueue.sync {
      storage.removeValue(forKey: modelID)
      _deletedIDs.append(modelID)
    }
  }

  /// Seeds a key without going through the throwing save path.
  func seedKey(_ key: String, for modelID: UUID) {
    stateQueue.sync { storage[modelID] = key }
  }
}
