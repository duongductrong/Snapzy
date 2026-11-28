//
//  AutomationTextSteps.swift
//  Snapzy
//
//  OCR (image → text) and Translate (text → text) steps, plus the live
//  services they call through `AutomationRunEnvironment`.
//

import AppKit
import Foundation

struct OCRStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.image] }

  func produces(_: AutomationStepAction, given: Set<AutomationPayloadKind>) -> Set<AutomationPayloadKind> {
    given.union([.text])
  }

  func run(
    _ action: AutomationStepAction,
    files: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .ocr(let config) = action else { return }
    guard !files.isEmpty else { throw AutomationStepError.noFile }
    var texts: [String] = []
    for file in files {
      let text = try await environment.recognizeText(in: file, config: config)
      try Task.checkCancellation()
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { texts.append(trimmed) }
    }
    guard !texts.isEmpty else { throw AutomationStepError.noTextFound }
    state.payload.text = texts.joined(separator: "\n\n")
  }
}

struct TranslateStepHandler: AutomationStepHandler {
  func accepts(_: AutomationStepAction) -> Set<AutomationPayloadKind> { [.text] }

  /// Network when routed to a custom endpoint; Apple Translation stays on device.
  var trust: AutomationTrustTier { .network }

  func run(
    _ action: AutomationStepAction,
    files _: [URL],
    state: inout AutomationRunState,
    environment: AutomationRunEnvironment
  ) async throws {
    guard case .translate(let config) = action else { return }
    guard let text = state.payload.text, !text.isEmpty else { throw AutomationStepError.noText }
    let translated = try await environment.translate(text, targetLanguage: config.targetLanguage)
    try Task.checkCancellation()
    state.payload.text = translated
  }
}

// MARK: - Live services

@MainActor
enum AutomationTextRecognizer {
  static func recognize(_ url: URL, config: AutomationOCRConfig) async throws -> String {
    guard let image = QuickAccessImageOptimizer.loadImage(at: url) else { throw AutomationStepError.noFile }
    let language = config.languageIdentifier ?? AppLanguageManager.shared.activeOCRLanguageIdentifier

    let recognized: String?
    do {
      recognized = try await OCRService.shared.recognizeText(
        from: image,
        preferredLanguageIdentifier: language,
        contentType: .interfaceText
      )
    } catch OCRError.noTextFound {
      recognized = nil
    }

    guard config.includeQR else {
      guard let recognized else { throw AutomationStepError.noTextFound }
      return recognized
    }
    let detections = (try? await QRCodeService.shared.detect(in: image))?.detections ?? []
    guard let composed = OCRQRPayloadComposer.compose(
      recognizedText: recognized,
      qrDetections: detections,
      qrSectionTitle: L10n.OCR.qrCodesLabel
    ) else { throw AutomationStepError.noTextFound }
    return composed
  }
}

@MainActor
enum AutomationTranslator {
  static func translate(_ text: String, targetLanguage: String?) async throws -> String {
    guard let target = TranslationLanguage.language(for: targetLanguage) ?? TranslationLanguage.storedTarget()
      ?? TranslationLanguage.language(for: Locale.current.language.languageCode?.identifier)
    else {
      throw AutomationStepError.translationUnavailable(L10n.Automations.errorTranslationNoTarget)
    }

    switch TranslationEngineResolver().resolve() {
    case .remote(let engine):
      return try await RemoteTranslationProvider(engine: engine).translate(text, to: target)
    case .apple:
      if #available(macOS 15.0, *) {
        return try await HeadlessTranslationHost.shared.translate(text, target: target)
      }
      throw AutomationStepError.translationUnavailable(L10n.Automations.errorTranslationRequiresMacOS15)
    case .unavailable:
      throw AutomationStepError.translationUnavailable(L10n.Automations.errorTranslationRequiresMacOS15)
    }
  }
}
