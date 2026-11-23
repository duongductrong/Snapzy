//
//  AutomationStore.swift
//  Snapzy
//
//  Persists automations as JSON in UserDefaults and seeds the built-in presets
//  once. Changes publish through `$automations`, which re-registers hotkeys.
//

import Combine
import Foundation

@MainActor
final class AutomationStore: ObservableObject {
  static let shared = AutomationStore()
  static let maxAutomations = 20

  @Published private(set) var automations: [Automation] = []

  private let defaults: UserDefaults
  /// Stored entries this build cannot decode. Kept and written back so one bad
  /// or newer entry never erases the others or itself.
  private var undecodableEntries: [AutomationJSONValue] = []

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let loaded = Self.load(from: defaults)
    automations = loaded.automations
    undecodableEntries = loaded.undecodable
    seedPresetsIfNeeded()
  }

  // MARK: - Queries

  func automation(id: UUID) -> Automation? {
    automations.first { $0.id == id }
  }

  /// Finds an automation by id, or by name (trimmed, case-insensitive, matching
  /// the stored or the displayed name). Several matches → `.ambiguousName`.
  func resolve(_ ref: AutomationRef) -> Result<Automation, AutomationLaunchRejection> {
    switch ref {
    case .id(let id):
      return automation(id: id).map { .success($0) } ?? .failure(.notFound)
    case .name(let raw):
      let wanted = Self.nameKey(raw)
      guard !wanted.isEmpty else { return .failure(.notFound) }
      let matches = automations.filter {
        Self.nameKey($0.name) == wanted || Self.nameKey($0.displayName) == wanted
      }
      switch matches.count {
      case 0: return .failure(.notFound)
      case 1: return .success(matches[0])
      default: return .failure(.ambiguousName(matches.map(\.id)))
      }
    }
  }

  /// Ids of other automations that share `automation`'s name (shown as a warning in the editor).
  func duplicateNameIDs(for automation: Automation) -> [UUID] {
    let key = Self.nameKey(automation.displayName)
    guard !key.isEmpty else { return [] }
    return automations
      .filter { $0.id != automation.id && Self.nameKey($0.displayName) == key }
      .map(\.id)
  }

  /// Enabled automations offered by `slot`. With `fileKind`, only those that
  /// have at least one enabled step accepting that kind of file.
  func automations(for slot: AutomationTriggerSlot, fileKind: AutomationFileKind? = nil) -> [Automation] {
    automations.filter { automation in
      guard automation.isEnabled, !automation.hasUnsupportedSource else { return false }
      switch slot {
      case .menuBar:
        guard automation.showsInMenuBar, automation.startsCapture else { return false }
      case .quickAccess:
        guard automation.showsInQuickAccess else { return false }
      case .history:
        guard automation.showsInHistory else { return false }
      case .external:
        guard automation.externalInvocation else { return false }
      }
      guard let fileKind else { return true }
      return automation.acceptsFile(of: fileKind)
    }
  }

  private static func nameKey(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  var canAdd: Bool {
    automations.count < Self.maxAutomations
  }

  var missingPresets: [AutomationPreset] {
    let present = Set(automations.compactMap(\.presetID))
    return AutomationPreset.allCases.filter { !present.contains($0.rawValue) }
  }

  // MARK: - Mutations

  @discardableResult
  func add(_ automation: Automation) -> Bool {
    guard canAdd else { return false }
    automations.append(automation.normalized())
    persist()
    return true
  }

  func update(_ automation: Automation) {
    guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
    let normalized = automation.normalized()
    guard automations[index] != normalized else { return }
    automations[index] = normalized
    persist()
  }

  @discardableResult
  func duplicate(id: UUID) -> Automation? {
    guard canAdd, let original = automation(id: id) else { return nil }
    var copy = original
    copy.id = UUID()
    copy.name = L10n.Automations.copyName(original.displayName)
    copy.presetID = nil
    copy.hotkey = nil
    copy.steps = copy.steps.map { step in
      var step = step
      step.id = UUID()
      return step
    }
    let normalized = copy.normalized()
    if let index = automations.firstIndex(where: { $0.id == id }) {
      automations.insert(normalized, at: index + 1)
    } else {
      automations.append(normalized)
    }
    persist()
    return normalized
  }

  func delete(id: UUID) {
    automations.removeAll { $0.id == id }
    persist()
  }

  func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    var reordered = automations
    let moving = source.sorted().map { reordered[$0] }
    for index in source.sorted(by: >) {
      reordered.remove(at: index)
    }
    let insertAt = destination - source.filter { $0 < destination }.count
    reordered.insert(contentsOf: moving, at: max(0, min(insertAt, reordered.count)))
    automations = reordered
    persist()
  }

  func setEnabled(_ enabled: Bool, id: UUID) {
    guard var automation = automation(id: id) else { return }
    automation.isEnabled = enabled
    update(automation)
  }

  func setHotkey(_ config: ShortcutConfig?, id: UUID) {
    guard var automation = automation(id: id) else { return }
    automation.hotkey = config
    update(automation)
  }

  func restoreMissingPresets() {
    let missing = missingPresets
    guard !missing.isEmpty else { return }
    for preset in missing where canAdd {
      automations.append(preset.makeAutomation())
    }
    persist()
  }

  /// Replace everything (configuration import). Keeps the cap and normalizes.
  func replaceAll(_ newAutomations: [Automation]) {
    automations = Array(newAutomations.prefix(Self.maxAutomations)).map { $0.normalized() }
    defaults.set(true, forKey: PreferencesKeys.automationsSeeded)
    persist()
  }

  // MARK: - Persistence

  private func seedPresetsIfNeeded() {
    guard !defaults.bool(forKey: PreferencesKeys.automationsSeeded) else { return }
    defaults.set(true, forKey: PreferencesKeys.automationsSeeded)
    if automations.isEmpty, undecodableEntries.isEmpty {
      automations = AutomationPreset.allCases.map { $0.makeAutomation() }
      persist()
    }
  }

  private func persist() {
    do {
      let encoded = try automations.map { automation -> AutomationJSONValue in
        let data = try JSONEncoder().encode(automation)
        return try JSONDecoder().decode(AutomationJSONValue.self, from: data)
      }
      let data = try JSONEncoder().encode(encoded + undecodableEntries)
      defaults.set(data, forKey: PreferencesKeys.automations)
    } catch {
      DiagnosticLogger.shared.logError(.action, error, "Automations save failed")
    }
  }

  private static func load(from defaults: UserDefaults) -> (automations: [Automation], undecodable: [AutomationJSONValue]) {
    guard let data = defaults.data(forKey: PreferencesKeys.automations) else { return ([], []) }
    let entries: [AutomationJSONValue]
    do {
      entries = try JSONDecoder().decode([AutomationJSONValue].self, from: data)
    } catch {
      DiagnosticLogger.shared.logError(.action, error, "Automations load failed")
      return ([], [])
    }

    var automations: [Automation] = []
    var undecodable: [AutomationJSONValue] = []
    for entry in entries {
      do {
        let entryData = try JSONEncoder().encode(entry)
        automations.append(try JSONDecoder().decode(Automation.self, from: entryData))
      } catch {
        undecodable.append(entry)
        DiagnosticLogger.shared.logError(.action, error, "Automation entry kept undecoded")
      }
    }
    return (automations, undecodable)
  }
}
