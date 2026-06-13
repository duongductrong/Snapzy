//
//  QuickAccessSettingsView.swift
//  Snapzy
//
//  Quick Access (floating overlay) settings tab
//

import SwiftUI

struct QuickAccessSettingsView: View {
  @ObservedObject private var manager = QuickAccessManager.shared
  @ObservedObject private var swipeConfiguration = QuickAccessSwipeConfigurationStore.shared

  @State private var positionIsLeft: Bool = false

  var body: some View {
    Form {
      QuickAccessActionCustomizationView(manager: manager)

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
            Slider(value: $manager.overlayScale.stepped(by: 0.25, in: 0.75...1.5), in: 0.75...1.5)
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

            Slider(value: $manager.autoDismissDelay.stepped(by: 1, in: 3...30), in: 3...30)
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

        SettingRow(icon: "hand.point.right", title: L10n.PreferencesQuickAccess.twoFingerSwipeTitle, description: L10n.PreferencesQuickAccess.twoFingerSwipeDescription) {
          Toggle("", isOn: $manager.twoFingerSwipeToDismissEnabled)
            .labelsHidden()
        }

        if manager.twoFingerSwipeToDismissEnabled {
          SettingRow(icon: "gauge.with.dots.needle.33percent", title: L10n.PreferencesQuickAccess.swipeSensitivityTitle, description: L10n.PreferencesQuickAccess.swipeSensitivityDescription) {
            HStack(spacing: 8) {
              Slider(value: $manager.swipeSensitivity.stepped(by: 0.25, in: 0.5...3.0), in: 0.5...3.0)
                .frame(width: 100)
              Text("\(Int(manager.swipeSensitivity * 100))%")
                .frame(width: 42)
                .monospacedDigit()
                .foregroundColor(.secondary)
            }
          }
        }
      }

      Section(L10n.PreferencesQuickAccess.swipeGesturesSection) {
        swipeBehaviorRow(
          icon: "arrow.left",
          direction: .left,
          behavior: Binding(
            get: { swipeConfiguration.leftBehavior },
            set: { swipeConfiguration.setBehavior($0, for: .left) }
          )
        )

        swipeBehaviorRow(
          icon: "arrow.right",
          direction: .right,
          behavior: Binding(
            get: { swipeConfiguration.rightBehavior },
            set: { swipeConfiguration.setBehavior($0, for: .right) }
          )
        )
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

  private func swipeBehaviorRow(
    icon: String,
    direction: QuickAccessSwipeDirection,
    behavior: Binding<QuickAccessSwipeBehavior>
  ) -> some View {
    SettingRow(
      icon: icon,
      title: direction.displayName,
      description: nil
    ) {
      Picker("", selection: behavior) {
        ForEach(QuickAccessSwipeBehavior.allCases) { behavior in
          Text(behavior.displayName).tag(behavior)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()
      .frame(width: 160, alignment: .trailing)
    }
  }
}

#Preview {
  QuickAccessSettingsView()
    .frame(width: 600, height: 450)
}
