//
//  PreferencesUpdateChannelSection.swift
//  Snapzy
//
//  Stable/Beta update channel picker for the About tab, with beta risk warning.
//

import SwiftUI

struct UpdateChannelSectionView: View {
  @AppStorage(PreferencesKeys.updateChannel)
  private var updateChannel: String = UpdateChannel.stable.rawValue

  var body: some View {
    VStack(spacing: 0) {
      SettingRow(
        icon: "shippingbox",
        title: L10n.PreferencesAbout.updateChannelTitle,
        description: L10n.PreferencesAbout.updateChannelDescription
      ) {
        Picker("", selection: $updateChannel) {
          Text(L10n.PreferencesAbout.updateChannelStable).tag(UpdateChannel.stable.rawValue)
          Text(L10n.PreferencesAbout.updateChannelBeta).tag(UpdateChannel.beta.rawValue)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xs)

      if updateChannel == UpdateChannel.beta.rawValue {
        HStack(alignment: .top, spacing: Spacing.sm) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundColor(.orange)
          Text(L10n.PreferencesAbout.updateChannelBetaWarning)
            .font(.caption)
            .foregroundColor(.orange)
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.sm)
      }
    }
    .background(Color.primary.opacity(0.03))
    .clipShape(Radius.rect(Radius.card))
    .overlay(
      Radius.rect(Radius.card)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    )
    .frame(maxWidth: 420)
    .onChange(of: updateChannel) { _ in
      SnapzyConfigurationSyncCoordinator.shared.scheduleSync(reason: .explicitChange)
      UpdaterManager.shared.checkForUpdates()
    }
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
    UpdateChannelSectionView()
  }
  .padding()
  .frame(width: 700)
}
