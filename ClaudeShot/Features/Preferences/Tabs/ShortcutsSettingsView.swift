//
//  ShortcutsSettingsView.swift
//  ClaudeShot
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
        Toggle("Enable global keyboard shortcuts", isOn: $shortcutsEnabled)
          .onChange(of: shortcutsEnabled) { _, newValue in
            if newValue {
              manager.enable()
            } else {
              manager.disable()
            }
          }
      }

      if shortcutsEnabled {
        Section("Capture") {
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
        }

        Section {
          Text("Click a shortcut button to record new keys. Press Esc to cancel.")
            .font(.caption)
            .foregroundColor(.secondary)
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
        .padding()
      }
    }
  }

  private func resetToDefaults() {
    fullscreenShortcut = .defaultFullscreen
    areaShortcut = .defaultArea
    manager.setFullscreenShortcut(.defaultFullscreen)
    manager.setAreaShortcut(.defaultArea)
  }
}

#Preview {
  ShortcutsSettingsView()
    .frame(width: 500, height: 400)
}
