//
//  L10n+TranslateAgentCLI.swift
//  Snapzy
//
//  Strings for translating through an agent CLI (Claude Code, Codex, OpenCode)
//  and the engine picker in Settings › Capture › OCR.
//

import Foundation

extension L10n.Translate {
  static var settingsEngineDescriptionAll: String {
    L10n.string(
      "translate.settings-engine-description-all",
      defaultValue: "Apple Translation runs on this Mac. Agent CLIs and custom endpoints send the text to their model provider.",
      comment: "Settings description of the translation engine picker"
    )
  }
  static var settingsHeroSubtitle: String {
    L10n.string(
      "translate.settings-hero-subtitle",
      defaultValue: "Pick the language and the engine Snapzy translates with, on this Mac or through your own AI.",
      comment: "Settings › Translate page subtitle"
    )
  }
  static var settingsLanguageSection: String {
    L10n.string("translate.settings-language-section", defaultValue: "Language",
                comment: "Settings › Translate section title over the target language picker")
  }
  static var settingsGroupDevice: String {
    L10n.string("translate.settings-group-device", defaultValue: "On this Mac",
                comment: "Translation engine picker: heading over Apple Translation")
  }
  static var settingsGroupAgentCLI: String {
    L10n.string("translate.settings-group-agent-cli", defaultValue: "Agent CLIs",
                comment: "Translation engine picker: heading over Claude Code, Codex and OpenCode")
  }
  static var settingsGroupEndpoints: String {
    L10n.string("translate.settings-group-endpoints", defaultValue: "Custom endpoints",
                comment: "Translation engine picker: heading over custom OpenAI-compatible endpoints")
  }
  static var settingsAppleTileTitle: String {
    L10n.string("translate.settings-apple-tile-title", defaultValue: "Apple Translation",
                comment: "Translation engine tile title for Apple Translation")
  }
  static var settingsAppleTileSubtitle: String {
    L10n.string("translate.settings-apple-tile-subtitle", defaultValue: "Private, on device",
                comment: "Translation engine tile subtitle for Apple Translation")
  }
  static var settingsAppleTileUnavailable: String {
    L10n.string("translate.settings-apple-tile-unavailable", defaultValue: "Needs macOS 15",
                comment: "Translation engine tile subtitle when Apple Translation is not available on this macOS")
  }
  static var settingsAppleDetail: String {
    L10n.string("translate.settings-apple-detail", defaultValue: "Translation runs on this Mac. Your text never leaves it.",
                comment: "Note under the engine picker when Apple Translation is selected")
  }
  static var settingsCLINotInstalled: String {
    L10n.string("translate.settings-cli-not-installed", defaultValue: "Not installed",
                comment: "Translation engine tile subtitle for an agent CLI that was not found on this Mac")
  }
  static var settingsOpenAISettings: String {
    L10n.string("translate.settings-open-ai-settings", defaultValue: "AI Settings…",
                comment: "Button that opens Settings › AI from the translation settings")
  }
  static var settingsCLIModelTitle: String {
    L10n.string("translate.settings-cli-model-title", defaultValue: "Translation model",
                comment: "Title of the model override picker for translating with an agent CLI")
  }
  static var settingsCLIModelDescription: String {
    L10n.string(
      "translate.settings-cli-model-description",
      defaultValue: "Keep the model from Settings › AI, or pick a faster one just for translating.",
      comment: "Description of the model override picker for translating with an agent CLI"
    )
  }
  static func settingsCLIModelFollowAI(_ model: String) -> String {
    L10n.format(
      "translate.settings-cli-model-follow-ai",
      defaultValue: "Same as AI settings (%@)",
      comment: "Model override picker option: use the model set in Settings › AI. %@ is that model's name",
      model
    )
  }
  static var settingsCLIModelOverridden: String {
    L10n.string("translate.settings-cli-model-overridden", defaultValue: "Translation only",
                comment: "Small badge shown when translation uses its own model instead of the AI settings one")
  }
  static func settingsCLIPrivacy(_ cli: String) -> String {
    L10n.format(
      "translate.settings-cli-privacy",
      defaultValue: "The text goes to the model provider %@ is signed in to. Snapzy runs it with no tools and no file access.",
      comment: "Privacy note when an agent CLI translates. %@ is the CLI name, e.g. Claude Code",
      cli
    )
  }
  static func settingsCLIConfigure(_ cli: String) -> String {
    L10n.format(
      "translate.settings-cli-configure",
      defaultValue: "Configure %@ for translation",
      comment: "Help and accessibility label of the gear button on an agent CLI tile. %@ is the CLI name",
      cli
    )
  }
  static var settingsCLITest: String {
    L10n.string("translate.settings-cli-test", defaultValue: "Try It",
                comment: "Button that translates a sample sentence with the selected agent CLI")
  }
  static var settingsCLITesting: String {
    L10n.string("translate.settings-cli-testing", defaultValue: "Translating a sample…",
                comment: "Status while the agent CLI translates the sample sentence")
  }
  static func settingsCLITestDone(_ seconds: String) -> String {
    L10n.format(
      "translate.settings-cli-test-done",
      defaultValue: "Answered in %@ s",
      comment: "Status after the agent CLI translated the sample sentence. %@ is the time in seconds, e.g. 4.2",
      seconds
    )
  }
  static func engineAgentCLIFooter(_ cli: String) -> String {
    L10n.format(
      "translate.engine-agent-cli-footer",
      defaultValue: "Translated by %@. The text was sent through this agent CLI.",
      comment: "Footer on the translation card when an agent CLI produced the result. %@ is the CLI name",
      cli
    )
  }
}

extension L10n.Preferences {
  static var translateTab: String {
    L10n.string("preferences.tab.translate", defaultValue: "Translate",
                comment: "Preferences tab title for translation settings (target language and engine)")
  }
}

extension L10n.AnnotateTranslate {
  static func engineAgentCLI(_ cli: String) -> String {
    L10n.format(
      "annotate.translate.engine-agent-cli",
      defaultValue: "%@ (text is sent through this agent CLI)",
      comment: "Auto Translate menu: current engine is an agent CLI. %@ is the CLI name",
      cli
    )
  }
}
