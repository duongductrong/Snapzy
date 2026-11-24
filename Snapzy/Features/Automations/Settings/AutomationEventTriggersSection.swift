//
//  AutomationEventTriggersSection.swift
//  Snapzy
//
//  Editor section "Run Automatically" (milestone 7): the event triggers —
//  after a Snapzy capture is saved, when another app copies an image, when a
//  file is added to a folder.
//

import AppKit
import SwiftUI

struct AutomationEventTriggersSection: View {
  @Binding var automation: Automation
  @AppStorage(PreferencesKeys.automationsEventTriggersPaused) private var eventsPaused = false

  var body: some View {
    Section {
      captureSavedRows
      Toggle(isOn: $automation.runsOnClipboardChange) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.Automations.eventClipboard)
          caption(L10n.Automations.eventClipboardDescription)
        }
      }
      folderRows
    } header: {
      Text(L10n.Automations.eventsHeader)
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        if eventsPaused, automation.hasEventTriggers {
          Label(L10n.Automations.eventsPausedGlobally, systemImage: "pause.circle")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        caption(L10n.Automations.eventsFooter)
      }
    }
  }

  // MARK: Capture saved

  @ViewBuilder
  private var captureSavedRows: some View {
    Toggle(L10n.Automations.eventCaptureSaved, isOn: Binding(
      get: { automation.captureEvent != nil },
      set: { automation.captureEvent = $0 ? AutomationCaptureEventConfig() : nil }
    ))
    if automation.captureEvent != nil {
      Picker(L10n.Automations.eventCaptureKinds, selection: captureKindsBinding) {
        Text(L10n.Automations.eventCaptureScreenshots).tag(CaptureKindChoice.screenshots)
        Text(L10n.Automations.eventCaptureRecordings).tag(CaptureKindChoice.recordings)
        Text(L10n.Automations.eventCaptureBoth).tag(CaptureKindChoice.both)
      }
      .pickerStyle(.segmented)
    }
  }

  private enum CaptureKindChoice: Hashable {
    case screenshots, recordings, both

    var kinds: Set<AutomationCaptureEventKind> {
      switch self {
      case .screenshots: [.screenshot]
      case .recordings: [.recording]
      case .both: [.screenshot, .recording]
      }
    }

    init(_ kinds: Set<AutomationCaptureEventKind>) {
      switch kinds {
      case [.recording]: self = .recordings
      case [.screenshot, .recording]: self = .both
      default: self = .screenshots
      }
    }
  }

  private var captureKindsBinding: Binding<CaptureKindChoice> {
    Binding(
      get: { CaptureKindChoice(automation.captureEvent?.kinds ?? [.screenshot]) },
      set: { automation.captureEvent = AutomationCaptureEventConfig(kinds: $0.kinds) }
    )
  }

  // MARK: Folder

  @ViewBuilder
  private var folderRows: some View {
    Toggle(L10n.Automations.eventFolder, isOn: Binding(
      get: { automation.folderWatch != nil },
      set: { isOn in
        if isOn {
          // Ask for the folder right away; keep the toggle off when cancelled.
          guard let picked = AutomationFolderAccessStore.shared.chooseFolder() else { return }
          automation.folderWatch = AutomationFolderWatchConfig(folder: picked.ref, folderPath: picked.path)
        } else {
          automation.folderWatch = nil
        }
      }
    ))
    if let config = automation.folderWatch {
      HStack(spacing: 8) {
        Image(systemName: isAvailable(config) ? "folder" : "exclamationmark.triangle.fill")
          .foregroundStyle(isAvailable(config) ? Color.secondary : Color.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text(displayPath(config))
            .lineLimit(1)
            .truncationMode(.middle)
          if !isAvailable(config) {
            caption(L10n.Automations.eventFolderMissing)
          }
        }
        Spacer()
        Button(L10n.Automations.eventFolderChange) {
          let start = config.folder.flatMap { AutomationFolderAccessStore.shared.resolve($0) }
          if let picked = AutomationFolderAccessStore.shared.chooseFolder(startingAt: start) {
            automation.folderWatch = AutomationFolderWatchConfig(folder: picked.ref, folderPath: picked.path)
          }
        }
      }
    }
  }

  private func isAvailable(_ config: AutomationFolderWatchConfig) -> Bool {
    guard let ref = config.folder else { return false }
    return AutomationFolderAccessStore.shared.resolve(ref) != nil
  }

  private func displayPath(_ config: AutomationFolderWatchConfig) -> String {
    let path = config.folder.flatMap { AutomationFolderAccessStore.shared.path(for: $0) } ?? config.folderPath
    guard let path else { return L10n.Automations.eventFolderNone }
    return (path as NSString).abbreviatingWithTildeInPath
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }
}
