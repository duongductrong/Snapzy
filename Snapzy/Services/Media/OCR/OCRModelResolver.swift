//
//  OCRModelResolver.swift
//  Snapzy
//
//  Resolves the persisted OCR model selection to a provider, with fallback.
//

import Foundation

/// Availability lookups for custom OCR models.
///
/// Keeps the resolver testable while the default implementation reads
/// UserDefaults.
protocol OCRModelAvailabilityChecking {
  func customModelExists(id: UUID) -> Bool
}

/// Default availability backed by the JSON array of custom model objects in
/// UserDefaults.
struct UserDefaultsOCRModelAvailability: OCRModelAvailabilityChecking {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func customModelExists(id: UUID) -> Bool {
    guard let data = defaults.data(forKey: PreferencesKeys.ocrCustomModels) else { return false }
    let models = try? JSONDecoder().decode([StoredCustomModel].self, from: data)
    return models?.contains { $0.id == id } ?? false
  }

  /// Minimal decode shape — the full `CustomOCRModel` is loaded by the
  /// provider only after availability has been confirmed.
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
/// Fallback rule: an unavailable custom selection (model removed)
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
    let selection = OCRModelSelection(persistedValue: rawValue)
    // `dl:<id>` was the persisted format for the removed downloadable
    // provider. Canonicalize it (and other invalid values) so an old install
    // cannot keep advertising a provider that no longer exists.
    if selection == .builtIn, rawValue != OCRModelSelection.builtIn.persistedValue {
      defaults.set(OCRModelSelection.builtIn.persistedValue, forKey: PreferencesKeys.ocrSelectedModel)
    }
    return selection
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
