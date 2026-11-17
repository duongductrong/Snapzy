//
//  SFSpeechChunkRecognizer.swift
//  Snapzy
//
//  One on-device `SFSpeechRecognizer` pass over a time range of the audio. Words come
//  back relative to the start of the range. Resumes its continuation exactly once.
//

import AVFoundation
import Foundation
import Speech

nonisolated enum SFSpeechChunkRecognizer {
  static func authorize() async throws {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      return
    case .notDetermined:
      let status = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
      }
      guard status == .authorized else { throw VideoEditorTranscriptError.denied }
    default:
      throw VideoEditorTranscriptError.denied
    }
  }

  static func recognize(
    asset: AVAsset,
    tracks: [AVAssetTrack],
    range: ClosedRange<TimeInterval>,
    locale: Locale,
    contextualStrings: [String]
  ) async throws -> [VideoEditorTranscriptWord] {
    guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
      throw VideoEditorTranscriptError.unsupported(locale.identifier)
    }
    guard let format = TranscriptAudioReader.speechFormat() else {
      throw VideoEditorTranscriptError.failed("audio format")
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    request.taskHint = .dictation
    request.addsPunctuation = true
    request.contextualStrings = contextualStrings
    recognizer.queue = OperationQueue()

    let state = Recognition(request: request)
    let limit = max(30, (range.upperBound - range.lowerBound) * 2)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        state.start(recognizer: recognizer, continuation: continuation)
        state.feeder = Task.detached(priority: .userInitiated) {
          do {
            try await TranscriptAudioReader.read(asset: asset, tracks: tracks, format: format, range: range) { buffer, _ in
              request.append(buffer)
            }
            request.endAudio()
          } catch {
            state.finish(.failure(error))
          }
        }
        // A recognizer that never answers must not hold the file forever.
        state.watchdog = Task.detached {
          try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
          guard !Task.isCancelled else { return }
          state.finish(.failure(VideoEditorTranscriptError.failed("timed out")))
        }
      }
    } onCancel: {
      state.cancel()
    }
  }

  private final class Recognition: @unchecked Sendable {
    private let lock = NSLock()
    private let request: SFSpeechAudioBufferRecognitionRequest
    private var continuation: CheckedContinuation<[VideoEditorTranscriptWord], Error>?
    private var task: SFSpeechRecognitionTask?
    private var words: [VideoEditorTranscriptWord] = []
    private var cancelled = false
    private var finished = false
    private var _feeder: Task<Void, Never>?
    private var _watchdog: Task<Void, Never>?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
      self.request = request
    }

    var feeder: Task<Void, Never>? {
      get { lock.lock(); defer { lock.unlock() }; return _feeder }
      set { lock.lock(); _feeder = newValue; let done = finished; lock.unlock(); if done { newValue?.cancel() } }
    }

    var watchdog: Task<Void, Never>? {
      get { lock.lock(); defer { lock.unlock() }; return _watchdog }
      set { lock.lock(); _watchdog = newValue; let done = finished; lock.unlock(); if done { newValue?.cancel() } }
    }

    func start(recognizer: SFSpeechRecognizer, continuation: CheckedContinuation<[VideoEditorTranscriptWord], Error>) {
      lock.lock()
      self.continuation = continuation
      let cancelled = self.cancelled
      lock.unlock()
      guard !cancelled else {
        finish(.failure(CancellationError()))
        return
      }
      let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
        guard let self else { return }
        if let result, result.isFinal {
          self.append(result.bestTranscription.segments)
          self.finish(.success(self.collected))
        } else if let error {
          let collected = self.collected
          // "No speech detected" is an empty chunk, not a failure.
          if !collected.isEmpty || (error as NSError).code == 1110 {
            self.finish(.success(collected))
          } else {
            self.finish(.failure(VideoEditorTranscriptError.failed(error.localizedDescription)))
          }
        }
      }
      lock.lock()
      self.task = task
      lock.unlock()
    }

    private var collected: [VideoEditorTranscriptWord] {
      lock.lock()
      defer { lock.unlock() }
      return words
    }

    private func append(_ segments: [SFTranscriptionSegment]) {
      lock.lock()
      defer { lock.unlock() }
      let after = words.last.map { $0.start + 0.01 } ?? -1
      for segment in segments where segment.timestamp >= after {
        words.append(.init(start: segment.timestamp, duration: segment.duration, text: segment.substring))
      }
    }

    func finish(_ result: Result<[VideoEditorTranscriptWord], Error>) {
      lock.lock()
      let continuation = self.continuation
      self.continuation = nil
      let firstFinish = !finished
      finished = true
      let feeder = _feeder, watchdog = _watchdog, task = self.task
      lock.unlock()
      continuation?.resume(with: result)
      guard firstFinish else { return }
      feeder?.cancel()
      watchdog?.cancel()
      if case .failure = result {
        request.endAudio()
        task?.cancel()
      }
    }

    func cancel() {
      lock.lock()
      cancelled = true
      let task = self.task
      lock.unlock()
      task?.cancel()
      finish(.failure(CancellationError()))
    }
  }
}
