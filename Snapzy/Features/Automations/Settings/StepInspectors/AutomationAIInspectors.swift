//
//  AutomationAIInspectors.swift
//  Snapzy
//
//  Settings for the milestone 6 AI steps: Redact and AI Describe.
//

import SwiftUI

extension AutomationRedactConfig.Category {
  var displayName: String {
    switch self {
    case .emails: L10n.Automations.redactEmails
    case .phoneNumbers: L10n.Automations.redactPhoneNumbers
    case .urls: L10n.Automations.redactURLs
    case .paymentCards: L10n.Automations.redactPaymentCards
    case .credentials: L10n.Automations.redactCredentials
    case .faces: L10n.Automations.redactFaces
    case .people: L10n.Automations.redactPeople
    }
  }
}

extension AutomationRedactConfig.Style {
  var displayName: String {
    switch self {
    case .pixelate: L10n.Automations.redactStylePixelate
    case .blur: L10n.Automations.redactStyleBlur
    case .solid: L10n.Automations.redactStyleSolid
    }
  }
}

struct RedactInspector: View {
  @Binding var config: AutomationRedactConfig

  var body: some View {
    Section {
      ForEach(AutomationRedactConfig.Category.allCases) { category in
        Toggle(category.displayName, isOn: binding(for: category))
      }
    } header: {
      Text(L10n.Automations.redactCategoriesLabel)
    } footer: {
      Text(L10n.Automations.redactPrivacyNote)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    Section {
      Picker(L10n.Automations.redactStyleLabel, selection: $config.style) {
        ForEach(AutomationRedactConfig.Style.allCases) { style in
          Text(style.displayName).tag(style)
        }
      }
    }
  }

  private func binding(for category: AutomationRedactConfig.Category) -> Binding<Bool> {
    Binding(
      get: { config.categories.contains(category) },
      set: { isOn in
        var categories = config.categories.filter { $0 != category }
        if isOn { categories.append(category) }
        config = AutomationRedactConfig(categories: categories, style: config.style)
      }
    )
  }
}

struct AIAnnotateInspector: View {
  @Binding var config: AutomationAIAnnotateConfig
  private let endpoints = CustomOCRModelStore.shared.models
  private let installedCLIs = AnnotateAgentCLIDetector.shared.installed.keys.sorted { $0.rawValue < $1.rawValue }

  var body: some View {
    Section {
      TextField(L10n.Automations.aiPromptLabel, text: $config.prompt, axis: .vertical)
        .lineLimit(3...8)
      Picker(L10n.Automations.aiProviderLabel, selection: providerBinding) {
        Text(L10n.Automations.aiProviderSettings).tag(AutomationAIAnnotateConfig.Provider.settings.persistedValue)
        if !endpoints.isEmpty || !installedCLIs.isEmpty { Divider() }
        ForEach(endpoints) { model in
          Text(model.name).tag(AutomationAIAnnotateConfig.Provider.endpoint(model.id).persistedValue)
        }
        ForEach(installedCLIs, id: \.rawValue) { kind in
          Text(kind.displayName).tag(AutomationAIAnnotateConfig.Provider.cli(kind.rawValue).persistedValue)
        }
      }
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.Automations.aiPrivacyNote)
        Text(L10n.Automations.aiOutputNote)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Picker over the persisted form, so an endpoint id or CLI kind is a plain tag.
  private var providerBinding: Binding<String> {
    Binding(
      get: { config.provider.persistedValue },
      set: { config.provider = AutomationAIAnnotateConfig.Provider(persistedValue: $0) }
    )
  }
}
