//
//  AutomationStore.swift
//  Snapzy
//
//  Persists automations as JSON in UserDefaults and seeds the built-in presets
//  once. Changes publish through `$automations`, which re-registers hotkeys.
//
//  Milestone 6: the two default after-capture automations live apart in
//  `systemAutomations` (own key, outside the 20-item cap and the user list).
//  They are built from the after-capture matrix on first launch and are the
//  source of truth since; every change is mirrored back to the legacy matrix
//  (`onSystemDefaultChanged`) for readers of it and for a downgrade.
//

import Combine
import Foundation

@MainActor
final class AutomationStore: ObservableObject {
  static let maxAutomations = 20

  @Published private(set) var automations: [Automation] = []
  /// "Default after screenshot" / "Default after recording" (milestone 6).
  @Published private(set) var systemAutomations: [Automation] = []

  /// Mirrors a default automation into the legacy after-capture matrix.
  var onSystemDefaultChanged: ((CaptureType, [AfterCaptureAction: Bool]) -> Void)?

  private let defaults: UserDefaults
  /// Stored entries this build cannot decode. Kept and written back so one bad
  /// or newer entry never erases the others or itself.
  private var undecodableEntries: [AutomationJSONValue] = []

  /// `matrix` reads the stored after-capture matrix; it seeds the default
  /// automations the first time this build runs.
  init(
    defaults: UserDefaults = .standard,
    matrix: ((CaptureType) -> [AfterCaptureAction: Bool])? = nil
  ) {
    self.defaults = defaults
    let loaded = Self.load(from: defaults)
    automations = loaded.automations
    undecodableEntries = loaded.undecodable
    seedPresetsIfNeeded()
    loadSystemDefaults(matrix: matrix ?? AutomationSystemDefault.defaultMatrix(for:))
  }

  /// The shared store owns the after-capture matrix: matrix setters write the
  /// default automations, which mirror back into `PreferencesManager`.
  static let shared: AutomationStore = {
    let preferences = PreferencesManager.shared
    let store = AutomationStore(defaults: .standard, matrix: { preferences.storedMatrix(for: $0) })
    store.onSystemDefaultChanged = { type, matrix in
      preferences.adoptDefaultAutomationMatrix(matrix, for: type)
    }
    preferences.defaultAutomationWriter = { [weak store] action, type, enabled in
      store?.setDefaultMatrixAction(action, for: type, enabled: enabled)
    }
    // The automations are the source of truth: the matrix follows them.
    for type in CaptureType.allCases {
      preferences.adoptDefaultAutomationMatrix(store.defaultMatrix(for: type), for: type)
    }
    return store
  }()

  // MARK: - Queries

  func automation(id: UUID) -> Automation? {
    automations.first { $0.id == id } ?? systemAutomations.first { $0.id == id }
  }

  // MARK: - Default after-capture automations

  /// The automation a standard capture of `type` runs.
  func defaultAutomation(for type: CaptureType) -> Automation {
    systemAutomations.first { $0.systemCaptureType == type }
      ?? AutomationSystemDefault.make(for: type, matrix: AutomationSystemDefault.defaultMatrix(for: type))
  }

  /// Best-effort matrix of the default automation (custom pipelines included).
  func defaultMatrix(for type: CaptureType) -> [AfterCaptureAction: Bool] {
    AutomationSystemDefault.lenientMatrix(defaultAutomation(for: type), type: type)
  }

  /// One matrix cell changed (After Capture settings, config import).
  func setDefaultMatrixAction(_ action: AfterCaptureAction, for type: CaptureType, enabled: Bool) {
    let current = defaultAutomation(for: type)
    updateSystemDefault(AutomationSystemDefault.setting(action, to: enabled, in: current, type: type))
  }

  /// Rebuilds a custom default pipeline as the simple form its steps come closest to.
  func resetDefaultAutomation(for type: CaptureType) {
    let current = defaultAutomation(for: type)
    let matrix = AutomationSystemDefault.lenientMatrix(current, type: type)
    var simple = AutomationSystemDefault.make(for: type, matrix: matrix, reusing: current)
    simple.name = AutomationSystemDefault.storedName(for: type)
    updateSystemDefault(simple)
  }

  /// Replaces a default automation (editor save, config import). Keeps its id,
  /// preset id and stored name so it stays the default for `type`.
  private func updateSystemDefault(_ automation: Automation) {
    guard let type = automation.systemCaptureType else { return }
    var normalized = automation
    normalized.id = AutomationSystemDefault.id(for: type)
    normalized.presetID = AutomationSystemDefault.presetID(for: type)
    normalized = normalized.normalized()
    if let index = systemAutomations.firstIndex(where: { $0.systemCaptureType == type }) {
      guard systemAutomations[index] != normalized else { return }
      systemAutomations[index] = normalized
    } else {
      systemAutomations.append(normalized)
    }
    persistSystemDefaults()
    onSystemDefaultChanged?(type, AutomationSystemDefault.lenientMatrix(normalized, type: type))
  }

  /// Replaces both defaults from a configuration file. Types it doesn't name keep theirs.
  func replaceSystemDefaults(_ imported: [Automation]) {
    for automation in imported where automation.isSystemDefault {
      updateSystemDefault(automation)
    }
  }

  private func loadSystemDefaults(matrix: (CaptureType) -> [AfterCaptureAction: Bool]) {
    var loaded: [Automation] = []
    if let data = defaults.data(forKey: PreferencesKeys.automationsSystemDefaults) {
      // Entry by entry: one unreadable default must not reset the other.
      let entries = (try? JSONDecoder().decode([AutomationJSONValue].self, from: data)) ?? []
      for entry in entries {
        do {
          let automation = try JSONDecoder().decode(Automation.self, from: JSONEncoder().encode(entry))
          if automation.isSystemDefault { loaded.append(automation) }
        } catch {
          DiagnosticLogger.shared.logError(.action, error, "Default automation entry unreadable; rebuilt from the matrix")
        }
      }
    }
    var migrated = false
    for type in CaptureType.allCases where !loaded.contains(where: { $0.systemCaptureType == type }) {
      // First launch of milestone 6 (or unreadable data): build it from the matrix.
      loaded.append(AutomationSystemDefault.make(for: type, matrix: matrix(type)))
      migrated = true
    }
    systemAutomations = CaptureType.allCases.compactMap { type in
      loaded.first { $0.systemCaptureType == type }?.normalized()
    }
    if migrated {
      persistSystemDefaults()
      DiagnosticLogger.shared.log(.info, .action, "Default after-capture automations created from the matrix")
    }
  }

  private func persistSystemDefaults() {
    do {
      defaults.set(try JSONEncoder().encode(systemAutomations), forKey: PreferencesKeys.automationsSystemDefaults)
    } catch {
      DiagnosticLogger.shared.logError(.action, error, "Default automations save failed")
    }
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
        guard automation.showsInMenuBar, automation.runsWithoutInput else { return false }
      case .quickAccess:
        guard automation.showsInQuickAccess else { return false }
      case .history:
        guard automation.showsInHistory else { return false }
      case .external:
        guard automation.externalInvocation else { return false }
      case .finder:
        guard automation.showsInFinder else { return false }
      }
      guard let fileKind else { return true }
      return automation.acceptsFile(of: fileKind)
    }
  }

  private static func nameKey(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// The stored automation seeded from `preset`, if any.
  private func presetAutomationID(_ preset: AutomationPreset) -> UUID? {
    automations.first { $0.presetID == preset.rawValue }?.id
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
    guard canAdd, !automation.isSystemDefault else { return false }
    automations.append(automation.normalized())
    persist()
    return true
  }

  func update(_ automation: Automation) {
    if automation.isSystemDefault {
      updateSystemDefault(automation)
      return
    }
    guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
    let normalized = automation.normalized()
    guard automations[index] != normalized else { return }
    automations[index] = normalized
    persist()
  }

  @discardableResult
  func duplicate(id: UUID) -> Automation? {
    guard canAdd, let original = automation(id: id), !original.isSystemDefault else { return nil }
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
    let missing = Set(missingPresets)
    guard !missing.isEmpty else { return }
    for preset in AutomationPreset.creationOrder where missing.contains(preset) && canAdd {
      automations.append(preset.makeAutomation(resolve: presetAutomationID))
    }
    persist()
  }

  /// Replace everything (configuration import). Keeps the cap and normalizes.
  func replaceAll(_ newAutomations: [Automation]) {
    replaceSystemDefaults(newAutomations)
    let user = newAutomations.filter { !$0.isSystemDefault }
    automations = Array(user.prefix(Self.maxAutomations)).map { $0.normalized() }
    defaults.set(true, forKey: PreferencesKeys.automationsSeeded)
    persist()
  }

  // MARK: - Persistence

  private func seedPresetsIfNeeded() {
    guard !defaults.bool(forKey: PreferencesKeys.automationsSeeded) else { return }
    defaults.set(true, forKey: PreferencesKeys.automationsSeeded)
    if automations.isEmpty, undecodableEntries.isEmpty {
      for preset in AutomationPreset.creationOrder {
        automations.append(preset.makeAutomation(resolve: presetAutomationID))
      }
      // Keep the catalog order in the list.
      automations.sort { lhs, rhs in
        let order = AutomationPreset.allCases.map(\.rawValue)
        return (order.firstIndex(of: lhs.presetID ?? "") ?? 0) < (order.firstIndex(of: rhs.presetID ?? "") ?? 0)
      }
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
