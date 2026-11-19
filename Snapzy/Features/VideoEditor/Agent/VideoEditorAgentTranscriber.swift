//
//  VideoEditorAgentTranscriber.swift
//  Snapzy
//
//  What is said in the recording, for `get_transcript`. On-device only
//  (`SFSpeechRecognizer` with `requiresOnDeviceRecognition`): the audio never
//  leaves the Mac; only the text the agent reads does, like the rest of the
//  timeline. Asks for Speech Recognition permission the first time it runs.
//
//  The microphone track is preferred (the narrator), else every track mixed.
//  Results are words in SOURCE time of the primary recording, grouped into
//  phrases and cached per file and language; the toolbox maps them onto the
//  timeline through the current clips.
//

import AVFoundation
import Foundation
import Speech

// MARK: - Results

nonisolated struct VideoEditorTranscriptWord: Equatable, Sendable {
  let start: TimeInterval
  let duration: TimeInterval
  let text: String
}

nonisolated struct VideoEditorTranscriptPhrase: Equatable {
  let range: ClosedRange<TimeInterval>
  let text: String
}

nonisolated enum VideoEditorTranscriptError: Error, Equatable {
  case noAudio
  /// Speech Recognition is off for Snapzy.
  case denied
  /// No on-device recognizer for the language.
  case unsupported(String)
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
    case .failed(let detail):
      return "The audio could not be transcribed (\(detail))."
    }
  }
}

// MARK: - Transcriber

@MainActor
final class VideoEditorAgentTranscriber {
  /// `@concurrent`: a nonsending async closure type stored as a value pulls in
  /// swift_getExtendedFunctionTypeMetadata (macOS 15+ only), which crashes Release builds on 13/14 (#725).
  typealias Engine = @concurrent @Sendable (_ asset: AVAsset, _ roles: [VideoEditorAudioTrackRole], _ locale: Locale) async throws -> [VideoEditorTranscriptWord]

  private struct Key: Equatable {
    let url: URL
    let modified: Date?
    let language: String
  }

  private let engine: Engine
  private var cached: [(key: Key, phrases: [VideoEditorTranscriptPhrase])] = []
  private var inFlight: (key: Key, task: Task<[VideoEditorTranscriptPhrase], Error>)?

  init(engine: @escaping Engine = SpeechTranscriptionEngine.transcribe) {
    self.engine = engine
  }

  /// Phrases of the primary recording in source time, from cache when it is current.
  func phrases(for state: VideoEditorState, locale: Locale) async throws -> [VideoEditorTranscriptPhrase] {
    guard !state.audioTrackRoles.isEmpty else { throw VideoEditorTranscriptError.noAudio }
    let url = state.editingSourceURL
    let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    let key = Key(url: url, modified: modified, language: locale.identifier)
    if let hit = cached.first(where: { $0.key == key }) { return hit.phrases }
    if let inFlight, inFlight.key == key { return try await inFlight.task.value }

    let engine = self.engine
    let asset = state.asset
    let roles = state.audioTrackRoles
    let task = Task.detached(priority: .userInitiated) {
      Self.phrases(try await engine(asset, roles, locale))
    }
    inFlight = (key, task)
    defer { if inFlight?.key == key { inFlight = nil } }
    let phrases = try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
    cached.append((key, phrases))
    if cached.count > 3 { cached.removeFirst() }
    return phrases
  }

  /// Words → phrases: a new phrase after a pause, at the end of a sentence, or past `maxLength` seconds.
  nonisolated static func phrases(
    _ words: [VideoEditorTranscriptWord],
    maxGap: TimeInterval = 0.7,
    maxLength: TimeInterval = 12
  ) -> [VideoEditorTranscriptPhrase] {
    var phrases: [VideoEditorTranscriptPhrase] = []
    var current: (start: TimeInterval, end: TimeInterval, words: [String])?
    for word in words.sorted(by: { $0.start < $1.start }) {
      let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      let end = word.start + max(word.duration, 0)
      if var open = current,
         word.start - open.end <= maxGap,
         end - open.start <= maxLength,
         !(open.words.last.map(endsSentence) ?? false) {
        open.end = max(open.end, end)
        open.words.append(text)
        current = open
      } else {
        if let open = current {
          phrases.append(.init(range: open.start ... open.end, text: open.words.joined(separator: " ")))
        }
        current = (word.start, end, [text])
      }
    }
    if let open = current {
      phrases.append(.init(range: open.start ... open.end, text: open.words.joined(separator: " ")))
    }
    return phrases
  }

  nonisolated private static func endsSentence(_ word: String) -> Bool {
    guard let last = word.last else { return false }
    return ".?!。？！".contains(last)
  }
}

// MARK: - Speech engine

/// `SFSpeechRecognizer`, on-device, over the recording's audio read as 16 kHz mono PCM.
nonisolated enum SpeechTranscriptionEngine {
  static let sampleRate = 16_000.0

  static func transcribe(
    asset: AVAsset,
    roles: [VideoEditorAudioTrackRole],
    locale: Locale
  ) async throws -> [VideoEditorTranscriptWord] {
    try await authorize()
    guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
      throw VideoEditorTranscriptError.unsupported(locale.identifier)
    }
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard !tracks.isEmpty else { throw VideoEditorTranscriptError.noAudio }
    let microphone = zip(tracks, roles).filter { $0.1 == .microphone }.map(\.0)

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    request.taskHint = .dictation
    if #available(macOS 13.0, *) { request.addsPunctuation = true }
    recognizer.queue = OperationQueue()

    let duration = try await CMTimeGetSeconds(asset.load(.duration))
    let recognition = Recognition(request: request)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        recognition.start(recognizer: recognizer, continuation: continuation)
        // Feed the audio while the recognizer listens; it finishes after `endAudio`.
        let chosen = microphone.isEmpty ? tracks : microphone
        recognition.feeder = Task.detached(priority: .userInitiated) {
          do {
            try await feed(asset: asset, tracks: chosen, into: request)
            request.endAudio()
          } catch {
            recognition.finish(.failure(error))
          }
        }
        // A recognizer that never answers must not hold the tool call forever.
        let limit = max(60, duration.isFinite ? duration * 1.5 : 0)
        recognition.watchdog = Task.detached {
          try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
          guard !Task.isCancelled else { return }
          recognition.finish(.failure(VideoEditorTranscriptError.failed("timed out")))
        }
      }
    } onCancel: {
      recognition.cancel()
    }
  }

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

  private static func feed(asset: AVAsset, tracks: [AVAssetTrack], into request: SFSpeechAudioBufferRecognitionRequest) async throws {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
      throw VideoEditorTranscriptError.failed("audio format")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw VideoEditorTranscriptError.failed("audio reader") }
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? VideoEditorTranscriptError.failed("audio reader") }

    while let sample = output.copyNextSampleBuffer() {
      try Task.checkCancellation()
      guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
      // Copy rather than read through a pointer: the block buffer may not be contiguous.
      let frames = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
      guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
            let channel = buffer.floatChannelData?[0] else { continue }
      guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: frames * MemoryLayout<Float>.size, destination: channel) == kCMBlockBufferNoErr else {
        continue
      }
      buffer.frameLength = AVAudioFrameCount(frames)
      request.append(buffer)
    }
    if reader.status == .failed { throw reader.error ?? VideoEditorTranscriptError.failed("audio reader") }
  }

  /// One recognition task, resumed exactly once.
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

    /// The task reading audio into the request; cancelled when recognition ends.
    var feeder: Task<Void, Never>? {
      get { lock.lock(); defer { lock.unlock() }; return _feeder }
      set { lock.lock(); _feeder = newValue; let done = finished; lock.unlock(); if done { newValue?.cancel() } }
    }

    var watchdog: Task<Void, Never>? {
      get { lock.lock(); defer { lock.unlock() }; return _watchdog }
      set { lock.lock(); _watchdog = newValue; let done = finished; lock.unlock(); if done { newValue?.cancel() } }
    }

    func start(
      recognizer: SFSpeechRecognizer,
      continuation: CheckedContinuation<[VideoEditorTranscriptWord], Error>
    ) {
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
          // "No speech detected" is an empty transcript, not a failure.
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

    /// Resumes once; then stops the feeder, the watchdog and, on failure, the recognizer.
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
