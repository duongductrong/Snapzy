//
//  CustomOCRModelStore.swift
//  Snapzy
//
//  Persistence for user-defined OpenAI-compatible OCR endpoints.
//

import Combine
import Foundation

/// CRUD store for `CustomOCRModel`s, JSON-encoded into UserDefaults key
/// `ocr.customModels` (preset-store pattern). API keys are kept out of
/// UserDefaults: they live in the Keychain via `OCRKeychainStoring`.
@MainActor
final class CustomOCRModelStore: ObservableObject {
  static let shared = CustomOCRModelStore()

  @Published private(set) var models: [CustomOCRModel]

  private let defaults: UserDefaults
  private let keychainStore: OCRKeychainStoring
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(
    defaults: UserDefaults = .standard,
    keychainStore: OCRKeychainStoring = OCRKeychainStore()
  ) {
    self.defaults = defaults
    self.keychainStore = keychainStore
    self.models = Self.loadModels(defaults: defaults, decoder: decoder)
  }

  func model(for id: UUID) -> CustomOCRModel? {
    models.first { $0.id == id }
  }

  func add(_ model: CustomOCRModel) {
    models.append(model)
    persist()
  }

  /// Applies edits (including renames); bumps `updatedAt`.
  func update(_ model: CustomOCRModel) {
    guard let index = models.firstIndex(where: { $0.id == model.id }) else { return }
    var updated = model
    updated.updatedAt = Date()
    models[index] = updated
    persist()
  }

  /// Removes the model, deletes its Keychain API key, and resets the
  /// persisted OCR selection to built-in when the removed model was active.
  func remove(id: UUID) {
    guard models.contains(where: { $0.id == id }) else { return }
    keychainStore.deleteKey(for: id)
    models.removeAll { $0.id == id }
    persist()
    resetSelectionIfNeeded(removedModelID: id)
  }

  /// Saves or clears the model's API key and keeps `hasAPIKey` in sync.
  func setAPIKey(_ key: String?, for id: UUID) throws {
    guard var model = model(for: id) else { return }
    if let key, !key.isEmpty {
      try keychainStore.saveKey(key, for: id)
      model.hasAPIKey = true
    } else {
      keychainStore.deleteKey(for: id)
      model.hasAPIKey = false
    }
    update(model)
  }

  /// Re-reads the models JSON after an external rewrite (config import).
  func reloadFromDefaults() {
    models = Self.loadModels(defaults: defaults, decoder: decoder)
  }

  // MARK: - Private

  private func persist() {
    do {
      let data = try encoder.encode(models)
      defaults.set(data, forKey: PreferencesKeys.ocrCustomModels)
    } catch {
      DiagnosticLogger.shared.logError(.ocr, error, "Failed to persist custom OCR models")
    }
  }

  private func resetSelectionIfNeeded(removedModelID id: UUID) {
    let removedSelection = OCRModelSelection.custom(id).persistedValue
    guard defaults.string(forKey: PreferencesKeys.ocrSelectedModel) == removedSelection else { return }
    defaults.set(OCRModelSelection.builtIn.persistedValue, forKey: PreferencesKeys.ocrSelectedModel)
    DiagnosticLogger.shared.log(
      .info,
      .ocr,
      "Active custom OCR model removed; selection reset to built-in",
      context: ["removedModelID": id.uuidString]
    )
  }

  private static func loadModels(defaults: UserDefaults, decoder: JSONDecoder) -> [CustomOCRModel] {
    guard let data = defaults.data(forKey: PreferencesKeys.ocrCustomModels) else {
      return []
    }
    do {
      return try decoder.decode([CustomOCRModel].self, from: data)
    } catch {
      defaults.removeObject(forKey: PreferencesKeys.ocrCustomModels)
      return []
    }
  }
}
