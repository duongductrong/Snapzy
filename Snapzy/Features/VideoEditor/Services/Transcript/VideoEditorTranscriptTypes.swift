//
//  VideoEditorTranscriptTypes.swift
//  Snapzy
//
//  Value types shared by every transcript engine, the service and its callers
//  (the video-editor agent, captions). All times are SOURCE time of the audio
//  that was transcribed.
//

import Foundation

nonisolated struct VideoEditorTranscriptWord: Equatable, Sendable, Codable {
  let start: TimeInterval
  let duration: TimeInterval
  let text: String

  var end: TimeInterval { start + max(duration, 0) }
}

nonisolated struct VideoEditorTranscriptPhrase: Equatable {
  let range: ClosedRange<TimeInterval>
  let text: String
}

/// Words plus the stretches an engine gave up on (a chunk that failed all retries).
nonisolated struct TranscriptResult: Equatable, Sendable {
  var words: [VideoEditorTranscriptWord]
  var unrecognizedSpans: [ClosedRange<TimeInterval>] = []
}

nonisolated enum TranscriptEngineID: String, Sendable, Codable {
  case speechAnalyzer
  case sfSpeech
  case remote
}

nonisolated enum TranscriptEngineAvailability: Equatable, Sendable {
  case available
  /// Works for the locale once its speech model is installed (`transcribe` installs it, with progress).
  case needsModelDownload
  case unsupported
}

nonisolated enum TranscriptProgress: Equatable, Sendable {
  case downloadingModel(fraction: Double)
  case transcribing(fraction: Double)
}

nonisolated enum VideoEditorTranscriptError: Error, Equatable {
  case noAudio
  /// Speech Recognition is off for Snapzy.
  case denied
  /// No on-device recognizer for the language.
  case unsupported(String)
  /// A remote engine was asked for without the caller's explicit opt-in.
  case remoteNotAllowed
  case failed(String)

  /// Written for the model: what to tell the user.
  var message: String {
    switch self {
    case .noAudio:
      return "This video has no audio, so there is nothing to transcribe."
    case .denied:
      return "Speech recognition is turned off for Snapzy. Tell the user to allow it in "
        + "System Settings › Privacy & Security › Speech Recognition, then ask again."
    case .unsupported(let language):
      return "On-device speech recognition isn't available for \(language) on this Mac. "
        + "Try another language, or tell the user (it may need Dictation turned on in System Settings › Keyboard)."
    case .remoteNotAllowed:
      return "Remote transcription sends audio off this Mac and was not approved."
    case .failed(let detail):
      return "The audio could not be transcribed (\(detail))."
    }
  }
}

/// Cancellation shared between an engine's `cancel()` and its running work.
nonisolated final class TranscriptCancelFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }

  func reset() {
    lock.lock()
    cancelled = false
    lock.unlock()
  }

  func check() throws {
    if isCancelled { throw CancellationError() }
    try Task.checkCancellation()
  }
}
