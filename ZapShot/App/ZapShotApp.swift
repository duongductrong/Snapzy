//
//  ZapShotApp.swift
//  ZapShot
//
//  Main app entry point
//

import SwiftUI

@main
struct ZapShotApp: App {
  @State private var showOnboarding = !OnboardingFlowView.hasCompletedOnboarding

  var body: some Scene {
    WindowGroup {
      if showOnboarding {
        OnboardingFlowView(onComplete: {
          showOnboarding = false
        })
        .frame(width: 500, height: 450)
      } else {
        ContentView()
      }
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)

    Settings {
      PreferencesView()
    }
  }
}
