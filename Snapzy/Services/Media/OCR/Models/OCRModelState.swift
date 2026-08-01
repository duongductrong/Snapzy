//
//  OCRModelState.swift
//  Snapzy
//
//  Install state of a downloadable OCR model.
//

import Foundation

/// Per-model install state surfaced by `OCRModelStore`.
enum OCRModelInstallState: Equatable {
  /// Model files are not present on disk.
  case notInstalled
  /// Download in progress; value is aggregate completion in `0...1`.
  case downloading(progress: Double)
  /// Bytes are on disk; checksum/dictionary verification is running.
  case verifying
  /// All files verified and present in the install directory.
  case installed
  /// Download or verification failed; `reason` is a user-presentable message.
  case failed(reason: String)

  /// Download or verification currently in progress.
  var isInFlight: Bool {
    switch self {
    case .downloading, .verifying:
      return true
    case .notInstalled, .installed, .failed:
      return false
    }
  }
}
