//
//  PlaceholderSettingsView.swift
//  Snapzy
//
//  Placeholder views for future preference tabs
//

import SwiftUI

struct PlaceholderSettingsView: View {
  let title: String
  let icon: String
  let description: String

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: icon)
        .font(.system(size: 48))
        .foregroundColor(.secondary)

      Text(title)
        .font(.title2)
        .fontWeight(.medium)

      Text(description)
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 300)

      Text("Coming Soon")
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Static Factory Methods

extension PlaceholderSettingsView {
  static var wallpaper: PlaceholderSettingsView {
    PlaceholderSettingsView(
      title: "Wallpaper",
      icon: "photo.artframe",
      description: "Customize screenshot backgrounds, add frames, and apply visual effects."
    )
  }

  static var recording: PlaceholderSettingsView {
    PlaceholderSettingsView(
      title: "Recording",
      icon: "video.fill",
      description: "Configure screen recording quality, format, and audio settings."
    )
  }

  static var cloud: PlaceholderSettingsView {
    PlaceholderSettingsView(
      title: "Cloud",
      icon: "cloud.fill",
      description: "Connect cloud services for automatic screenshot uploads and sharing."
    )
  }

  static var advanced: PlaceholderSettingsView {
    PlaceholderSettingsView(
      title: "Advanced",
      icon: "slider.horizontal.3",
      description: "Fine-tune performance, file naming, and other power-user settings."
    )
  }
}

#Preview("Wallpaper") {
  PlaceholderSettingsView.wallpaper
}

#Preview("Recording") {
  PlaceholderSettingsView.recording
}

#Preview("Cloud") {
  PlaceholderSettingsView.cloud
}

#Preview("Advanced") {
  PlaceholderSettingsView.advanced
}
