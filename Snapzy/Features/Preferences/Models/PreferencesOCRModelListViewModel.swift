//
//  PreferencesOCRModelListViewModel.swift
//  Snapzy
//
//  Selection, download, and alert state for the OCR model list in Capture preferences.
//

import Combine
import Foundation

/// View model behind `PreferencesOCRModelListView`.
///
/// Selection persists immediately to `ocr.selectedModel`; downloadable models
/// are selectable only once installed (spec), custom endpoints while their
/// configuration still exists. Removal of the active model resets the
/// selection back to built-in so the UI matches the resolver's fallback.
@MainActor
final class PreferencesOCRModelListViewModel: ObservableObject {
  /// Identifiable payload for the add/edit custom model sheet; `editing == nil` means add.
  struct SheetRequest: Identifiable {
    let id = UUID()
    let editing: CustomOCRModel?
  }

  /// Add/edit payload for a user-defined downloadable OCR model.
  struct CatalogSheetRequest: Identifiable {
    let id = UUID()
    let editing: OCRModelManifest?
  }

  /// Identifiable payload for the download-failure alert.
  struct DownloadFailure: Identifiable {
    let id = UUID()
    let modelID: String
    let modelName: String
    let reason: String
  }

  /// Identifiable payload for the connection-test result alert.
  struct ConnectionTestResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
  }

  struct CatalogOperationResult: Identifiable {
    let id = UUID()
    let title: String
    let message: String
  }

  @Published private(set) var selection: OCRModelSelection
  @Published var sheetRequest: SheetRequest?
  @Published var catalogSheetRequest: CatalogSheetRequest?
  @Published var downloadFailure: DownloadFailure?
  @Published var removeDownloadableCandidate: OCRModelDefinition?
  @Published var removeUserCatalogCandidate: OCRModelCatalogEntry?
  @Published var removeCustomCandidate: CustomOCRModel?
  @Published var connectionTestResult: ConnectionTestResult?
  @Published var catalogOperationResult: CatalogOperationResult?
  @Published private(set) var testingConnectionModelID: UUID?
  /// Script coverage of each installed catalog model's `dict.txt`, loaded
  /// lazily by the row that displays it.
  @Published private(set) var coverage: [String: OCRScriptCoverageReport] = [:]

  let modelStore: OCRModelStore
  let customModelStore: CustomOCRModelStore
  let userCatalogStore: OCRUserCatalogStore
  let catalog: OCRModelCatalog
  private let defaults: UserDefaults
  private var cancellables: Set<AnyCancellable> = []

  init(
    defaults: UserDefaults = .standard,
    modelStore: OCRModelStore? = nil,
    customModelStore: CustomOCRModelStore? = nil,
    userCatalogStore: OCRUserCatalogStore? = nil,
    catalog: OCRModelCatalog? = nil
  ) {
    self.defaults = defaults
    self.modelStore = modelStore ?? .shared
    self.customModelStore = customModelStore ?? .shared
    self.userCatalogStore = userCatalogStore ?? .shared
    self.catalog = catalog ?? .shared
    selection = Self.storedSelection(defaults: defaults)

    // Forward store changes so the single @StateObject in the view re-renders.
    self.modelStore.objectWillChange
      .sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)
    self.customModelStore.objectWillChange
      .sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)
    self.catalog.objectWillChange
      .sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)
    // Store-side selection resets (e.g. config import, custom model removal)
    // land in UserDefaults; mirror them into the published selection.
    self.customModelStore.$models
      .dropFirst()
      .sink { [weak self] _ in self?.refreshSelection() }
      .store(in: &cancellables)
    self.userCatalogStore.$models
      .dropFirst()
      .sink { [weak self] _ in
        self?.coverage.removeAll()
        self?.refreshSelection()
      }
      .store(in: &cancellables)
  }

  static func storedSelection(defaults: UserDefaults) -> OCRModelSelection {
    guard let rawValue = defaults.string(forKey: PreferencesKeys.ocrSelectedModel) else { return .builtIn }
    return OCRModelSelection(persistedValue: rawValue)
  }

  /// Re-reads the persisted selection after store-side resets.
  func refreshSelection() {
    selection = Self.storedSelection(defaults: defaults)
  }

  // MARK: - Selection

  func isSelected(_ selection: OCRModelSelection) -> Bool {
    self.selection == selection
  }

  /// Built-in is always selectable; downloadable models only once installed;
  /// custom endpoints while their configuration still exists.
  func isSelectable(_ selection: OCRModelSelection) -> Bool {
    switch selection {
    case .builtIn:
      true
    case .downloadable(let id):
      modelStore.state(for: id) == .installed
    case .custom(let id):
      customModelStore.model(for: id) != nil
    }
  }

  /// Persists the selection immediately; taps on non-selectable rows are ignored.
  func select(_ selection: OCRModelSelection) {
    guard isSelectable(selection) else { return }
    self.selection = selection
    defaults.set(selection.persistedValue, forKey: PreferencesKeys.ocrSelectedModel)
  }

  // MARK: - Script Coverage

  /// Reads an installed model's `dict.txt` off the main actor and caches which
  /// scripts it can spell, so the row can warn about the ones it only partly
  /// covers. No-op until the model is installed, and cached thereafter — the
  /// dictionaries run to ~19k lines.
  func loadCoverage(for modelID: String) async {
    guard coverage[modelID] == nil,
          modelStore.state(for: modelID) == .installed,
          let directory = modelStore.installDirectory(for: modelID)
    else { return }

    let dictionaryURL = directory.appendingPathComponent("dict.txt")
    let report = await Task.detached(priority: .utility) { () -> OCRScriptCoverageReport? in
      guard let dictionary = try? PPOCRSessionManager.loadDictionary(from: dictionaryURL) else {
        return nil
      }
      return OCRScriptCoverageReport.analyze(dictionary: dictionary)
    }.value

    guard let report else { return }
    coverage[modelID] = report
  }

  // MARK: - Downloads

  func download(modelID: String) {
    let task = modelStore.download(modelID: modelID)
    Task { [weak self] in
      await task.value
      guard let self, case .failed(let reason) = modelStore.state(for: modelID) else { return }
      downloadFailure = DownloadFailure(
        modelID: modelID,
        modelName: catalog.definition(for: modelID)?.displayName ?? modelID,
        reason: reason
      )
    }
  }

  func cancelDownload(modelID: String) {
    modelStore.cancelDownload(modelID: modelID)
  }

  // MARK: - Removal

  func removeDownloadable(_ definition: OCRModelDefinition) {
    modelStore.removeModel(modelID: definition.id)
    // A re-download may bring a different dictionary revision; the catalog
    // pins no checksum for dict.txt.
    coverage[definition.id] = nil
    // The resolver only persists its built-in fallback lazily on the next OCR
    // run; reset eagerly here so the list reflects it right away.
    if selection == .downloadable(definition.id) {
      select(.builtIn)
    }
  }

  func removeCustom(_ model: CustomOCRModel) {
    // The store deletes the Keychain key and resets the persisted selection
    // when the removed model was active.
    customModelStore.remove(id: model.id)
    refreshSelection()
  }

  func removeUserCatalogModel(_ entry: OCRModelCatalogEntry) {
    guard entry.source == .user else { return }
    userCatalogStore.remove(id: entry.id)
    coverage[entry.id] = nil
    refreshSelection()
  }

  // MARK: - User Catalog Import / Export

  @discardableResult
  func importCatalog(_ data: Data, fileExtension: String) throws -> Int {
    let document = try OCRCatalogManifestCodec.decode(data, fileExtension: fileExtension)
    return try importCatalog(document)
  }

  @discardableResult
  func importCatalog(from url: URL) throws -> Int {
    try importCatalog(OCRCatalogManifestCodec.decode(contentsOf: url))
  }

  private func importCatalog(_ document: OCRModelManifestDocument) throws -> Int {
    let imported = try OCRCatalogManifestValidator.validate(document)
    try userCatalogStore.merge(imported)
    refreshSelection()
    return imported.count
  }

  func exportCatalog(
    format: OCRModelManifestFormat,
    model: OCRModelManifest? = nil
  ) throws -> Data {
    let document = model.map(OCRModelManifestDocument.singleModel)
      ?? userCatalogStore.exportDocument()
    return try OCRCatalogManifestCodec.encode(document, format: format)
  }

  // MARK: - Connection Test (row menu)

  func testConnection(for model: CustomOCRModel) {
    guard testingConnectionModelID == nil else { return }
    testingConnectionModelID = model.id
    Task { [weak self] in
      let result = await RemoteOCRProvider(model: model).testConnection()
      guard let self else { return }
      testingConnectionModelID = nil
      switch result {
      case .success(let latency):
        connectionTestResult = ConnectionTestResult(
          title: L10n.PreferencesCapture.ocrModelTestSuccessTitle,
          message: L10n.PreferencesCapture.ocrModelTestSuccessLatency(Int(latency * 1000))
        )
      case .failure(let error):
        connectionTestResult = ConnectionTestResult(
          title: L10n.PreferencesCapture.ocrModelTestFailedTitle,
          message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        )
      }
    }
  }
}
