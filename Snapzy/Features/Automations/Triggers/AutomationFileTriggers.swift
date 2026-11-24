//
//  AutomationFileTriggers.swift
//  Snapzy
//
//  Files handed to Snapzy from outside a capture (milestone 5): Finder's
//  "Run Snapzy Automation…" service (Quick Actions / Services menu) and files
//  dropped on the menu bar icon. Both list the automations with "Show in
//  Finder & menu bar drop" that accept every file, in the picker HUD, then
//  run the choice on all the files.
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum AutomationFileTriggers {
  /// Supported files (image, video, GIF) among `urls`, in order, without duplicates.
  nonisolated static func supportedFiles(_ urls: [URL]) -> [URL] {
    var seen = Set<String>()
    return urls.filter { url in
      url.isFileURL && AutomationFileKind.of(url) != nil && seen.insert(url.standardizedFileURL.path).inserted
    }
  }

  /// File URLs on a Services / drag pasteboard.
  nonisolated static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] ?? []
    return supportedFiles(urls)
  }

  /// Automations offered for `files`: shown in Finder, and every file kind accepted.
  static func eligibleAutomations(for files: [URL], store: AutomationStore = .shared) -> [Automation] {
    let kinds = Set(files.compactMap(AutomationFileKind.of))
    guard !kinds.isEmpty else { return [] }
    return store.automations(for: .finder).filter { automation in
      kinds.allSatisfy(automation.acceptsFile(of:))
    }
  }

  /// Picker → launch. Rejections and "nothing to run" end as a toast.
  static func run(files rawFiles: [URL], invocation: AutomationInvocation) {
    let files = supportedFiles(rawFiles)
    guard !files.isEmpty else {
      AppToastManager.shared.show(message: L10n.Automations.fileTriggerNoSupportedFiles, style: .warning)
      return
    }
    let automations = eligibleAutomations(for: files)
    guard !automations.isEmpty else {
      AppToastManager.shared.show(message: L10n.Automations.fileTriggerNoAutomations, style: .warning)
      return
    }
    DiagnosticLogger.shared.log(
      .info,
      .action,
      "Automation file trigger",
      context: ["invocation": invocation.rawValue, "files": "\(files.count)", "eligible": "\(automations.count)"]
    )

    Task { @MainActor in
      // Sandbox: the drop / service grants access to these files; hold it for the run.
      let access = files.map { SandboxFileAccessManager.shared.beginAccessingURL($0) }
      defer { access.forEach { $0.stop() } }

      let automationID: UUID
      let runDirectly = UserDefaults.standard.bool(forKey: PreferencesKeys.automationsRunSingleFileTriggerDirectly)
      // Direct runs have no UI, so they never reach script steps (any app can call a Service).
      if automations.count == 1, runDirectly, let only = automations.first,
         only.effectiveMaxTrust(lookup: { AutomationStore.shared.automation(id: $0) }) != .code
      {
        automationID = only.id
      } else {
        let choices = automations.map {
          AutomationPickerChoice(value: .automation($0.id), title: $0.displayName, symbol: $0.symbol ?? $0.sourceSymbol)
        }
        let title = files.count == 1
          ? files[0].lastPathComponent
          : L10n.Automations.fileTriggerTitle(files.count)
        let thumbnail = files.first { AutomationFileKind.of($0) == .image }
        guard let picked = await AutomationPickerHUD.shared.present(title: title, thumbnail: thumbnail, choices: choices),
              case .automation(let id) = picked.value
        else { return }
        automationID = id
      }

      let input = AutomationInput(files: files, isAlreadyInHistory: false)
      let outcome = await AutomationLauncher.shared.launch(.id(automationID), invocation: invocation, input: input)
      if case .rejected(let rejection) = outcome {
        AppToastManager.shared.show(message: rejection.localizedMessage, style: .warning)
      }
    }
  }
}

// MARK: - Finder service

/// `NSApp.servicesProvider`: receives Finder's "Run Snapzy Automation…" (see
/// `NSServices` in Info.plist; `NSMessage = runAutomationService`).
@MainActor
final class AutomationServicesProvider: NSObject {
  static let shared = AutomationServicesProvider()

  /// Installs the provider and refreshes the Services menu once per app version
  /// (the system caches Services; an update may add or rename the entry).
  func install(defaults: UserDefaults = .standard) {
    NSApp.servicesProvider = self
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    if defaults.string(forKey: PreferencesKeys.automationsServicesRegisteredVersion) != version {
      NSUpdateDynamicServices()
      defaults.set(version, forKey: PreferencesKeys.automationsServicesRegisteredVersion)
    }
  }

  @objc func runAutomationService(
    _ pasteboard: NSPasteboard,
    userData _: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    let files = AutomationFileTriggers.fileURLs(from: pasteboard)
    guard !files.isEmpty else {
      error.pointee = L10n.Automations.fileTriggerNoSupportedFiles as NSString
      return
    }
    AutomationFileTriggers.run(files: files, invocation: .finder)
  }
}

// MARK: - Menu bar drop

/// Drop target for the status item's window: highlights the icon while
/// supported files hover and hands the drop to `AutomationFileTriggers`.
@MainActor
final class AutomationStatusItemDropTarget: NSObject, NSWindowDelegate, NSDraggingDestination {
  private weak var button: NSStatusBarButton?

  /// Registers `button`'s window for file drops. Safe to call again for a new status item.
  func attach(to button: NSStatusBarButton) {
    self.button = button
    guard let window = button.window else { return }
    window.registerForDraggedTypes([.fileURL])
    if window.delegate == nil || window.delegate === self {
      window.delegate = self
    }
  }

  private func files(in sender: NSDraggingInfo) -> [URL] {
    AutomationFileTriggers.fileURLs(from: sender.draggingPasteboard)
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard !files(in: sender).isEmpty else { return [] }
    button?.highlight(true)
    return .copy
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    files(in: sender).isEmpty ? [] : .copy
  }

  func draggingExited(_: NSDraggingInfo?) {
    button?.highlight(false)
  }

  func draggingEnded(_: NSDraggingInfo) {
    button?.highlight(false)
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    button?.highlight(false)
    let files = files(in: sender)
    guard !files.isEmpty else { return false }
    AutomationFileTriggers.run(files: files, invocation: .menuBarDrop)
    return true
  }
}
