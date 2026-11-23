//
//  AutomationNotificationRouter.swift
//  Snapzy
//
//  Buttons on automation notifications. A failed run offers Retry (re-runs the
//  automation on the files it captured or was given) and Open Activity; a run
//  that produced a link or saved a file offers Open Link / Show in Finder.
//

import AppKit
import Combine
import Foundation
import UserNotifications

@MainActor
enum AutomationNotificationRouter {
  enum Category {
    static let failed = "automation.failed"
    static let succeededLink = "automation.succeeded.link"
    static let succeededFile = "automation.succeeded.file"
  }

  enum Action {
    static let retry = "automation.retry"
    static let openActivity = "automation.openActivity"
    static let openLink = "automation.openLink"
    static let reveal = "automation.reveal"
  }

  fileprivate enum Key {
    static let automationID = "automationID"
    static let files = "files"
    static let link = "link"
    static let saved = "saved"
  }

  /// Registers the categories and the tap handler. Call once at launch.
  static func install(
    service: SystemNotificationService? = nil,
    launcher: @escaping @MainActor (UUID, [URL]) -> Void = { id, files in
      Task { @MainActor in
        let outcome = await AutomationLauncher.shared.launch(
          .id(id),
          invocation: .retry,
          input: AutomationInput(files: files, isAlreadyInHistory: true)
        )
        if case .rejected(let rejection) = outcome {
          AppToastManager.shared.show(message: rejection.localizedMessage, style: .warning)
        }
      }
    }
  ) {
    let service = service ?? .shared
    let retry = UNNotificationAction(identifier: Action.retry, title: L10n.Automations.notificationRetry)
    let activity = UNNotificationAction(identifier: Action.openActivity, title: L10n.Automations.notificationOpenActivity)
    let openLink = UNNotificationAction(identifier: Action.openLink, title: L10n.Automations.notificationOpenLink)
    let reveal = UNNotificationAction(identifier: Action.reveal, title: L10n.Common.openInFinder)
    service.registerCategories([
      UNNotificationCategory(identifier: Category.failed, actions: [retry, activity], intentIdentifiers: []),
      UNNotificationCategory(identifier: Category.succeededLink, actions: [openLink], intentIdentifiers: []),
      UNNotificationCategory(identifier: Category.succeededFile, actions: [reveal], intentIdentifiers: []),
    ])
    service.actionHandler = { action, userInfo in
      handle(action: action, userInfo: userInfo, retry: launcher)
    }
  }

  /// Category and user info for a run's notification.
  static func payload(for context: AutomationNotificationContext) -> (category: String, userInfo: [String: String])? {
    var info = [Key.automationID: context.automationID.uuidString]
    switch context.outcome {
    case .failed:
      guard !context.inputFiles.isEmpty else { return nil }
      info[Key.files] = context.inputFiles.map(\.path).joined(separator: "\n")
      return (Category.failed, info)
    case .succeeded:
      if let link = context.link {
        info[Key.link] = link.absoluteString
        return (Category.succeededLink, info)
      }
      if let saved = context.savedFile {
        info[Key.saved] = saved.path
        return (Category.succeededFile, info)
      }
      return nil
    }
  }

  static func handle(
    action: String,
    userInfo: [String: String],
    retry: @MainActor (UUID, [URL]) -> Void
  ) {
    switch action {
    case Action.retry:
      guard let id = userInfo[Key.automationID].flatMap(UUID.init(uuidString:)) else { return }
      let files = (userInfo[Key.files] ?? "")
        .split(separator: "\n")
        .map { URL(fileURLWithPath: String($0)) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
      guard !files.isEmpty else {
        AppToastManager.shared.show(message: L10n.Automations.errorRetryFilesMissing, style: .warning)
        return
      }
      retry(id, files)
    case Action.openActivity:
      openActivity()
    case Action.openLink:
      openLink(userInfo)
    case Action.reveal:
      reveal(userInfo)
    case UNNotificationDefaultActionIdentifier:
      // Clicking the banner itself: the most useful thing for that outcome.
      if userInfo[Key.files] != nil {
        openActivity()
      } else if userInfo[Key.link] != nil {
        openLink(userInfo)
      } else if userInfo[Key.saved] != nil {
        reveal(userInfo)
      }
    default:
      break
    }
  }
}

extension AutomationNotificationRouter {
  private static func openActivity() {
    AutomationSettingsNavigation.shared.page = .activity
    AppStatusBarController.shared.openPreferencesWindow(tab: .automations)
  }

  private static func openLink(_ userInfo: [String: String]) {
    guard let link = userInfo[Key.link].flatMap(URL.init(string:)) else { return }
    NSWorkspace.shared.open(link)
  }

  private static func reveal(_ userInfo: [String: String]) {
    guard let path = userInfo[Key.saved] else { return }
    FileRevealer.reveal([URL(fileURLWithPath: path)])
  }
}

/// Which Settings → Automations page is shown (list or activity log).
@MainActor
final class AutomationSettingsNavigation: ObservableObject {
  enum Page: String, CaseIterable, Identifiable {
    case automations
    case activity

    var id: String { rawValue }
  }

  static let shared = AutomationSettingsNavigation()

  @Published var page: Page = .automations
}
