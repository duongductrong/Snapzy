//
//  PostCaptureRouting.swift
//  Snapzy
//
//  Who decides what happens after a screenshot is saved: the global
//  after-capture matrix, or an automation run started by a trigger.
//

import Foundation

nonisolated enum PostCaptureRouting: Equatable, Sendable {
  /// Global `AfterCaptureAction` matrix.
  case standard
  /// The automation run registered under `runID` in `AutomationRunner`.
  case automation(runID: UUID)
  /// The unified capture toolbar session `sessionID` (milestone 6, #498): the
  /// capture goes to the temp folder and the toolbar decides what happens.
  case captureToolbar(sessionID: UUID)

  var logValue: String {
    switch self {
    case .standard: "standard"
    case .automation(let runID): "automation:\(runID.uuidString.prefix(8))"
    case .captureToolbar(let sessionID): "toolbar:\(sessionID.uuidString.prefix(8))"
    }
  }
}

/// Emitted by `ScreenCaptureManager` for every saved interactive screenshot.
nonisolated struct CaptureCompletionEvent: Sendable {
  let url: URL
  let routing: PostCaptureRouting
}
