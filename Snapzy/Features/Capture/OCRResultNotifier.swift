//
//  OCRResultNotifier.swift
//  Snapzy
//
//  Announces the outcome of an OCR capture, preferring a native macOS notification
//

import Foundation

/// Reports the result of one OCR capture to the user.
///
/// Preferred surface is a native macOS notification. When notifications are turned off in
/// Preferences, or macOS refuses to deliver them, the previous in-app toast is used so OCR
/// never completes silently. Exactly one of the two is shown per capture.
@MainActor
final class OCRResultNotifier {

  static let shared = OCRResultNotifier()

  private let notificationService: SystemNotificationService

  init(notificationService: SystemNotificationService = .shared) {
    self.notificationService = notificationService
  }

  static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
    defaults.object(forKey: PreferencesKeys.ocrSuccessNotificationEnabled) as? Bool ?? true
  }

  /// Announce `outcome`. Delivery runs detached so a first-run authorization prompt never
  /// stalls the rest of the OCR flow (clipboard write, link detection).
  func report(_ outcome: OCRCaptureOutcome) {
    guard Self.isEnabled() else {
      showFallback(for: outcome, notificationsEnabled: false)
      return
    }

    Task { @MainActor in
      let delivered = await notificationService.post(
        title: OCRNotificationContent.title(for: outcome),
        body: OCRNotificationContent.body(for: outcome)
      )
      if !delivered {
        showFallback(for: outcome, notificationsEnabled: true)
      }
    }
  }

  // MARK: - In-app fallback

  private func showFallback(for outcome: OCRCaptureOutcome, notificationsEnabled: Bool) {
    switch outcome {
    case .copied:
      // With notifications turned off, a successful OCR reports nothing — the text is on
      // the clipboard. This matches the behavior when the preference was off before.
      guard notificationsEnabled else { return }
      AppToastManager.shared.show(
        message: L10n.Common.copiedToClipboard,
        style: .success,
        position: .bottomCenter
      )
    case .noText:
      AppToastManager.shared.show(
        message: L10n.OCR.noTextFound,
        style: .warning,
        position: .bottomCenter
      )
    case .qrTextOnlyUnsupported:
      AppToastManager.shared.show(
        message: L10n.OCR.qrTextOnlyUnsupported,
        style: .warning,
        position: .bottomCenter
      )
    case .failed(let errorDescription):
      AppToastManager.shared.show(
        message: errorDescription,
        style: .error,
        position: .bottomCenter
      )
    }
  }
}
