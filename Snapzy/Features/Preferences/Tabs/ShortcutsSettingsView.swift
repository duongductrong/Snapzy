//
//  ShortcutsSettingsView.swift
//  Snapzy
//
//  Keyboard shortcuts configuration tab
//

import SwiftUI

struct ShortcutsSettingsView: View {
  @State private var fullscreenShortcut: ShortcutConfig
  @State private var areaShortcut: ShortcutConfig
  @State private var shortcutsEnabled: Bool

  private let manager = KeyboardShortcutManager.shared

  init() {
    _fullscreenShortcut = State(initialValue: KeyboardShortcutManager.shared.fullscreenShortcut)
    _areaShortcut = State(initialValue: KeyboardShortcutManager.shared.areaShortcut)
    _shortcutsEnabled = State(initialValue: KeyboardShortcutManager.shared.isEnabled)
  }

  var body: some View {
    Form {
      Section("Global Shortcuts") {
        Text("Use keyboard shortcuts to capture from anywhere.")
          .font(.caption)
          .foregroundColor(.secondary)

        settingRow(icon: "keyboard", title: "Enable Shortcuts", description: "Capture from any app") {
          Toggle("", isOn: $shortcutsEnabled)
            .labelsHidden()
            .onChange(of: shortcutsEnabled) { _, newValue in
              if newValue {
                manager.enable()
              } else {
                manager.disable()
              }
            }
        }
      }

      if shortcutsEnabled {
        Section("Capture Shortcuts") {
          ShortcutRecorderView(
            label: "Capture Fullscreen",
            shortcut: $fullscreenShortcut,
            onShortcutChanged: { manager.setFullscreenShortcut($0) }
          )

          ShortcutRecorderView(
            label: "Capture Area",
            shortcut: $areaShortcut,
            onShortcutChanged: { manager.setAreaShortcut($0) }
          )

          Text("Click a shortcut button to record new keys. Press Esc to cancel.")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }
      }
    }
    .formStyle(.grouped)
    .safeAreaInset(edge: .bottom) {
      HStack {
        Spacer()
        Button("Reset to Defaults") {
          resetToDefaults()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding()
      }
    }
  }

  // MARK: - Setting Row Helper

  @ViewBuilder
  private func settingRow<Content: View>(
    icon: String,
    title: String,
    description: String?,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.secondary)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .fontWeight(.medium)
        if let description {
          Text(description)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }

      Spacer()
      content()
    }
    .padding(.vertical, 4)
  }

  // MARK: - Actions

  private func resetToDefaults() {
    fullscreenShortcut = .defaultFullscreen
    areaShortcut = .defaultArea
    manager.setFullscreenShortcut(.defaultFullscreen)
    manager.setAreaShortcut(.defaultArea)
  }
}

#Preview {
  ShortcutsSettingsView()
    .frame(width: 600, height: 400)
}
