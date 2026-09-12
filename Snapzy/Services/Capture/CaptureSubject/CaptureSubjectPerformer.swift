//
//  CaptureSubjectPerformer.swift
//  Snapzy
//
//  Routes a locked Capture Subject preview into the cutout pipeline.
//

import Foundation

@MainActor
final class CaptureSubjectPerformer: CaptureSubjectCapturePerforming {
  private let viewModelProvider: @MainActor () -> ScreenCaptureViewModel?

  init(viewModelProvider: (@MainActor () -> ScreenCaptureViewModel?)? = nil) {
    self.viewModelProvider = viewModelProvider ?? {
      AppStatusBarController.shared.screenCaptureViewModel
    }
  }

  func captureSubject(preview: CaptureSubjectSnappedPreview) async {
    guard let viewModel = viewModelProvider() else {
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "Capture subject skipped: screen capture view model unavailable"
      )
      return
    }
    await viewModel.finishObjectCutout(from: preview)
  }
}
