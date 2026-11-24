//
//  CustomUploaderStore.swift
//  Snapzy
//
//  Persists custom uploader definitions as JSON in UserDefaults
//  (`cloud.customUploaders`). Definitions hold secret references only.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "Snapzy", category: "CustomUploaderStore")

@MainActor
final class CustomUploaderStore: ObservableObject {

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  static let shared = CustomUploaderStore()
  static let maxUploaders = 20

  @Published private(set) var uploaders: [CustomUploader] = []

  private let defaults: UserDefaults
  private let storageKey: String

  init(defaults: UserDefaults = .standard, storageKey: String = PreferencesKeys.cloudCustomUploaders) {
    self.defaults = defaults
    self.storageKey = storageKey
    uploaders = Self.load(from: defaults, key: storageKey)
  }

  var canAdd: Bool { uploaders.count < Self.maxUploaders }

  func uploader(id: UUID) -> CustomUploader? {
    uploaders.first { $0.id == id }
  }

  /// Appends an uploader. A clashing id gets a fresh one.
  @discardableResult
  func add(_ uploader: CustomUploader) throws -> CustomUploader {
    guard canAdd else { throw CustomUploaderError.limitReached(Self.maxUploaders) }
    var stored = uploader
    if self.uploader(id: stored.id) != nil {
      stored.id = UUID()
    }
    uploaders.append(stored)
    persist()
    return stored
  }

  /// Replaces the uploader with the same id; returns false when it does not exist.
  @discardableResult
  func update(_ uploader: CustomUploader) -> Bool {
    guard let index = uploaders.firstIndex(where: { $0.id == uploader.id }) else { return false }
    uploaders[index] = uploader
    persist()
    return true
  }

  /// Adds a copy named "<name> copy" right after the original.
  @discardableResult
  func duplicate(id: UUID, nameFormatter: (String) -> String = { L10n.CustomUploader.duplicateName($0) }) throws
    -> CustomUploader?
  {
    guard let index = uploaders.firstIndex(where: { $0.id == id }) else { return nil }
    guard canAdd else { throw CustomUploaderError.limitReached(Self.maxUploaders) }
    let copy = uploaders[index].duplicated(name: nameFormatter(uploaders[index].name))
    uploaders.insert(copy, at: index + 1)
    persist()
    return copy
  }

  func delete(id: UUID) {
    uploaders.removeAll { $0.id == id }
    persist()
  }

  func reload() {
    uploaders = Self.load(from: defaults, key: storageKey)
  }

  // MARK: - Persistence

  private func persist() {
    do {
      let data = try JSONEncoder().encode(uploaders)
      defaults.set(data, forKey: storageKey)
    } catch {
      logger.error("Custom uploaders could not be encoded: \(error.localizedDescription, privacy: .public)")
    }
  }

  private static func load(from defaults: UserDefaults, key: String) -> [CustomUploader] {
    guard let data = defaults.data(forKey: key) ?? defaults.string(forKey: key).map({ Data($0.utf8) }) else {
      return []
    }
    do {
      let decoded = try JSONDecoder().decode([CustomUploader].self, from: data)
      return Array(decoded.prefix(maxUploaders))
    } catch {
      logger.error("Custom uploaders could not be decoded: \(error.localizedDescription, privacy: .public)")
      return []
    }
  }
}
