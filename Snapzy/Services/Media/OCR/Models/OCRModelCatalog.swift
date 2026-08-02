//
//  OCRModelCatalog.swift
//  Snapzy
//
//  Merged, data-driven catalog of bundled and user-defined OCR models.
//

import Combine
import Foundation

struct OCRModelCatalogLoadResult {
  let manifests: [OCRModelManifest]
  let definitions: [OCRModelDefinition]
  let errorDescription: String?

  var isAvailable: Bool {
    errorDescription == nil
  }
}

enum OCRModelCatalogEntrySource: Equatable {
  case bundled
  case user
}

struct OCRModelCatalogEntry: Identifiable, Equatable {
  let manifest: OCRModelManifest
  let definition: OCRModelDefinition
  let source: OCRModelCatalogEntrySource

  var id: String {
    definition.id
  }
}

/// Observable facade over the bundled catalog and the user's validated
/// downloadable model records. Bundled entries always come first and retain
/// their YAML order; user entries follow in persisted order.
///
/// Snapzy ships an empty bundled catalog: no model vendor is baked into the
/// app, so every downloadable model comes from a manifest the user supplies.
@MainActor
final class OCRModelCatalog: ObservableObject {
  private static let bundledResult = loadBundledCatalog()

  static let shared = OCRModelCatalog(userStore: .shared)

  /// Compatibility surface used by existing download/UI call sites.
  static var all: [OCRModelDefinition] {
    shared.definitions
  }

  static var manifests: [OCRModelManifest] {
    shared.entries.map(\.manifest)
  }

  static var isBundledCatalogAvailable: Bool {
    bundledResult.isAvailable
  }

  static var bundledCatalogError: String? {
    bundledResult.errorDescription
  }

  /// Ids owned by the bundled catalog, and therefore not claimable by user
  /// manifests. Empty in stock builds; non-empty only when a build ships its
  /// own `ocr-model-catalog.yaml` entries.
  static var bundledModelIDs: Set<String> {
    Set(bundledResult.definitions.map(\.id))
  }

  static var bundledDefinitions: [OCRModelDefinition] {
    bundledResult.definitions
  }

  @Published private(set) var entries: [OCRModelCatalogEntry] = []
  @Published private(set) var mergeErrorDescription: String?

  var definitions: [OCRModelDefinition] {
    entries.map(\.definition)
  }

  var isAuthoritative: Bool {
    bundledLoadResult.isAvailable
      && userStore.loadErrorDescription == nil
      && mergeErrorDescription == nil
  }

  private let bundledLoadResult: OCRModelCatalogLoadResult
  private let userStore: OCRUserCatalogStore
  private var cancellables: Set<AnyCancellable> = []

  init(
    bundledLoadResult: OCRModelCatalogLoadResult? = nil,
    userStore: OCRUserCatalogStore
  ) {
    self.bundledLoadResult = bundledLoadResult ?? OCRModelCatalog.bundledResult
    self.userStore = userStore
    rebuild(userModels: userStore.models)

    userStore.$models
      .dropFirst()
      .sink { [weak self] models in
        self?.rebuild(userModels: models)
      }
      .store(in: &cancellables)

    userStore.$loadErrorDescription
      .dropFirst()
      .sink { [weak self] _ in
        self?.objectWillChange.send()
      }
      .store(in: &cancellables)
  }

  func definition(for id: String) -> OCRModelDefinition? {
    entries.first { $0.id == id }?.definition
  }

  func entry(for id: String) -> OCRModelCatalogEntry? {
    entries.first { $0.id == id }
  }

  func isUserDefined(modelID: String) -> Bool {
    entry(for: modelID)?.source == .user
  }

  static func definition(for id: String) -> OCRModelDefinition? {
    shared.definition(for: id)
  }

  static func load(_ data: Data, fileExtension: String) -> OCRModelCatalogLoadResult {
    do {
      let document = try OCRCatalogManifestCodec.decode(data, fileExtension: fileExtension)
      guard document.format == OCRModelManifestDocument.catalogFormat else {
        throw OCRModelManifestError.invalid("the bundled resource must be a catalog document")
      }
      // An empty `models:` list is the shipped default, not a failure: it means
      // the build offers no downloadable models until the user adds one.
      let manifests = try OCRCatalogManifestValidator.validate(document)
      let definitions = try manifests.map {
        try OCRCatalogManifestValidator.definition(from: $0)
      }
      return OCRModelCatalogLoadResult(
        manifests: manifests,
        definitions: definitions,
        errorDescription: nil
      )
    } catch {
      return OCRModelCatalogLoadResult(
        manifests: [],
        definitions: [],
        errorDescription: error.localizedDescription
      )
    }
  }

  private func rebuild(userModels: [OCRModelManifest]) {
    do {
      let bundledIDs = Set(bundledLoadResult.manifests.map(\.id))
      if let collision = userModels.first(where: { bundledIDs.contains($0.id) }) {
        throw OCRUserCatalogStoreError.reservedModelID(collision.id)
      }

      let bundledEntries = zip(
        bundledLoadResult.manifests,
        bundledLoadResult.definitions
      ).map {
        OCRModelCatalogEntry(manifest: $0.0, definition: $0.1, source: .bundled)
      }
      let userEntries = try userModels.map { manifest in
        try OCRModelCatalogEntry(
          manifest: manifest,
          definition: OCRCatalogManifestValidator.definition(from: manifest),
          source: .user
        )
      }
      entries = bundledEntries + userEntries
      mergeErrorDescription = nil
    } catch {
      entries = zip(
        bundledLoadResult.manifests,
        bundledLoadResult.definitions
      ).map {
        OCRModelCatalogEntry(manifest: $0.0, definition: $0.1, source: .bundled)
      }
      mergeErrorDescription = error.localizedDescription
      DiagnosticLogger.shared.logError(.ocr, error, "User OCR catalog merge failed")
    }
  }

  private static func loadBundledCatalog() -> OCRModelCatalogLoadResult {
    guard let url = Bundle.main.url(forResource: "ocr-model-catalog", withExtension: "yaml") else {
      let result = OCRModelCatalogLoadResult(
        manifests: [],
        definitions: [],
        errorDescription: "Bundled ocr-model-catalog.yaml is missing."
      )
      logLoadFailure(result.errorDescription)
      return result
    }
    do {
      let result = try load(Data(contentsOf: url), fileExtension: url.pathExtension)
      if !result.isAvailable { logLoadFailure(result.errorDescription) }
      return result
    } catch {
      let result = OCRModelCatalogLoadResult(
        manifests: [],
        definitions: [],
        errorDescription: error.localizedDescription
      )
      logLoadFailure(result.errorDescription)
      return result
    }
  }

  private static func logLoadFailure(_ message: String?) {
    DiagnosticLogger.shared.log(
      .error,
      .ocr,
      "Bundled OCR model catalog unavailable",
      context: ["reason": message ?? "unknown"]
    )
  }
}
