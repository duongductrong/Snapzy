//
//  UpdatesCheckForUpdatesView.swift
//  Snapzy
//
//  Reusable "Check for Updates" button + Sparkle status view model
//

import Combine
import Sparkle
import SwiftUI

final class CheckForUpdatesViewModel: ObservableObject {
  private let updater: SPUUpdater

  @Published var canCheckForUpdates = false
  @Published var lastUpdateCheckDate: Date?

  init(updater: SPUUpdater) {
    self.updater = updater
    updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)
    updater.publisher(for: \.lastUpdateCheckDate)
      .assign(to: &$lastUpdateCheckDate)
  }

  func checkForUpdates() {
    updater.checkForUpdates()
  }
}

struct CheckForUpdatesView<Label: View>: View {
  @ObservedObject private var viewModel: CheckForUpdatesViewModel
  private let label: () -> Label

  init(viewModel: CheckForUpdatesViewModel, @ViewBuilder label: @escaping () -> Label) {
    self.viewModel = viewModel
    self.label = label
  }

  var body: some View {
    Button(action: viewModel.checkForUpdates, label: label)
      .disabled(!viewModel.canCheckForUpdates)
  }
}
