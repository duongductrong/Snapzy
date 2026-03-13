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
      Section("Position") {
        SettingRow(icon: "rectangle.leadinghalf.inset.filled", title: "Screen Edge", description: "Where the overlay appears") {
          Picker("", selection: $positionIsLeft) {
            Text("Left").tag(true)
            Text("Right").tag(false)
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .onChange(of: positionIsLeft) { newValue in
            manager.setPosition(newValue ? .bottomLeft : .bottomRight)
          }
        }
      }

      Section("Appearance") {
        SettingRow(icon: "arrow.up.left.and.arrow.down.right", title: "Overlay Size", description: "Adjust the floating preview size") {
          HStack(spacing: 8) {
            Text("S")
              .font(.caption)
              .foregroundColor(.secondary)
            Slider(value: $manager.overlayScale, in: 0.75...1.5, step: 0.25)
              .frame(width: 100)
            Text("L")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Section("Behaviors") {
        SettingRow(icon: "square.on.square", title: "Floating Overlay", description: "Show preview after capture") {
          Toggle("", isOn: $manager.isEnabled)
            .labelsHidden()
        }

        SettingRow(icon: "timer", title: "Auto-close", description: autoCloseDescription) {
          Toggle("", isOn: $manager.autoDismissEnabled)
            .labelsHidden()
        }

        if manager.autoDismissEnabled {
          HStack(spacing: 12) {
            Image(systemName: "clock")
              .font(.title2)
              .foregroundColor(.secondary)
              .frame(width: 28)

            Text("Close after")
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
          SettingRow(icon: "cursorarrow.motionlines", title: "Pause on Hover", description: "Pause countdown when hovering over the card") {
            Toggle("", isOn: $manager.pauseCountdownOnHover)
              .labelsHidden()
          }
        }

        SettingRow(icon: "hand.draw", title: "Drag & Drop", description: "Drag captures to other apps") {
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
      return "Closes after \(Int(manager.autoDismissDelay)) seconds"
    }
    return "Keep overlay open until dismissed"
  }
}

#Preview {
  QuickAccessSettingsView()
    .frame(width: 600, height: 450)
}
