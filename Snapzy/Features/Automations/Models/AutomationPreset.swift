//
//  AutomationPreset.swift
//  Snapzy
//
//  Built-in automations seeded on first launch (and offered again through
//  "Restore built-in"). Shortcuts ship unbound so a preset never takes a
//  combination the user already uses elsewhere. Presets that need a setting
//  (Docs Shot needs a folder) ship disabled and show "Needs setup".
//

import Foundation

enum AutomationPreset: String, CaseIterable {
  case quickCopy = "quick-copy"
  case cloudShare = "cloud-share"
  case docsShot = "docs-shot"
  case gifShare = "gif-share"
  case translateSnip = "translate-snip"

  /// Template Docs Shot copies: Markdown image with the path relative to the folder.
  static let docsShotMarkdown = "![{file.basename}]({saved.relativeURL})"

  /// Name written to storage. Kept in English so `displayName` can tell an
  /// untouched preset (shown localized) from one the user renamed.
  var storedName: String {
    switch self {
    case .quickCopy: "Quick Copy"
    case .cloudShare: "Cloud Share"
    case .docsShot: "Docs Shot"
    case .gifShare: "GIF Share"
    case .translateSnip: "Translate Snip"
    }
  }

  var localizedName: String {
    switch self {
    case .quickCopy: L10n.Automations.presetQuickCopy
    case .cloudShare: L10n.Automations.presetCloudShare
    case .docsShot: L10n.Automations.presetDocsShot
    case .gifShare: L10n.Automations.presetGIFShare
    case .translateSnip: L10n.Automations.presetTranslateSnip
    }
  }

  var symbol: String {
    switch self {
    case .quickCopy: "doc.on.clipboard"
    case .cloudShare: "link"
    case .docsShot: "doc.richtext"
    case .gifShare: "photo.stack"
    case .translateSnip: "character.bubble"
    }
  }

  func makeAutomation() -> Automation {
    let source: AutomationSource
    let steps: [AutomationStep]
    var isEnabled = true
    switch self {
    case .quickCopy:
      source = .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false))
      steps = [AutomationStep(.copyImage), AutomationStep(.notify)]
    case .cloudShare:
      source = .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false))
      steps = [
        AutomationStep(.copyImage),
        AutomationStep(.upload(AutomationUploadConfig())),
        AutomationStep(.copyLink(AutomationLinkTemplate(style: .url))),
        AutomationStep(.notify),
      ]
    case .docsShot:
      source = .capture(AutomationCaptureSpec(mode: .activeWindow, saveToExportDirectory: false))
      steps = [
        AutomationStep(.applyCanvasPreset(AutomationCanvasPresetConfig())),
        AutomationStep(.resize(AutomationResizeConfig(mode: .maxDimension, maxDimension: 1600))),
        AutomationStep(.convert(AutomationConvertConfig(format: .webp, quality: 85))),
        AutomationStep(.saveToFolder(AutomationSaveToFolderConfig(nameTemplate: "{date}-{appName}"))),
        AutomationStep(.copyText(AutomationTextTemplate(template: Self.docsShotMarkdown))),
        AutomationStep(.notify),
      ]
      // Needs a folder before it can run.
      isEnabled = false
    case .gifShare:
      source = .capture(AutomationCaptureSpec(mode: .recordingArea, saveToExportDirectory: false, recordingOutput: .gif))
      steps = [
        AutomationStep(.upload(AutomationUploadConfig())),
        AutomationStep(.copyLink(AutomationLinkTemplate(style: .url))),
        AutomationStep(.notify),
      ]
    case .translateSnip:
      source = .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false))
      steps = [
        AutomationStep(.ocr(AutomationOCRConfig())),
        AutomationStep(.translate(AutomationTranslateConfig())),
        AutomationStep(.copyText(AutomationTextTemplate())),
        AutomationStep(.notify),
      ]
    }
    return Automation(
      name: storedName,
      symbol: symbol,
      isEnabled: isEnabled,
      // Offered on Quick Access cards and History items; existing users keep their own setup.
      triggers: [.quickAccessAction, .historyAction],
      source: source,
      steps: steps,
      presetID: rawValue
    )
  }
}
