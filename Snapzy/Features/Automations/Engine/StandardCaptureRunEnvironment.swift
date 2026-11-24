//
//  StandardCaptureRunEnvironment.swift
//  Snapzy
//
//  Environment for a standard capture's default after-capture automation
//  (milestone 6). Uses the post-capture handler's Quick Access manager and
//  preset applier so the run behaves exactly like the legacy matrix handler:
//  Pin pins the card this run created, Annotate opens that card's item.
//

import Foundation

@MainActor
final class StandardCaptureRunEnvironment: LiveAutomationRunEnvironment {
  private let quickAccess: QuickAccessManaging
  private let prepare: (URL) -> AnnotationSessionData?
  /// Quick Access / pinned items this run created, by file.
  private var items: [URL: QuickAccessItem] = [:]

  init(quickAccess: QuickAccessManaging, prepare: @escaping (URL) -> AnnotationSessionData?) {
    self.quickAccess = quickAccess
    self.prepare = prepare
    super.init()
  }

  /// The card (or pin window) the run made for `url`.
  func item(for url: URL) -> QuickAccessItem? {
    items[url]
  }

  override func prepareScreenshot(_ url: URL) -> AnnotationSessionData? {
    prepare(url)
  }

  override func showQuickAccess(_ url: URL, kind: AutomationFileKind, sessionData: AnnotationSessionData?) async -> UUID? {
    let item: QuickAccessItem?
    if kind == .image {
      item = await quickAccess.addScreenshot(url: url)
      if let item, let sessionData {
        AnnotateManager.shared.saveSessionData(sessionData, for: item.id)
      }
    } else {
      item = await quickAccess.addVideo(url: url)
    }
    guard let item else { return nil }
    items[url] = item
    return item.id
  }

  override func pin(_ url: URL) async -> Bool {
    if let item = items[url] {
      quickAccess.pinScreenshot(id: item.id)
      return true
    }
    guard let item = await quickAccess.pinScreenshot(url: url) else { return false }
    items[url] = item
    return true
  }

  override func openAnnotate(_ url: URL, quickAccessItemID: UUID?, sessionData: AnnotationSessionData?) {
    if let item = items[url] {
      AnnotateManager.shared.openAnnotation(for: item)
    } else {
      super.openAnnotate(url, quickAccessItemID: quickAccessItemID, sessionData: sessionData)
    }
  }
}
