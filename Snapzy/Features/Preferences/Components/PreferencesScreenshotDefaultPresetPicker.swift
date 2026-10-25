//
//  PreferencesScreenshotDefaultPresetPicker.swift
//  Snapzy
//
//  Picker for the screenshot default Annotate canvas preset.
//

import SwiftUI

struct PreferencesScreenshotDefaultPresetPicker: View {
  @State private var presets: [AnnotateCanvasPreset] = []
  @State private var selectedPresetRawValue = ""

  private let presetStore = AnnotateCanvasPresetStore.shared

  var body: some View {
    SettingRow(
      title: L10n.PreferencesCapture.defaultPresetTitle,
      description: L10n.PreferencesCapture.defaultPresetDescription
    ) {
      Picker("", selection: presetSelection) {
        Text(L10n.Common.none).tag("")
        ForEach(presets) { preset in
          Text(preset.name).tag(preset.id.uuidString)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: 220, alignment: .trailing)
    }
    .onAppear(perform: reloadPresets)
    .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
      reloadPresets()
    }
  }

  private var presetSelection: Binding<String> {
    Binding(
      get: { selectedPresetRawValue },
      set: { rawValue in
        selectedPresetRawValue = rawValue
        guard rawValue.isEmpty == false else {
          presetStore.clearDefaultPresetId()
          return
        }
        guard let id = UUID(uuidString: rawValue),
              presets.contains(where: { $0.id == id }) else {
          reloadPresets()
          return
        }
        presetStore.saveDefaultPresetId(id)
      }
    )
  }

  private func reloadPresets() {
    let loadedPresets = presetStore.loadPresets()
    let selectedId = presetStore.loadDefaultPresetId(validating: loadedPresets)
    presets = loadedPresets
    selectedPresetRawValue = selectedId?.uuidString ?? ""
  }
}
