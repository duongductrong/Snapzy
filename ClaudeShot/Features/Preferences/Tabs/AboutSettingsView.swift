//
//  AboutSettingsView.swift
//  ClaudeShot
//
//  About tab showing app info, version, and links
//

import SwiftUI
import Sparkle

struct AboutSettingsView: View {
  private let updater: SPUUpdater

  init() {
    updater = SPUStandardUpdaterController(
      startingUpdater: false,
      updaterDelegate: nil,
      userDriverDelegate: nil
    ).updater
  }

  private var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(version) (\(build))"
  }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      // App Icon
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 128, height: 128)

      // App Name
      Text("ClaudeShot")
        .font(.largeTitle)
        .fontWeight(.bold)

      // Version
      Text("Version \(appVersion)")
        .font(.subheadline)
        .foregroundColor(.secondary)

      // Description
      Text("A modern macOS screenshot application")
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)

      Spacer()

      // Action Buttons
      HStack(spacing: 16) {
        Button("Visit Website") {
          if let url = URL(string: "https://github.com/duongductrong/ClaudeShot") {
            NSWorkspace.shared.open(url)
          }
        }
        .buttonStyle(.bordered)

        Button("Check for Updates...") {
          updater.checkForUpdates()
        }
        .buttonStyle(.borderedProminent)
      }

      Spacer()
        .frame(height: 32)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }
}

#Preview {
  AboutSettingsView()
    .frame(width: 500, height: 400)
}
