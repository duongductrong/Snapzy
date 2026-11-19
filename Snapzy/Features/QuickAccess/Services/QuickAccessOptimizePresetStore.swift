//
//  QuickAccessOptimizePresetStore.swift
//  Snapzy
//
//  Saved Optimize presets (shown in the Quick Access Optimize menu and edited in
//  Preferences) and the last settings used in the "Custom…" editor.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class QuickAccessOptimizePresetStore: ObservableObject {
  static let shared = QuickAccessOptimizePresetStore()

  static let maxNameLength = 40

  @Published private(set) var presets: [QuickAccessOptimizePreset]
  @Published private(set) var lastCustomSettings: QuickAccessOptimizeSettings

  private let defaults: UserDefaults

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: PreferencesKeys.quickAccessOptimizePresets),
       let saved = try? JSONDecoder().decode([QuickAccessOptimizePreset].self, from: data) {
      presets = saved
    } else {
      presets = Self.starterPresets()
    }
    if let data = defaults.data(forKey: PreferencesKeys.quickAccessOptimizeLastCustom),
       let saved = try? JSONDecoder().decode(QuickAccessOptimizeSettings.self, from: data) {
      lastCustomSettings = saved.clamped
    } else {
      lastCustomSettings = .default
    }
  }

  /// Two examples so the feature is discoverable; users can edit or delete them.
  static func starterPresets() -> [QuickAccessOptimizePreset] {
    [
      QuickAccessOptimizePreset(
        name: L10n.QuickAccess.optimizePresetStarterChat,
        settings: QuickAccessOptimizeSettings(scalePercent: 50, format: .webp, qualityPercent: 80, maxFileSize: nil)
      ),
      QuickAccessOptimizePreset(
        name: L10n.QuickAccess.optimizePresetStarterUnderOneMB,
        settings: QuickAccessOptimizeSettings(scalePercent: 100, format: .original, qualityPercent: 85, maxFileSize: 1_000_000)
      ),
    ]
  }

  // MARK: - Presets

  @discardableResult
  func addPreset(name: String, settings: QuickAccessOptimizeSettings) -> QuickAccessOptimizePreset {
    let preset = QuickAccessOptimizePreset(name: Self.cleanName(name), settings: settings.clamped)
    presets.append(preset)
    persistPresets()
    return preset
  }

  func updatePreset(_ preset: QuickAccessOptimizePreset) {
    guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
    var cleaned = preset
    cleaned.name = Self.cleanName(preset.name)
    cleaned.settings = preset.settings.clamped
    presets[index] = cleaned
    persistPresets()
  }

  func deletePreset(id: UUID) {
    presets.removeAll { $0.id == id }
    persistPresets()
  }

  func movePresets(fromOffsets source: IndexSet, toOffset destination: Int) {
    presets.move(fromOffsets: source, toOffset: destination)
    persistPresets()
  }

  func setLastCustomSettings(_ settings: QuickAccessOptimizeSettings) {
    let clamped = settings.clamped
    guard clamped != lastCustomSettings else { return }
    lastCustomSettings = clamped
    if let data = try? JSONEncoder().encode(clamped) {
      defaults.set(data, forKey: PreferencesKeys.quickAccessOptimizeLastCustom)
    }
  }

  /// Trimmed, length-capped, never empty.
  static func cleanName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let capped = String(trimmed.prefix(maxNameLength))
    return capped.isEmpty ? L10n.QuickAccess.optimizePresetUntitled : capped
  }

  private func persistPresets() {
    guard let data = try? JSONEncoder().encode(presets) else { return }
    defaults.set(data, forKey: PreferencesKeys.quickAccessOptimizePresets)
  }
}
