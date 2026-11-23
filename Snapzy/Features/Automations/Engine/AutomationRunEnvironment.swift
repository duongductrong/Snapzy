//
//  AutomationRunEnvironment.swift
//  Snapzy
//
//  The app services automation steps touch, behind one seam so the runner and
//  step handlers can be tested without a pasteboard, network or windows.
//

import AppKit
import Foundation

@MainActor
protocol AutomationRunEnvironment: AnyObject {
  /// Bake the default canvas preset into a fresh screenshot (as standard routing does).
  func prepareScreenshot(_ url: URL) -> AnnotationSessionData?
  /// Copies image(s) and returns the pasteboard change count after the write.
  func copyImages(_ urls: [URL]) -> Int
  /// Writes plain text and returns the pasteboard change count after the write.
  func copyText(_ text: String) -> Int
  var pasteboardChangeCount: Int { get }

  var isCloudConfigured: Bool { get }
  func upload(_ url: URL) async throws -> CloudUploadResult

  /// Adds a Quick Access card and returns its item id.
  func showQuickAccess(_ url: URL, sessionData: AnnotationSessionData?) async -> UUID?
  func setCloudLink(quickAccessItemID: UUID, result: CloudUploadResult)
  func openAnnotate(_ url: URL, quickAccessItemID: UUID?, sessionData: AnnotationSessionData?)

  func recordHistory(_ url: URL) async
  func notify(title: String, body: String, isError: Bool) async
}

/// Production environment backed by the app's singletons.
@MainActor
final class LiveAutomationRunEnvironment: AutomationRunEnvironment {
  func prepareScreenshot(_ url: URL) -> AnnotationSessionData? {
    PostCaptureActionHandler.shared.applyDefaultPreset(toScreenshot: url)
  }

  func copyImages(_ urls: [URL]) -> Int {
    if urls.count == 1, let url = urls.first {
      ClipboardHelper.copyImage(from: url)
    } else {
      ClipboardHelper.copyFileURLs(urls)
    }
    return NSPasteboard.general.changeCount
  }

  func copyText(_ text: String) -> Int {
    CloudShareService.shared.copyToPasteboard(text)
  }

  var pasteboardChangeCount: Int {
    NSPasteboard.general.changeCount
  }

  var isCloudConfigured: Bool {
    CloudShareService.shared.isConfigured
  }

  func upload(_ url: URL) async throws -> CloudUploadResult {
    try await CloudShareService.shared.upload(fileURL: url)
  }

  func showQuickAccess(_ url: URL, sessionData: AnnotationSessionData?) async -> UUID? {
    guard let item = await QuickAccessManager.shared.addScreenshot(url: url) else { return nil }
    if let sessionData {
      AnnotateManager.shared.saveSessionData(sessionData, for: item.id)
    }
    return item.id
  }

  func setCloudLink(quickAccessItemID: UUID, result: CloudUploadResult) {
    QuickAccessManager.shared.setCloudURL(id: quickAccessItemID, url: result.publicURL, key: result.key)
  }

  func openAnnotate(_ url: URL, quickAccessItemID: UUID?, sessionData: AnnotationSessionData?) {
    if let quickAccessItemID,
       let item = QuickAccessManager.shared.items.first(where: { $0.id == quickAccessItemID })
    {
      AnnotateManager.shared.openAnnotation(for: item)
    } else {
      AnnotateManager.shared.openAnnotation(url: url, sessionData: sessionData)
    }
  }

  func recordHistory(_ url: URL) async {
    await PostCaptureActionHandler.shared.addScreenshotToHistory(url: url)
  }

  func notify(title: String, body: String, isError: Bool) async {
    let delivered = await SystemNotificationService.shared.post(title: title, body: body)
    if !delivered {
      AppToastManager.shared.show(message: body, style: isError ? .warning : .success)
    }
  }
}
