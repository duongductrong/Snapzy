//
//  AutomationAppIntents.swift
//  Snapzy
//
//  Apple Shortcuts / Spotlight / Siri: "Run Snapzy Automation". Lists only
//  automations that allow other apps, and runs in-process through the launcher.
//

import AppIntents
import Foundation

nonisolated struct AutomationEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("automations.intent.entity-type", defaultValue: "Snapzy Automation", table: "Automations")
  )
  static var defaultQuery: AutomationEntityQuery { AutomationEntityQuery() }

  let id: UUID
  let name: String
  let symbol: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
  }
}

nonisolated struct AutomationEntityQuery: EntityStringQuery {
  func entities(for identifiers: [UUID]) async throws -> [AutomationEntity] {
    await AutomationIntentSupport.entities().filter { identifiers.contains($0.id) }
  }

  func suggestedEntities() async throws -> [AutomationEntity] {
    await AutomationIntentSupport.entities()
  }

  func entities(matching string: String) async throws -> [AutomationEntity] {
    let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
    let all = await AutomationIntentSupport.entities()
    guard !query.isEmpty else { return all }
    return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }
}

nonisolated struct RunAutomationIntent: AppIntent {
  static let title = LocalizedStringResource(
    "automations.intent.run-title",
    defaultValue: "Run Snapzy Automation",
    table: "Automations"
  )
  static let description = IntentDescription(
    LocalizedStringResource(
      "automations.intent.run-description",
      defaultValue: "Runs a Snapzy automation: captures the screen, or uses the files you pass in, then runs its steps. Returns the uploaded link or the file path.",
      table: "Automations"
    )
  )
  static let openAppWhenRun = false

  @Parameter(title: LocalizedStringResource("automations.intent.parameter-automation", defaultValue: "Automation", table: "Automations"))
  var automation: AutomationEntity

  @Parameter(
    title: LocalizedStringResource("automations.intent.parameter-files", defaultValue: "Files", table: "Automations"),
    supportedTypeIdentifiers: ["public.image", "public.movie", "com.compuserve.gif"],
    inputConnectionBehavior: .connectToPreviousIntentResult
  )
  var files: [IntentFile]?

  static var parameterSummary: some ParameterSummary {
    Summary("Run \(\.$automation)") {
      \.$files
    }
  }

  init() {}

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let staged = try AutomationIntentSupport.stage(files ?? [])
    let outcome = await AutomationIntentSupport.launch(automationID: automation.id, files: staged)
    if case .finished = outcome {} else {
      AutomationIntentSupport.removeStaged(staged)
    }
    switch outcome {
    case .finished(let report):
      let value = AutomationIntentSupport.resultValue(for: report)
      return .result(value: value, dialog: IntentDialog(stringLiteral: report.message))
    case .cancelled:
      throw AutomationIntentError(message: AutomationIntentSupport.cancelledMessage)
    case .rejected(let rejection):
      throw AutomationIntentError(message: await rejection.localizedMessage)
    }
  }
}

nonisolated struct AutomationIntentError: Error, CustomLocalizedStringResourceConvertible {
  let message: String

  var localizedStringResource: LocalizedStringResource {
    LocalizedStringResource(stringLiteral: message)
  }
}

nonisolated struct SnapzyAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: RunAutomationIntent(),
      phrases: [
        "Run \(.applicationName) automation",
        "Run \(\.$automation) with \(.applicationName)",
      ]
    )
  }
}

/// Intent logic behind a seam so it can be unit tested without App Intents.
enum AutomationIntentSupport {
  /// Re-reads the parameterized phrases ("Run <automation> with Snapzy").
  static func refreshAppShortcuts() {
    SnapzyAppShortcuts.updateAppShortcutParameters()
  }

  @MainActor
  static func entities(store: AutomationStore = .shared) -> [AutomationEntity] {
    store.automations(for: .external).map { automation in
      AutomationEntity(
        id: automation.id,
        name: automation.displayName,
        symbol: automation.symbol ?? automation.captureSpec?.mode.symbol ?? AutomationDisplay.inputSymbol
      )
    }
  }

  @MainActor
  static func launch(
    automationID: UUID,
    files: [URL],
    launcher: AutomationLauncher = .shared
  ) async -> AutomationLaunchOutcome {
    let input = files.isEmpty ? nil : AutomationInput(files: files, isAlreadyInHistory: false)
    return await launcher.launch(.id(automationID), invocation: .appIntent, input: input)
  }

  /// The link when a step produced one, else the first file path.
  nonisolated static func resultValue(for report: AutomationRunReport) -> String {
    report.link ?? report.text ?? report.outputFiles.first?.path ?? ""
  }

  nonisolated static var cancelledMessage: String {
    L10n.Automations.intentCancelled
  }

  /// Copies the files Shortcuts hands in to Snapzy's temporary capture folder
  /// (Shortcuts' copies are short-lived), where the usual temp-capture cleanup
  /// removes them unless History keeps them.
  nonisolated static func stage(_ files: [IntentFile]) throws -> [URL] {
    guard !files.isEmpty else { return [] }
    let directory = TempCaptureManager.tempCaptureRootDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var staged: [URL] = []
    do {
      for (index, file) in files.enumerated() {
        staged.append(try stage(file, index: index, in: directory))
      }
    } catch {
      removeStaged(staged)
      throw error
    }
    return staged
  }

  /// Removes copies made by `stage` for a run that never used them.
  nonisolated static func removeStaged(_ urls: [URL]) {
    urls.forEach { try? FileManager.default.removeItem(at: $0) }
  }

  private nonisolated static func stage(_ file: IntentFile, index: Int, in directory: URL) throws -> URL {
    let original = (file.filename as NSString).lastPathComponent
    let destination = uniqueURL(in: directory, name: original.isEmpty ? "Snapzy_input_\(index)" : original)
    if let source = file.fileURL {
      let didAccess = source.startAccessingSecurityScopedResource()
      defer { if didAccess { source.stopAccessingSecurityScopedResource() } }
      try FileManager.default.copyItem(at: source, to: destination)
    } else {
      try file.data.write(to: destination)
    }
    return destination
  }

  nonisolated static func uniqueURL(in directory: URL, name: String) -> URL {
    let base = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var candidate = directory.appendingPathComponent(name)
    var counter = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      let numbered = "\(base) \(counter)"
      candidate = directory.appendingPathComponent(ext.isEmpty ? numbered : "\(numbered).\(ext)")
      counter += 1
    }
    return candidate
  }
}
