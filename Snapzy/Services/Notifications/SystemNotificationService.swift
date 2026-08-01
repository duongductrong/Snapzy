//
//  SystemNotificationService.swift
//  Snapzy
//
//  Posts native macOS notifications through UserNotifications
//

import AppKit
import Foundation
import UserNotifications

/// Whether Snapzy is currently allowed to post notifications.
enum SystemNotificationAuthorization: Equatable {
  /// Notifications cannot be used at all in this process (no bundle proxy).
  case unavailable
  /// The user has not been asked yet.
  case notDetermined
  case authorized
  case denied

  var isAuthorized: Bool { self == .authorized }
}

/// Delivers native macOS notifications.
///
/// Every call is best-effort: when the bundle cannot host notifications, the user denied
/// authorization, or the notification center rejects the request, `post` returns `false`
/// so callers can fall back to in-app feedback instead of leaving the user with nothing.
@MainActor
final class SystemNotificationService {

  static let shared = SystemNotificationService()

  private let center: UNUserNotificationCenter?
  private let presentationDelegate = ForegroundPresentationDelegate()
  private var didRequestAuthorization = false

  private init() {
    // `UNUserNotificationCenter.current()` traps when the process has no bundle proxy
    // (command-line hosts, some test runners), so resolve it defensively.
    guard Bundle.main.bundleIdentifier != nil else {
      center = nil
      return
    }
    let center = UNUserNotificationCenter.current()
    center.delegate = presentationDelegate
    self.center = center
  }

  /// Post a notification.
  /// - Returns: `true` when the request was handed to the notification center.
  @discardableResult
  func post(title: String, body: String) async -> Bool {
    guard let center else {
      DiagnosticLogger.shared.log(.debug, .system, "System notification skipped: no bundle identifier")
      return false
    }

    guard await isAuthorized(center) else { return false }

    let content = UNMutableNotificationContent()
    content.title = title
    if !body.isEmpty {
      content.body = body
    }
    // Snapzy plays its own capture sounds; a notification sound would double up.
    content.sound = nil

    // A fresh identifier per call keeps one notification per action instead of
    // replacing the previous one.
    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil
    )

    do {
      try await center.add(request)
      return true
    } catch {
      DiagnosticLogger.shared.logError(.system, error, "System notification delivery failed")
      return false
    }
  }

  // MARK: - Authorization

  /// Current authorization, without prompting.
  func authorizationStatus() async -> SystemNotificationAuthorization {
    guard let center else { return .unavailable }

    switch await center.notificationSettings().authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return .authorized
    case .notDetermined:
      return .notDetermined
    case .denied:
      return .denied
    @unknown default:
      return .denied
    }
  }

  /// Show the system authorization prompt. Use for explicit user actions such as the
  /// onboarding permission row, which should always be able to retry.
  @discardableResult
  func requestAuthorization() async -> Bool {
    guard let center else { return false }
    didRequestAuthorization = true
    return await performAuthorizationRequest(center)
  }

  /// Open System Settings on the Notifications pane, for when authorization was denied and
  /// only the user can reverse it.
  func openSystemSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
    NSWorkspace.shared.open(url)
  }

  private func isAuthorized(_ center: UNUserNotificationCenter) async -> Bool {
    switch await center.notificationSettings().authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    case .notDetermined:
      // Only prompt once per launch on this implicit path; a declined prompt must not
      // re-ask on every capture. Explicit `requestAuthorization()` calls are not gated.
      guard !didRequestAuthorization else { return false }
      didRequestAuthorization = true
      return await performAuthorizationRequest(center)
    case .denied:
      return false
    @unknown default:
      return false
    }
  }

  private func performAuthorizationRequest(_ center: UNUserNotificationCenter) async -> Bool {
    do {
      let granted = try await center.requestAuthorization(options: [.alert])
      DiagnosticLogger.shared.log(
        .info,
        .system,
        "System notification authorization resolved",
        context: ["granted": "\(granted)"]
      )
      return granted
    } catch {
      DiagnosticLogger.shared.logError(.system, error, "System notification authorization failed")
      return false
    }
  }
}

/// Keeps banners visible while Snapzy is the frontmost app, which happens whenever a
/// capture is triggered from the menu bar or an open Snapzy window.
private final class ForegroundPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }
}
