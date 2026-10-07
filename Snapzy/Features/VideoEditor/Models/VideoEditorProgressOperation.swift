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
    }
  }
}
