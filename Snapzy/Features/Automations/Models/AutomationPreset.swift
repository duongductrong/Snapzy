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
  // Milestone 5
  case shareMenu = "share-menu"
  case designRouter = "design-router"

  /// Bundle ids Design Router sends to the design folder (Figma, Sketch).
  static let designAppBundleIDs = ["com.figma.Desktop", "com.bohemiancoding.sketch3"]

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
    case .shareMenu: "Share Menu"
    case .designRouter: "Design Router"
    }
  }

  var localizedName: String {
    switch self {
    case .quickCopy: L10n.Automations.presetQuickCopy
    case .cloudShare: L10n.Automations.presetCloudShare
    case .docsShot: L10n.Automations.presetDocsShot
    case .gifShare: L10n.Automations.presetGIFShare
    case .translateSnip: L10n.Automations.presetTranslateSnip
    case .shareMenu: L10n.Automations.presetShareMenu
    case .designRouter: L10n.Automations.presetDesignRouter
    }
  }

  var symbol: String {
    switch self {
    case .quickCopy: "doc.on.clipboard"
    case .cloudShare: "link"
    case .docsShot: "doc.richtext"
    case .gifShare: "photo.stack"
    case .translateSnip: "character.bubble"
    case .shareMenu: "list.bullet.rectangle"
    case .designRouter: "arrow.triangle.branch"
    }
  }

  /// Presets other presets point at (Share Menu's choices) are created first.
  static var creationOrder: [AutomationPreset] {
    allCases.filter { $0 != .shareMenu } + [.shareMenu]
  }

  /// `presetID` resolves another preset's automation id (Share Menu's Ask
  /// choices); presets it can't resolve are left out of the choices.
  func makeAutomation(resolve presetID: (AutomationPreset) -> UUID? = { _ in nil }) -> Automation {
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
    case .shareMenu:
      // One hotkey, many outcomes: pick Quick Copy, Cloud Share or Docs Shot after capturing.
      source = .capture(AutomationCaptureSpec(mode: .area, saveToExportDirectory: false))
      let choices = [AutomationPreset.quickCopy, .cloudShare, .docsShot]
        .compactMap(presetID)
        .map(AutomationAskChoice.automation)
      steps = [AutomationStep(.ask(AutomationAskConfig(choices: choices)))]
    case .designRouter:
      // Window captures of Figma / Sketch go to a design folder; others to the export folder.
      source = .capture(AutomationCaptureSpec(mode: .activeWindow, saveToExportDirectory: false))
      steps = [
        AutomationStep(.condition(AutomationConditionConfig(
          predicates: [.frontmostApp(bundleIDs: Self.designAppBundleIDs, negate: false)],
          otherwise: .skip(3)
        ))),
        AutomationStep(.saveToFolder(AutomationSaveToFolderConfig(nameTemplate: "{appName}/{datetime}"))),
        AutomationStep(.notify),
        AutomationStep(.stop),
        AutomationStep(.saveToFolder(AutomationSaveToFolderConfig(folder: .exportDirectory))),
        AutomationStep(.notify),
      ]
      // Needs the design folder before it can run.
      isEnabled = false
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
