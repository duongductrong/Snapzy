//
//  AppEnvironment.swift
//  Snapzy
//
//  App-level dependency container.
//

import Foundation

@MainActor
final class AppEnvironment {
  let screenCaptureViewModel: ScreenCaptureViewModel

  init(screenCaptureViewModel: ScreenCaptureViewModel) {
    self.screenCaptureViewModel = screenCaptureViewModel
  }

  static func live() -> AppEnvironment {
    AppEnvironment(screenCaptureViewModel: ScreenCaptureViewModel())
  }
}
