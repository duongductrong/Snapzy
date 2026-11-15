//
//  TranslationCardModel.swift
//  Snapzy
//
//  State for the Snip to Translate card.
//

import AppKit
import Combine
import Foundation
import Translation

@MainActor
final class TranslationCardModel: ObservableObject {
  enum Phase: Equatable {
    /// No target language stored yet: the card asks first.
    case needsTarget
    case translating
    case done(TranslationOutput)
    case failed(TranslationFailure)
    case unavailable(TranslationUnavailableReason)
  }

  @Published private(set) var phase: Phase
  @Published private(set) var target: TranslationLanguage?
  @Published private(set) var route: TranslationRoute
  /// Bumped whenever the Apple host view should (re)run its translation task.
  @Published private(set) var appleRequestToken = 0
  /// The text is already in the target language; the card shows it as-is.
  @Published private(set) var isAlreadyInTarget = false

  let sourceText: String
  /// Best-effort source language for the header and as the Apple session source.
  let detectedSourceIdentifier: String?
  /// Endpoint the user may pick explicitly when Apple Translation can't help.
  let alternativeEndpoint: CustomOCRModel?

  private var remoteTask: Task<Void, Never>?

  init(
    sourceText: String,
    route: TranslationRoute,
    target: TranslationLanguage?,
    alternativeEndpoint: CustomOCRModel?
  ) {
    self.sourceText = sourceText
    self.route = route
    self.target = target
    self.alternativeEndpoint = alternativeEndpoint
    detectedSourceIdentifier = sourceText.isEmpty ? nil : TranslationSourceLanguageDetector.detect(sourceText)
    if case .unavailable(let reason) = route {
      phase = .unavailable(reason)
    } else {
      phase = target == nil ? .needsTarget : .translating
    }
  }

  var isAppleRoute: Bool {
    route == .apple
  }

  /// Apple session source: the detected language when Apple supports it, so
  /// short lines are not re-detected one by one.
  var appleSourceLanguage: Locale.Language? {
    guard let detectedSourceIdentifier else { return nil }
    let source = Locale.Language(identifier: detectedSourceIdentifier)
    let isSupported = TranslationLanguage.all.contains { $0.localeLanguage.languageCode == source.languageCode }
    return isSupported ? source : nil
  }

  var translatedText: String? {
    if case .done(let output) = phase { return output.text }
    return nil
  }

  /// Offer "Translate with <endpoint>" only after an Apple failure it can fix.
  var offersEndpointFallback: Bool {
    guard isAppleRoute, alternativeEndpoint != nil, case .failed(let failure) = phase else { return false }
    return failure.canRetryWithEndpoint
  }

  // MARK: - Actions

  func start() {
    remoteTask?.cancel()
    remoteTask = nil
    isAlreadyInTarget = false

    if case .unavailable(let reason) = route {
      phase = .unavailable(reason)
      return
    }
    guard let target else {
      phase = .needsTarget
      return
    }
    if isSameLanguage(target) {
      isAlreadyInTarget = true
      phase = .done(TranslationOutput(text: sourceText, sourceLanguageIdentifier: detectedSourceIdentifier))
      return
    }

    phase = .translating
    switch route {
    case .apple:
      appleRequestToken += 1
    case .remote(let model):
      let text = sourceText
      let detected = detectedSourceIdentifier
      remoteTask = Task { [weak self] in
        do {
          let translated = try await RemoteTranslationProvider(model: model).translate(text, to: target)
          guard !Task.isCancelled else { return }
          self?.finish(.done(TranslationOutput(text: translated, sourceLanguageIdentifier: detected)))
        } catch {
          guard !Task.isCancelled else { return }
          DiagnosticLogger.shared.logError(.ocr, error, "Remote translation failed")
          self?.finish(.failed(.other(error.localizedDescription)))
        }
      }
    case .unavailable:
      break
    }
  }

  func selectTarget(_ language: TranslationLanguage) {
    TranslationLanguage.storeTarget(language)
    target = language
    start()
  }

  /// Explicit, one-off switch to the custom endpoint for this card only. The
  /// persisted engine selection is not changed.
  func translateWithAlternativeEndpoint() {
    guard let alternativeEndpoint else { return }
    DiagnosticLogger.shared.log(.info, .ocr, "Translation retried with custom endpoint by user")
    route = .remote(alternativeEndpoint)
    start()
  }

  func cancel() {
    remoteTask?.cancel()
    remoteTask = nil
  }

  @available(macOS 15.0, *)
  func runApple(session: TranslationSession) async {
    guard phase == .translating, isAppleRoute else { return }
    let startTime = CFAbsoluteTimeGetCurrent()
    do {
      let output = try await AppleTranslationRunner.run(sourceText, session: session)
      DiagnosticLogger.shared.log(
        .info,
        .ocr,
        "Apple translation completed",
        context: ["durationMs": String(Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000))]
      )
      finish(.done(output))
    } catch {
      let failure = AppleTranslationRunner.failure(from: error)
      DiagnosticLogger.shared.log(.warning, .ocr, "Apple translation failed", context: ["failure": "\(failure)"])
      finish(.failed(failure))
    }
  }

  private func finish(_ newPhase: Phase) {
    phase = newPhase
  }

  private func isSameLanguage(_ target: TranslationLanguage) -> Bool {
    guard let detectedSourceIdentifier else { return false }
    let source = Locale.Language(identifier: detectedSourceIdentifier)
    let targetLanguage = target.localeLanguage
    guard source.languageCode == targetLanguage.languageCode else { return false }
    // zh-Hans vs zh-Hant are different targets.
    return source.script == nil || targetLanguage.script == nil || source.script == targetLanguage.script
  }
}
