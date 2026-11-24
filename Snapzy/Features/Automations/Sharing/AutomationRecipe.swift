//
//  AutomationRecipe.swift
//  Snapzy
//
//  Milestone 6: sharing automations as `.snapzyautomation` files.
//
//    { "format": "snapzy-automation", "version": 1, "exportedBy": "Snapzy 2.x",
//      "automations": [ …Automation JSON… ] }
//
//  Export strips what belongs to this Mac or this user's trust decisions:
//  keyboard shortcuts, folder bookmarks (the path stays as a hint), the
//  external-invocation opt-ins and the review flag. Secret values never live
//  in an automation (steps hold `{secret:NAME}` references), so none leak.
//  Import gives everything new ids, re-points Run Automation / Ask between
//  the file's own automations, flags webhook / script / AI steps for review
//  and leaves anything that still needs setup (a folder, an uploader) off.
//

import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

enum AutomationRecipeError: LocalizedError, Equatable {
  case notARecipe
  case unsupportedVersion(Int)
  case empty
  case tooLarge
  case insecureURL
  case download(String)

  var errorDescription: String? {
    switch self {
    case .notARecipe: L10n.Automations.recipeErrorNotARecipe
    case .unsupportedVersion(let version): L10n.Automations.recipeErrorVersion(version)
    case .empty: L10n.Automations.recipeErrorEmpty
    case .tooLarge: L10n.Automations.recipeErrorTooLarge
    case .insecureURL: L10n.Automations.recipeErrorInsecureURL
    case .download(let reason): reason
    }
  }
}

@MainActor
enum AutomationRecipeCodec {
  static let format = "snapzy-automation"
  static let version = 1
  static let fileExtension = "snapzyautomation"
  static let typeIdentifier = "com.trongduong.snapzy.automation"
  /// Biggest recipe accepted from a URL.
  static let maxDownloadBytes = 256 * 1024
  /// Biggest recipe file opened from disk.
  static let maxFileBytes = 1024 * 1024

  static var contentType: UTType {
    UTType(exportedAs: typeIdentifier, conformingTo: .json)
  }

  private struct File: Codable {
    var format: String
    var version: Int
    var exportedBy: String?
    var automations: [AutomationJSONValue]
  }

  // MARK: - Export

  /// The file for `automations`. `folderPath` resolves a bookmark to its path hint.
  static func encode(
    _ automations: [Automation],
    folderPath: ((AutomationFolderRef) -> String?)? = nil
  ) throws -> Data {
    let folderPath = folderPath ?? { AutomationFolderAccessStore.shared.path(for: $0) }
    let entries = try automations
      .filter { !$0.isSystemDefault }
      .map { automation -> AutomationJSONValue in
        let data = try JSONEncoder().encode(stripped(automation, folderPath: folderPath))
        return try JSONDecoder().decode(AutomationJSONValue.self, from: data)
      }
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    let file = File(format: format, version: version, exportedBy: "Snapzy \(appVersion)", automations: entries)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(file)
  }

  /// What leaves this Mac: no shortcut, no bookmark, no opt-ins.
  static func stripped(_ automation: Automation, folderPath: (AutomationFolderRef) -> String?) -> Automation {
    var copy = automation.migrated()
    copy.name = automation.displayName
    copy.presetID = nil
    copy.hotkey = nil
    copy.externalInvocation = false
    copy.allowExternalCode = false
    copy.needsReview = false
    copy.steps = copy.steps.map { step in
      guard case .saveToFolder(var config)? = step.action,
            case .bookmark = config.folder else { return step }
      // The other Mac picks its own folder; the path tells the user which one was meant.
      config.folderPath = config.folder.flatMap(folderPath) ?? config.folderPath
      config.folder = nil
      var copy = step
      copy.content = .action(.saveToFolder(config))
      return copy
    }
    return copy
  }

  // MARK: - Import

  /// Decodes a recipe file. Entries this build can't read are skipped.
  static func decode(_ data: Data) throws -> [Automation] {
    guard let file = try? JSONDecoder().decode(File.self, from: data), file.format == format else {
      throw AutomationRecipeError.notARecipe
    }
    guard file.version <= version else { throw AutomationRecipeError.unsupportedVersion(file.version) }
    let automations = file.automations.compactMap { entry -> Automation? in
      guard let data = try? JSONEncoder().encode(entry) else { return nil }
      return try? JSONDecoder().decode(Automation.self, from: data)
    }
    guard !automations.isEmpty else { throw AutomationRecipeError.empty }
    return automations
  }

  /// Fresh ids (automations and steps), references between the file's own
  /// automations re-pointed, no system defaults, review flag set by the M4 rule.
  static func prepareForImport(_ automations: [Automation]) -> [Automation] {
    let candidates = automations.filter { !$0.isSystemDefault }
    var idMap: [UUID: UUID] = [:]
    for automation in candidates { idMap[automation.id] = UUID() }

    return candidates.map { original in
      var copy = original.migrated()
      copy.id = idMap[original.id] ?? UUID()
      copy.presetID = nil
      copy.hotkey = nil
      copy.externalInvocation = false
      copy.allowExternalCode = false
      copy.steps = copy.steps.map { step in
        var step = step
        step.id = UUID()
        if let action = step.action {
          step.content = .action(remapped(action, idMap))
        }
        return step
      }
      return copy.normalized().flaggedForReview(comparedTo: nil)
    }
  }

  private static func remapped(_ action: AutomationStepAction, _ idMap: [UUID: UUID]) -> AutomationStepAction {
    switch action {
    case .runAutomation(var config):
      config.automationID = config.automationID.map { idMap[$0] ?? $0 }
      return .runAutomation(config)
    case .ask(var config):
      config.choices = config.choices.map { choice in
        guard case .automation(let id) = choice else { return choice }
        return .automation(idMap[id] ?? id)
      }
      return .ask(config)
    default:
      return action
    }
  }

  // MARK: - URL

  /// `https` only, at most `maxDownloadBytes`.
  static func download(_ url: URL, session: URLSession = .shared) async throws -> Data {
    guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
      throw AutomationRecipeError.insecureURL
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (bytes, response) = try await session.bytes(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw AutomationRecipeError.download(L10n.Automations.errorHTTPStatus(http.statusCode))
    }
    // Redirects must stay on https too.
    guard response.url?.scheme?.lowercased() == "https" else { throw AutomationRecipeError.insecureURL }
    if response.expectedContentLength > Int64(maxDownloadBytes) { throw AutomationRecipeError.tooLarge }
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      if data.count > maxDownloadBytes { throw AutomationRecipeError.tooLarge }
    }
    return data
  }
}

// MARK: - Import review

/// One automation offered in the import sheet.
struct AutomationImportCandidate: Identifiable, Equatable {
  var automation: Automation
  var isSelected = true

  var id: UUID { automation.id }
}

/// Where an import came from; URL imports never arrive enabled.
enum AutomationImportOrigin: Equatable {
  case file(String)
  case url(String)
  case gallery

  var label: String {
    switch self {
    case .file(let name): name
    case .url(let host): host
    case .gallery: L10n.Automations.galleryTitle
    }
  }
}

struct AutomationImportRequest: Identifiable, Equatable {
  let id = UUID()
  let origin: AutomationImportOrigin
  var candidates: [AutomationImportCandidate]
}

/// Receives recipe files / URLs from anywhere in the app and hands them to
/// Settings → Automations, which shows the import sheet.
@MainActor
final class AutomationImportCoordinator: ObservableObject {
  static let shared = AutomationImportCoordinator()

  @Published var pending: AutomationImportRequest?
  @Published var lastError: String?

  /// Opens Settings → Automations on an import of `data`.
  func present(_ data: Data, origin: AutomationImportOrigin) {
    do {
      var automations = AutomationRecipeCodec.prepareForImport(try AutomationRecipeCodec.decode(data))
      if case .url = origin {
        // Something on the web sent this: it waits for the user to turn it on.
        automations = automations.map { var copy = $0; copy.isEnabled = false; return copy }
      }
      pending = AutomationImportRequest(origin: origin, candidates: automations.map { AutomationImportCandidate(automation: $0) })
      lastError = nil
      DiagnosticLogger.shared.log(.info, .action, "Automation recipe opened", context: ["count": "\(automations.count)"])
    } catch {
      pending = nil
      lastError = error.localizedDescription
      AppToastManager.shared.show(message: error.localizedDescription, style: .warning)
      DiagnosticLogger.shared.logError(.action, error, "Automation recipe rejected")
    }
    AppStatusBarController.shared.openPreferencesWindow(tab: .automations)
    AutomationSettingsNavigation.shared.page = .automations
  }

  func open(fileURL: URL) {
    let access = fileURL.startAccessingSecurityScopedResource()
    defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
    do {
      let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      guard size <= AutomationRecipeCodec.maxFileBytes else { throw AutomationRecipeError.tooLarge }
      let data = try Data(contentsOf: fileURL)
      present(data, origin: .file(fileURL.lastPathComponent))
    } catch {
      AppToastManager.shared.show(message: error.localizedDescription, style: .warning)
    }
  }

  func open(remoteURL: URL) {
    // Any web page can open this link: nothing is fetched until the user agrees.
    let host = remoteURL.host ?? remoteURL.absoluteString
    let alert = NSAlert()
    alert.messageText = L10n.Automations.importURLConfirmTitle(host)
    alert.informativeText = L10n.Automations.importURLConfirmMessage
    alert.addButton(withTitle: L10n.Automations.importURLConfirmButton)
    alert.addButton(withTitle: L10n.Common.cancel)
    NSApp.activate(ignoringOtherApps: true)
    guard alert.runModal() == .alertFirstButtonReturn else {
      DiagnosticLogger.shared.log(.info, .action, "Automation recipe download declined")
      return
    }
    Task { @MainActor in
      do {
        let data = try await AutomationRecipeCodec.download(remoteURL)
        present(data, origin: .url(remoteURL.host ?? remoteURL.absoluteString))
      } catch {
        AppToastManager.shared.show(message: error.localizedDescription, style: .warning)
        DiagnosticLogger.shared.logError(.action, error, "Automation recipe download failed")
      }
    }
  }

  /// Adds the selected candidates (up to the cap). Returns how many were added.
  @discardableResult
  func importSelected(_ request: AutomationImportRequest, into store: AutomationStore = .shared) -> Int {
    var added = 0
    for candidate in request.candidates where candidate.isSelected {
      var automation = candidate.automation
      // Missing folders / uploaders: added off, with "Needs setup".
      if automation.needsSetup { automation.isEnabled = false }
      guard store.add(automation) else { break }
      added += 1
    }
    pending = nil
    DiagnosticLogger.shared.log(.info, .action, "Automation recipe imported", context: ["count": "\(added)"])
    return added
  }

  static func isRecipeFile(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == AutomationRecipeCodec.fileExtension
  }
}
