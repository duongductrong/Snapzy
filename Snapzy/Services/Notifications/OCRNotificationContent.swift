//
//  OCRNotificationContent.swift
//  Snapzy
//
//  Builds the title and body shown in the OCR result notification
//

import Foundation

/// The user-visible result of one OCR capture action.
enum OCRCaptureOutcome {
  /// Text (and optionally QR payloads) landed on the clipboard.
  case copied(String)
  /// Nothing readable was found in the selected area.
  case noText
  /// A QR code was present but its payload cannot be represented as text.
  case qrTextOnlyUnsupported
  /// Recognition threw before producing a result. The associated value is the underlying
  /// error description, used by the in-app fallback toast; the notification itself keeps
  /// the generic wording.
  case failed(errorDescription: String)
}

/// Pure formatting for OCR notifications. Kept free of AppKit so it stays unit-testable.
enum OCRNotificationContent {

  /// Notification bodies stay short; the clipboard always holds the full text.
  static let previewCharacterLimit = 200

  static func title(for outcome: OCRCaptureOutcome) -> String {
    switch outcome {
    case .copied:
      return L10n.OCR.notificationCopiedTitle
    case .noText, .qrTextOnlyUnsupported:
      return L10n.OCR.notificationNoTextTitle
    case .failed:
      return L10n.OCR.notificationFailedTitle
    }
  }

  static func body(for outcome: OCRCaptureOutcome) -> String {
    switch outcome {
    case .copied(let text):
      return preview(text)
    case .noText:
      return L10n.OCR.notificationNoTextBody
    case .qrTextOnlyUnsupported:
      return L10n.OCR.qrTextOnlyUnsupported
    case .failed:
      return L10n.OCR.notificationFailedBody
    }
  }

  /// Collapse recognized text into a single-line preview capped at `limit` characters.
  ///
  /// Truncation counts grapheme clusters, so emoji, CJK, and combining diacritics are
  /// never split mid-character.
  static func preview(_ text: String, limit: Int = previewCharacterLimit) -> String {
    let collapsed = text
      .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
      .joined(separator: " ")

    guard limit > 0 else { return "" }
    guard collapsed.count > limit else { return collapsed }

    let truncated = collapsed
      .prefix(limit)
      .reversed()
      .drop(while: { $0.isWhitespace })
      .reversed()

    return String(truncated) + "…"
  }
}
