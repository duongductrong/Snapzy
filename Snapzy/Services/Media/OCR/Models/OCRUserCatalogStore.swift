//
//  OCRUserCatalogStore.swift
//  Snapzy
//
//  Persistence for user-defined downloadable OCR model metadata.
//

import Combine
import Foundation

enum OCRUserCatalogStoreError: LocalizedError, Equatable {
  case duplicateModelID(String)
  case reservedModelID(String)
  case modelNotFound(String)

  var errorDescription: String? {
    switch self {
    case .duplicateModelID(let id):
      "A downloadable OCR model with id \(id) already exists."
    case .reservedModelID(let id):
      "The model id \(id) is reserved by Snapzy's bundled catalog."
    case .modelNotFound(let id):
      "The downloadable OCR model \(id) no longer exists."
    }
  }
}

/// Stores only validated manifest metadata. Model binaries and install state
/// remain machine-local in `OCRModelStore`.
@MainActor
final class OCRUserCatalogStore: ObservableObject {
  static let shared = OCRUserCatalogStore { invalidatedIDs in
    OCRModelStore.shared.invalidateCatalogModels(modelIDs: invalidatedIDs)
  }

  @Published private(set) var models: [OCRModelManifest]
  @Published private(set) var loadErrorDescription: String?

  private let defaults: UserDefaults
  private let reservedModelIDs: Set<String>
  private let invalidationHandler: ([String]) -> Void

  init(
    defaults: UserDefaults = .standard,
    reservedModelIDs: Set<String>? = nil,
    invalidationHandler: @escaping ([String]) -> Void = { _ in }
  ) {
    let resolvedReservedModelIDs = reservedModelIDs ?? OCRModelCatalog.bundledModelIDs
    self.defaults = defaults
    self.reservedModelIDs = resolvedReservedModelIDs
    self.invalidationHandler = invalidationHandler

    switch Self.loadPersistedModels(defaults: defaults, reservedModelIDs: resolvedReservedModelIDs) {
    case .success(let models):
      self.models = models
      loadErrorDescription = nil
    case .failure(let error):
      models = []
      loadErrorDescription = error.localizedDescription
      DiagnosticLogger.shared.logError(.ocr, error, "Failed to load user OCR catalog")
    }
  }

  func model(for id: String) -> OCRModelManifest? {
    models.first { $0.id == id }
  }

  func add(_ model: OCRModelManifest) throws {
    guard self.model(for: model.id) == nil else {
      throw OCRUserCatalogStoreError.duplicateModelID(model.id)
    }
    try apply(models + [model], persist: true)
  }

  func update(_ model: OCRModelManifest) throws {
    guard let index = models.firstIndex(where: { $0.id == model.id }) else {
      throw OCRUserCatalogStoreError.modelNotFound(model.id)
    }
    var updated = models
    updated[index] = model
    try apply(updated, persist: true)
  }

  /// Merges imported records by stable id. Existing positions are retained;
  /// new ids append in import order. Replaced definitions invalidate any old
  /// local install so stale artifacts can never run under new metadata.
  func merge(_ importedModels: [OCRModelManifest]) throws {
    if !importedModels.isEmpty {
      _ = try OCRCatalogManifestValidator.validate(.catalog(importedModels))
      try Self.validateReservedIDs(importedModels, reservedModelIDs: reservedModelIDs)
    }
    var merged = models
    for model in importedModels {
      if let index = merged.firstIndex(where: { $0.id == model.id }) {
        merged[index] = model
      } else {
        merged.append(model)
      }
    }
    try apply(merged, persist: true)
  }

  /// Replace semantics used by the app's TOML configuration import.
  func replaceAll(with replacement: [OCRModelManifest]) throws {
    try apply(replacement, persist: true)
  }

  func remove(id: String) {
    guard models.contains(where: { $0.id == id }) else { return }
    do {
      try apply(models.filter { $0.id != id }, persist: true)
    } catch {
      DiagnosticLogger.shared.logError(.ocr, error, "Failed to remove user OCR catalog model")
    }
  }

  /// Re-reads canonical JSON after a configuration-file rewrite. Invalid
  /// external data leaves the last valid in-memory catalog untouched.
  func reloadFromDefaults() {
    switch Self.loadPersistedModels(defaults: defaults, reservedModelIDs: reservedModelIDs) {
    case .success(let reloaded):
      do {
        try apply(reloaded, persist: false)
        loadErrorDescription = nil
      } catch {
        loadErrorDescription = error.localizedDescription
        DiagnosticLogger.shared.logError(.ocr, error, "Failed to reload user OCR catalog")
      }
    case .failure(let error):
      loadErrorDescription = error.localizedDescription
      DiagnosticLogger.shared.logError(.ocr, error, "Failed to reload user OCR catalog")
    }
  }

  func exportDocument() -> OCRModelManifestDocument {
    .catalog(models)
  }

  static func encodedData(for models: [OCRModelManifest]) throws -> Data {
    try OCRCatalogManifestCodec.encode(.catalog(models), format: .json)
  }

  static func decodePersistedData(
    _ data: Data,
    reservedModelIDs: Set<String>
  ) throws -> [OCRModelManifest] {
    let document = try OCRCatalogManifestCodec.decode(data, fileExtension: "json")
    guard document.format == OCRModelManifestDocument.catalogFormat else {
      throw OCRModelManifestError.invalid("stored user models must use catalog format")
    }
    let models = try OCRCatalogManifestValidator.validate(document)
    try validateReservedIDs(models, reservedModelIDs: reservedModelIDs)
    return models
  }

  private func apply(_ newModels: [OCRModelManifest], persist: Bool) throws {
    if !newModels.isEmpty {
      _ = try OCRCatalogManifestValidator.validate(.catalog(newModels))
    }
    try Self.validateReservedIDs(newModels, reservedModelIDs: reservedModelIDs)

    if persist {
      if newModels.isEmpty {
        defaults.removeObject(forKey: PreferencesKeys.ocrUserCatalogModels)
      } else {
        try defaults.set(Self.encodedData(for: newModels), forKey: PreferencesKeys.ocrUserCatalogModels)
      }
    }

    let previousByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
    let newByID = Dictionary(uniqueKeysWithValues: newModels.map { ($0.id, $0) })
    let invalidatedIDs = previousByID.compactMap { id, previous -> String? in
      guard let replacement = newByID[id], replacement == previous else { return id }
      return nil
    }.sorted()

    models = newModels
    loadErrorDescription = nil
    resetSelectionIfNeeded(invalidatedModelIDs: invalidatedIDs)
    if !invalidatedIDs.isEmpty {
      invalidationHandler(invalidatedIDs)
    }
  }

  private func resetSelectionIfNeeded(invalidatedModelIDs: [String]) {
    guard let rawSelection = defaults.string(forKey: PreferencesKeys.ocrSelectedModel),
          case .downloadable(let selectedID) = OCRModelSelection(persistedValue: rawSelection),
          invalidatedModelIDs.contains(selectedID)
    else { return }
    defaults.set(OCRModelSelection.builtIn.persistedValue, forKey: PreferencesKeys.ocrSelectedModel)
  }

  private static func loadPersistedModels(
    defaults: UserDefaults,
    reservedModelIDs: Set<String>
  ) -> Result<[OCRModelManifest], Error> {
    guard let data = defaults.data(forKey: PreferencesKeys.ocrUserCatalogModels) else {
      return .success([])
    }
    do {
      return try .success(decodePersistedData(data, reservedModelIDs: reservedModelIDs))
    } catch {
      return .failure(error)
    }
  }

  private static func validateReservedIDs(
    _ models: [OCRModelManifest],
    reservedModelIDs: Set<String>
  ) throws {
    if let collision = models.first(where: { reservedModelIDs.contains($0.id) }) {
      throw OCRUserCatalogStoreError.reservedModelID(collision.id)
    }
  }
}
