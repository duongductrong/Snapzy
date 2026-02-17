//
//  CrashSentinel.swift
//  Snapzy
//
//  Flag-based crash detection using UserDefaults
//

import Foundation

final class CrashSentinel {
  static let shared = CrashSentinel()

  private let sessionActiveKey = PreferencesKeys.diagnosticsSessionActive

  /// Whether the previous session ended abnormally (crash / force-quit)
  private(set) var didCrashLastSession: Bool = false

  private init() {}

  // MARK: - Lifecycle

  /// Call at launch — reads crash flag, then sets it for the new session.
  /// Returns `true` if the previous session crashed.
  @discardableResult
  func checkAndReset() -> Bool {
    let wasActive = UserDefaults.standard.bool(forKey: sessionActiveKey)
    didCrashLastSession = wasActive

    // Mark new session as active
    UserDefaults.standard.set(true, forKey: sessionActiveKey)

    return didCrashLastSession
  }

  /// Call on clean termination (`applicationWillTerminate`).
  func markTerminated() {
    UserDefaults.standard.set(false, forKey: sessionActiveKey)
  }
}
