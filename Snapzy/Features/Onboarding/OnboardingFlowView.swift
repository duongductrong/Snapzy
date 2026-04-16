//
//  OnboardingFlowView.swift
//  Snapzy
//
//  Static helpers for onboarding state — flow is now managed by SplashOnboardingRootView
//

import SwiftUI

struct OnboardingFlowView {
  private static let onboardingCompletedKey = PreferencesKeys.onboardingCompleted

  static var hasCompletedOnboarding: Bool {
    UserDefaults.standard.bool(forKey: onboardingCompletedKey)
  }

  static func resetOnboarding() {
    UserDefaults.standard.set(false, forKey: onboardingCompletedKey)
    UserDefaults.standard.set(false, forKey: PreferencesKeys.splashSkipped)
    UserDefaults.standard.removeObject(forKey: PreferencesKeys.splashSkipOnceAfterOnboardingRelaunch)
  }
}
