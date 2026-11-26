//
//  AutomationTriggerActions.swift
//  Snapzy
//
//  "Run Automation" from a Quick Access card or a History item: runs the
//  automation on that item's file and reports a rejection as a toast.
//

import Foundation

@MainActor
enum AutomationTriggerActions {
  /// Runs on the card's file and reuses the card (an upload sets its cloud link;
  /// no second card, no new History entry).
  static func runFromQuickAccess(_ automationID: UUID, item: QuickAccessItem) {
    let input = AutomationInput(files: [item.url], isAlreadyInHistory: true, sourceQuickAccessItemID: item.id)
    QuickAccessManager.shared.pauseCountdownForActivity(item.id)
    Task {
      defer { QuickAccessManager.shared.resumeCountdownForActivity(item.id) }
      await run(automationID, invocation: .quickAccess, input: input)
    }
  }

  static func runFromHistory(_ automationID: UUID, record: CaptureHistoryRecord) {
    let input = AutomationInput(files: [record.fileURL], isAlreadyInHistory: true)
    Task {
      await run(automationID, invocation: .history, input: input)
    }
  }

  /// File kind of a History record, from its stored capture type.
  static func fileKind(of record: CaptureHistoryRecord) -> AutomationFileKind {
    switch record.captureType {
    case .screenshot: .image
    case .video: .video
    case .gif: .gif
    }
  }

  private static func run(_ automationID: UUID, invocation: AutomationInvocation, input: AutomationInput) async {
    let access = input.files.map { SandboxFileAccessManager.shared.beginAccessingURL($0) }
    defer { access.forEach { $0.stop() } }
    let outcome = await AutomationLauncher.shared.launch(.id(automationID), invocation: invocation, input: input)
    if case .rejected(let rejection) = outcome {
      AppToastManager.shared.show(message: rejection.localizedMessage, style: .warning)
    }
  }
}
