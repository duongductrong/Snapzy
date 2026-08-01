//
//  FakeOCRKeychainStore.swift
//  SnapzyTests
//
//  In-memory OCRKeychainStoring fake for store and provider tests.
//

import Foundation
@testable import Snapzy

final class FakeOCRKeychainStore: OCRKeychainStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [UUID: String] = [:]
  private var _deletedIDs: [UUID] = []
  private var _saveError: Error?

  var deletedIDs: [UUID] {
    lock.lock()
    defer { lock.unlock() }
    return _deletedIDs
  }

  /// When set, `saveKey` throws this error instead of storing the key.
  var saveError: Error? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _saveError
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _saveError = newValue
    }
  }

  func readKey(for modelID: UUID) -> String? {
    lock.lock()
    defer { lock.unlock() }
    return storage[modelID]
  }

  func saveKey(_ key: String, for modelID: UUID) throws {
    lock.lock()
    defer { lock.unlock() }
    if let _saveError { throw _saveError }
    storage[modelID] = key
  }

  func deleteKey(for modelID: UUID) {
    lock.lock()
    defer { lock.unlock() }
    storage.removeValue(forKey: modelID)
    _deletedIDs.append(modelID)
  }

  /// Seeds a key without going through the throwing save path.
  func seedKey(_ key: String, for modelID: UUID) {
    lock.lock()
    defer { lock.unlock() }
    storage[modelID] = key
  }
}
