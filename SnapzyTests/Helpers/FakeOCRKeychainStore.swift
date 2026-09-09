//
//  FakeOCRKeychainStore.swift
//  SnapzyTests
//
//  In-memory OCRKeychainStoring fake for store and provider tests.
//

import Foundation
import os.lock
@testable import Snapzy

final class FakeOCRKeychainStore: OCRKeychainStoring, @unchecked Sendable {
  private struct State {
    var storage: [UUID: String] = [:]
    var deletedIDs: [UUID] = []
    var saveError: Error?
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  func reset() {
    state.withLock { $0 = State() }
  }

  var deletedIDs: [UUID] {
    state.withLock { $0.deletedIDs }
  }

  /// When set, `saveKey` throws this error instead of storing the key.
  var saveError: Error? {
    get { state.withLock { $0.saveError } }
    set { state.withLock { $0.saveError = newValue } }
  }

  func readKey(for modelID: UUID) -> String? {
    state.withLock { $0.storage[modelID] }
  }

  func saveKey(_ key: String, for modelID: UUID) throws {
    try state.withLock { state in
      if let saveError = state.saveError { throw saveError }
      state.storage[modelID] = key
    }
  }

  func deleteKey(for modelID: UUID) {
    state.withLock { state in
      state.storage.removeValue(forKey: modelID)
      state.deletedIDs.append(modelID)
    }
  }

  /// Seeds a key without going through the throwing save path.
  func seedKey(_ key: String, for modelID: UUID) {
    state.withLock { $0.storage[modelID] = key }
  }
}
