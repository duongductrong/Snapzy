//
//  VideoEditorProgressOperation.swift
//  Snapzy
//
//  User-facing operation labels for the Video Editor progress overlay.
//

import Foundation

enum VideoEditorProgressOperation: Equatable {
  case saveVideo
  case exportVideo
  case saveGIF
  case exportGIF
  case uploadToCloud
  case generateCaptions
  case downloadSpeechModel

  /// Caption work runs in the overlay too and can be cancelled from it.
  var isCaptionWork: Bool { self == .generateCaptions || self == .downloadSpeechModel }

  var title: String {
    switch self {
    case .saveVideo:
      L10n.VideoEditor.savingVideo
    case .exportVideo:
      L10n.VideoEditor.exportingVideo
    case .saveGIF:
      L10n.VideoEditor.saveGIFTitle
    case .exportGIF:
      L10n.VideoEditor.saveResizedGIFTitle
    case .uploadToCloud:
      L10n.PreferencesHistory.uploadingToCloud
    case .generateCaptions:
      L10n.VideoEditor.generatingCaptions
    case .downloadSpeechModel:
      L10n.VideoEditor.downloadingSpeechModel
    }
  }

  var initialStatusMessage: String {
    switch self {
    case .saveVideo:
      L10n.VideoEditor.preparingSave
    case .exportVideo:
      L10n.VideoEditor.preparingExport
    case .saveGIF, .exportGIF:
      L10n.VideoEditor.resizingGIF
    case .uploadToCloud:
      L10n.PreferencesHistory.uploadingToCloud
    case .generateCaptions:
      L10n.VideoEditor.transcribingSpeech
    case .downloadSpeechModel:
      L10n.VideoEditor.downloadingSpeechModelDetail
    }
  }
}
