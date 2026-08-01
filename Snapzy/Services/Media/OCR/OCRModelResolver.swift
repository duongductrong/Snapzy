//
//  OCRModelResolver.swift
//  Snapzy
//
//  Resolves the persisted OCR model selection to a provider, with fallback.
//

import Foundation

/// Availability lookups for non-built-in OCR models.
///
/// Keeps the resolver testable; the default implementation reads UserDefaults
/// so Phase 2 (downloadable catalog) and Phase 4 (custom endpoints) only need
/// to persist their keys.
protocol OCRModelAvailabilityChecking {
  func isDownloadableModelInstalled(id: String) -> Bool
  func customModelExists(id: UUID) -> Bool
}

/// Default availability backed by UserDefaults:
/// - `ocr.installedModels`: String array of installed catalog model ids.
/// - `ocr.customModels`: JSON array of custom model objects (each with `id`).
struct UserDefaultsOCRModelAvailability: OCRModelAvailabilityChecking {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func isDownloadableModelInstalled(id: String) -> Bool {
    (defaults.array(forKey: PreferencesKeys.ocrInstalledModels) as? [String])?.contains(id) ?? false
  }

  func customModelExists(id: UUID) -> Bool {
    guard let data = defaults.data(forKey: PreferencesKeys.ocrCustomModels) else { return false }
    let models = try? JSONDecoder().decode([StoredCustomModel].self, from: data)
    return models?.contains { $0.id == id } ?? false
  }

  /// Minimal decode shape — the full `CustomOCRModel` arrives in Phase 4.
  private struct StoredCustomModel: Decodable {
    let id: UUID
  }
}

/// Result of resolving a selection: the effective selection (after fallback)
/// plus the provider that should run recognition.
struct OCRModelResolution {
  let selection: OCRModelSelection
  let provider: OCRProvider
}

/// Routes the persisted OCR model selection to a concrete provider.
///
/// Fallback rule: an unavailable selection (model uninstalled or removed)
/// resolves to `.builtIn`, persists `.builtIn` back, and logs to `.ocr`.
@MainActor
struct OCRModelResolver {
  private let defaults: UserDefaults
  private let availability: OCRModelAvailabilityChecking

  init(
    defaults: UserDefaults = .standard,
    availability: OCRModelAvailabilityChecking? = nil
  ) {
    self.defaults = defaults
    self.availability = availability ?? UserDefaultsOCRModelAvailability(defaults: defaults)
  }

  /// Persisted selection; missing/corrupt values read as `.builtIn`.
  func storedSelection() -> OCRModelSelection {
    guard let rawValue = defaults.string(forKey: PreferencesKeys.ocrSelectedModel) else {
      return .builtIn
    }
    return OCRModelSelection(persistedValue: rawValue)
  }

  func resolveStoredSelection() -> OCRModelResolution {
    resolve(storedSelection())
  }

  func resolve(_ selection: OCRModelSelection) -> OCRModelResolution {
    let effective = effectiveSelection(for: selection)
    return OCRModelResolution(selection: effective, provider: provider(for: effective))
  }

  private func effectiveSelection(for selection: OCRModelSelection) -> OCRModelSelection {
    switch selection {
    case .builtIn:
      return .builtIn
    case .downloadable(let id):
      guard availability.isDownloadableModelInstalled(id: id) else {
        return fallBackToBuiltIn(from: selection, reason: "downloadable model not installed")
      }
      return selection
    case .custom(let id):
      guard availability.customModelExists(id: id) else {
        return fallBackToBuiltIn(from: selection, reason: "custom model missing")
      }
      return selection
    }
  }

  private func fallBackToBuiltIn(from selection: OCRModelSelection, reason: String) -> OCRModelSelection {
    defaults.set(OCRModelSelection.builtIn.persistedValue, forKey: PreferencesKeys.ocrSelectedModel)
    DiagnosticLogger.shared.log(
      .warning,
      .ocr,
      "OCR model selection unavailable; falling back to built-in",
      context: ["selection": selection.persistedValue, "reason": reason]
    )
    return .builtIn
  }

  private func provider(for selection: OCRModelSelection) -> OCRProvider {
    switch selection {
    case .builtIn:
      return VisionOCRProvider()
    case .downloadable(let id):
      return PPOCRProvider(
        modelID: id,
        modelDirectory: OCRModelStore.defaultInstallRootURL()?
          .appendingPathComponent(id, isDirectory: true)
      )
    case .custom(let id):
      guard let model = loadCustomModel(id: id) else {
        // Availability already confirmed the id exists; a decode failure here
        // means a partially-written entry — stay on Vision rather than crash.
        return VisionOCRProvider()
      }
      return RemoteOCRProvider(model: model)
    }
  }

  private func loadCustomModel(id: UUID) -> CustomOCRModel? {
    guard let data = defaults.data(forKey: PreferencesKeys.ocrCustomModels) else { return nil }
    return (try? JSONDecoder().decode([CustomOCRModel].self, from: data))?.first { $0.id == id }
  }
}
