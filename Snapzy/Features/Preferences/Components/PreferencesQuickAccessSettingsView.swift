//
//  QuickAccessSettingsView.swift
//  Snapzy
//
//  Quick Access (floating overlay) settings tab
//

import SwiftUI

struct QuickAccessSettingsView: View {
  @ObservedObject private var manager = QuickAccessManager.shared

  @State private var positionIsLeft: Bool = false

  var body: some View {
    Form {
      Section(L10n.PreferencesQuickAccess.positionSection) {
        SettingRow(icon: "rectangle.leadinghalf.inset.filled", title: L10n.PreferencesQuickAccess.screenEdgeTitle, description: L10n.PreferencesQuickAccess.screenEdgeDescription) {
          Picker("", selection: $positionIsLeft) {
            Text(L10n.PreferencesQuickAccess.left).tag(true)
            Text(L10n.PreferencesQuickAccess.right).tag(false)
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .onChange(of: positionIsLeft) { newValue in
            manager.setPosition(newValue ? .bottomLeft : .bottomRight)
          }
        }
      }

      Section(L10n.PreferencesQuickAccess.appearanceSection) {
        SettingRow(icon: "arrow.up.left.and.arrow.down.right", title: L10n.PreferencesQuickAccess.overlaySizeTitle, description: L10n.PreferencesQuickAccess.overlaySizeDescription) {
          HStack(spacing: 8) {
            Text(verbatim: "S")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $manager.overlayScale, in: 0.75...1.5, step: 0.25)
              .frame(width: 100)
            Text(verbatim: "L")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Section(L10n.PreferencesQuickAccess.behaviorsSection) {
        SettingRow(icon: "square.on.square", title: L10n.PreferencesQuickAccess.floatingOverlayTitle, description: L10n.PreferencesQuickAccess.floatingOverlayDescription) {
          Toggle("", isOn: $manager.isEnabled)
            .labelsHidden()
        }

        SettingRow(icon: "timer", title: L10n.PreferencesQuickAccess.autoCloseTitle, description: autoCloseDescription) {
          Toggle("", isOn: $manager.autoDismissEnabled)
            .labelsHidden()
        }

        if manager.autoDismissEnabled {
          HStack(spacing: 12) {
            Image(systemName: "clock")
              .font(.title2)
              .foregroundColor(.secondary)
              .frame(width: 28)

            Text(L10n.PreferencesQuickAccess.closeAfter)
              .fontWeight(.medium)

            Spacer()

            Slider(value: $manager.autoDismissDelay, in: 3...30, step: 1)
              .frame(width: 120)

            Text("\(Int(manager.autoDismissDelay))s")
              .frame(width: 35)
              .monospacedDigit()
              .foregroundColor(.secondary)
          }
          .padding(.vertical, 4)
        }

        if manager.autoDismissEnabled {
          SettingRow(icon: "cursorarrow.motionlines", title: L10n.PreferencesQuickAccess.pauseOnHoverTitle, description: L10n.PreferencesQuickAccess.pauseOnHoverDescription) {
            Toggle("", isOn: $manager.pauseCountdownOnHover)
              .labelsHidden()
          }
        }

        SettingRow(icon: "hand.draw", title: L10n.PreferencesQuickAccess.dragAndDropTitle, description: L10n.PreferencesQuickAccess.dragAndDropDescription) {
          Toggle("", isOn: $manager.dragDropEnabled)
            .labelsHidden()
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      positionIsLeft = manager.position.isLeftSide
    }
  }

  // MARK: - Helpers

  private var autoCloseDescription: String {
    if manager.autoDismissEnabled {
      return L10n.PreferencesQuickAccess.closesAfter(Int(manager.autoDismissDelay))
    }
    return L10n.PreferencesQuickAccess.keepOpenUntilDismissed
  }
}

#Preview {
  QuickAccessSettingsView()
    .frame(width: 600, height: 450)
}
