//
//  AppleTranslationRunner.swift
//  Snapzy
//
//  Runs a translation on a TranslationSession handed out by SwiftUI's
//  `.translationTask` (the only way to get a session before macOS 26).
//

import Foundation
import NaturalLanguage
import Translation

/// Why a translation failed, mapped to user-facing copy by the card.
enum TranslationFailure: Equatable {
  /// Apple Translation can't translate between the detected source and the target.
  case unsupportedLanguagePair
  /// Apple Translation couldn't tell which language the text is in.
  case unableToIdentifyLanguage
  /// The user declined or cancelled the language download.
  case cancelled
  /// Endpoint/transport/other error with its description.
  case other(String)

  /// Apple failures that an explicit "Translate with <endpoint>" can work around.
  var canRetryWithEndpoint: Bool {
    switch self {
    case .unsupportedLanguagePair, .unableToIdentifyLanguage, .other:
      return true
    case .cancelled:
      return false
    }
  }
}

struct TranslationOutput: Equatable {
  let text: String
  /// BCP-47 id of the detected source language, when known.
  let sourceLanguageIdentifier: String?
}

@available(macOS 15.0, *)
enum AppleTranslationRunner {
  /// Translates line by line (see `TranslationTextSegments`) in one batch so
  /// layout is preserved and the session is used once.
  static func run(_ text: String, session: TranslationSession) async throws -> TranslationOutput {
    let segments = TranslationTextSegments(text: text)
    guard !segments.isEmpty else {
      return TranslationOutput(text: text, sourceLanguageIdentifier: nil)
    }

    let requests = segments.translatableTexts.enumerated().map { offset, line in
      TranslationSession.Request(sourceText: line, clientIdentifier: String(offset))
    }
    let responses = try await session.translations(from: requests)

    var translations = segments.translatableTexts
    for response in responses {
      guard let identifier = response.clientIdentifier, let offset = Int(identifier),
            translations.indices.contains(offset) else { continue }
      translations[offset] = response.targetText
    }

    return TranslationOutput(
      text: segments.rebuilt(with: translations),
      sourceLanguageIdentifier: responses.first.map { $0.sourceLanguage.minimalIdentifier }
    )
  }

  static func failure(from error: Error) -> TranslationFailure {
    if error is CancellationError {
      return .cancelled
    }
    if TranslationError.unsupportedLanguagePairing ~= error
      || TranslationError.unsupportedSourceLanguage ~= error
      || TranslationError.unsupportedTargetLanguage ~= error {
      return .unsupportedLanguagePair
    }
    if TranslationError.unableToIdentifyLanguage ~= error {
      return .unableToIdentifyLanguage
    }
    if #available(macOS 26.0, *), TranslationError.alreadyCancelled ~= error {
      return .cancelled
    }
    return .other(error.localizedDescription)
  }
}

enum TranslationSourceLanguageDetector {
  /// Best-effort dominant language of `text` (BCP-47), for the card header.
  static func detect(_ text: String) -> String? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
    return language.rawValue
  }
}
