//
//  L10n+VideoEditorAIAndFonts.swift
//  Snapzy
//
//  Localized strings for the Video Editor Font Library (system, installed,
//  opt-in SIL OFL 1.1 downloads, and local imports) and AI typography/gap tools.
//

import Foundation

extension L10n.VideoEditor {
  nonisolated static let fontLibraryButton = L10n.string(
    "video-editor.font-library-button",
    defaultValue: "Fonts",
    comment: "Button label opening the Video Editor font library popover"
  )

  nonisolated static let fontImportLocalFile = L10n.string(
    "video-editor.font-import-local-file",
    defaultValue: "Import .TTF / .OTF…",
    comment: "Button in Font Library popover for importing custom font files from disk"
  )

  nonisolated static let systemFontDisplayName = L10n.string(
    "video-editor.system-font-display-name",
    defaultValue: "System (SF Pro)",
    comment: "Display name for the default macOS system font in the Video Editor font picker"
  )

  nonisolated static let installedFontsSection = L10n.string(
    "video-editor.installed-fonts-section",
    defaultValue: "Installed Fonts",
    comment: "Section header for fonts already installed on the Mac"
  )

  nonisolated static let oflFontsSection = L10n.string(
    "video-editor.ofl-fonts-section",
    defaultValue: "Downloadable Open Fonts (SIL OFL 1.1)",
    comment: "Section header in the Video Editor font picker for opt-in downloadable SIL Open Font License 1.1 fonts"
  )

  nonisolated static let importedFontsSection = L10n.string(
    "video-editor.imported-fonts-section",
    defaultValue: "Imported Fonts",
    comment: "Section header for user-imported local font files"
  )

  nonisolated static let fontSearchPlaceholder = L10n.string(
    "video-editor.font-search-placeholder",
    defaultValue: "Search installed fonts…",
    comment: "Search field placeholder inside the Video Editor font picker"
  )

  nonisolated static let fontMissingNotice = L10n.string(
    "video-editor.font-missing-notice",
    defaultValue: "Font not installed — showing System Font",
    comment: "Notice shown when captions reference a font family that is not installed on this Mac"
  )

  nonisolated static let fontUseSystemSubstitute = L10n.string(
    "video-editor.font-use-system-substitute",
    defaultValue: "Use System Font",
    comment: "Button switching a missing font reference to the macOS system font"
  )

  nonisolated static let fontDownloadOFLButton = L10n.string(
    "video-editor.font-download-ofl-button",
    defaultValue: "Download (OFL)",
    comment: "Button label to explicitly download a curated SIL Open Font License 1.1 font family"
  )

  nonisolated static let fontLicenseButton = L10n.string(
    "video-editor.font-license-button",
    defaultValue: "OFL License",
    comment: "Button and sheet title for viewing the downloaded SIL Open Font License 1.1 text"
  )

  nonisolated static let fontSourceAttribution = L10n.string(
    "video-editor.font-source-attribution",
    defaultValue: "Source: github.com/google/fonts @ 50268007 (SHA-256 verified)",
    comment: "Attribution subtitle disclosing the pinned Google Fonts commit and SHA-256 verification for opt-in OFL font downloads"
  )

  nonisolated static let captionsItalic = L10n.string(
    "video-editor.captions-italic",
    defaultValue: "Italic",
    comment: "Toggle and tooltip label for italic slant on subtitles"
  )

  nonisolated static let aiStepClosedGaps = L10n.string(
    "video-editor.ai-step-closed-gaps",
    defaultValue: "Closed timeline gaps",
    comment: "AI transcript step row when empty timeline gaps were closed"
  )
}
