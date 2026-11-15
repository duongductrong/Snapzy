//
//  PreferencesTranslateSettingsSection.swift
//  Snapzy
//
//  Snip to Translate settings, shown in Capture → OCR below the OCR model list
//  (custom endpoints are shared with OCR).
//

import SwiftUI

struct PreferencesTranslateSettingsSection: View {
  @AppStorage(PreferencesKeys.translateTargetLanguage) private var targetLanguage = ""
  @AppStorage(PreferencesKeys.translateSelectedEngine)
  private var selectedEngine = TranslationEngineSelection.builtIn.persistedValue
  @ObservedObject private var store = CustomOCRModelStore.shared

  private static let builtInTag = TranslationEngineSelection.builtIn.persistedValue

  var body: some View {
    Section(L10n.Translate.settingsSection) {
      SettingRow(
        title: L10n.Translate.targetLanguageLabel,
        description: L10n.Translate.settingsTargetDescription
      ) {
        Picker("", selection: $targetLanguage) {
          Text(L10n.Translate.settingsTargetAsk).tag("")
          Divider()
          ForEach(TranslationLanguage.all) { language in
            Text(language.displayName).tag(language.identifier)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }

      SettingRow(
        title: L10n.Translate.settingsEngineTitle,
        description: L10n.Translate.settingsEngineDescription
      ) {
        Picker("", selection: engineBinding) {
          Text(TranslationEngineResolver.systemSupportsAppleTranslation
            ? L10n.Translate.settingsEngineApple
            : L10n.Translate.settingsEngineAppleUnavailable)
            .tag(Self.builtInTag)
          if !store.models.isEmpty {
            Divider()
            ForEach(store.models) { model in
              Text(model.name).tag(TranslationEngineSelection.custom(model.id).persistedValue)
            }
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }

      if let hint = engineHint {
        Label {
          Text(hint)
            .font(.callout)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "info.circle")
            .foregroundColor(.secondary)
        }
      }
    }
  }

  /// A stored endpoint that was removed reads as Apple Translation.
  private var engineBinding: Binding<String> {
    Binding(
      get: {
        let selection = TranslationEngineSelection(persistedValue: selectedEngine)
        if case .custom(let id) = selection, store.model(for: id) == nil {
          return Self.builtInTag
        }
        return selection.persistedValue
      },
      set: { selectedEngine = $0 }
    )
  }

  private var engineHint: String? {
    if engineBinding.wrappedValue == Self.builtInTag {
      guard !TranslationEngineResolver.systemSupportsAppleTranslation else { return nil }
      return store.models.isEmpty
        ? L10n.Translate.requiresMacOS15MessageNoEndpoint
        : L10n.Translate.requiresMacOS15MessageWithEndpoint
    }
    return L10n.Translate.useEndpointCaption
  }
}
