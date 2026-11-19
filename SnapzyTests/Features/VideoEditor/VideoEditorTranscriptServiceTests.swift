//
//  VideoEditorTranscriptServiceTests.swift
//  SnapzyTests
//
//  Captions engine (5a): chunk planning, offsets, retries and partial failure (fake
//  recognizer), engine selection order, caching, the remote opt-in and its parsing.
//

import AVFoundation
import XCTest
@testable import Snapzy

final class VideoEditorTranscriptServiceTests: XCTestCase {
  private var tempDirectory: URL!

  override func setUpWithError() throws {
    tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("transcript-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDirectory)
  }

  // MARK: Chunking

  func testPlanCutsAtTheLatestSilenceInTheBackHalf() {
    let chunks = TranscriptChunker.plan(duration: 120, silences: [30 ... 32, 44 ... 46, 60 ... 62, 98 ... 99], maxLength: 50)
    XCTAssertEqual(chunks, [0 ... 45, 45 ... 95, 95 ... 120])
    XCTAssertEqual(chunks.first?.lowerBound, 0)
    XCTAssertTrue(chunks.allSatisfy { $0.upperBound - $0.lowerBound <= 50 })
  }

  func testPlanHardCutsWithoutSilenceAndKeepsShortFilesWhole() {
    XCTAssertEqual(TranscriptChunker.plan(duration: 30, silences: []), [0 ... 30])
    XCTAssertEqual(TranscriptChunker.plan(duration: 110, silences: []), [0 ... 50, 50 ... 100, 100 ... 110])
    XCTAssertEqual(TranscriptChunker.plan(duration: 0, silences: []), [])
  }

  func testRunOffsetsWordsByChunkStart() async throws {
    let result = try await TranscriptChunker.run(chunks: [0 ... 10, 10 ... 20]) { range in
      [.init(start: 1, duration: 0.5, text: "w\(Int(range.lowerBound))")]
    }
    XCTAssertEqual(result.words.map(\.start), [1, 11])
    XCTAssertEqual(result.words.map(\.text), ["w0", "w10"])
    XCTAssertTrue(result.unrecognizedSpans.isEmpty)
  }

  func testRunRetriesAChunkTwiceThenSucceeds() async throws {
    let attempts = Attempts()
    let result = try await TranscriptChunker.run(chunks: [0 ... 10]) { _ in
      if attempts.next() < 3 { throw VideoEditorTranscriptError.failed("flaky") }
      return [.init(start: 0, duration: 1, text: "ok")]
    }
    XCTAssertEqual(attempts.value, 3)
    XCTAssertEqual(result.words.map(\.text), ["ok"])
  }

  func testRunReportsAChunkThatKeepsFailingWithoutFailingTheFile() async throws {
    let result = try await TranscriptChunker.run(chunks: [0 ... 10, 10 ... 20, 20 ... 30]) { range in
      if range.lowerBound == 10 { throw VideoEditorTranscriptError.failed("bad audio") }
      return [.init(start: 0, duration: 1, text: "w")]
    }
    XCTAssertEqual(result.unrecognizedSpans, [10 ... 20])
    XCTAssertEqual(result.words.map(\.start), [0, 20])
  }

  func testRunFailsWhenNothingCouldBeRecognizedOrOnPermissionErrors() async {
    do {
      _ = try await TranscriptChunker.run(chunks: [0 ... 10]) { _ in throw VideoEditorTranscriptError.failed("x") }
      XCTFail("expected failure")
    } catch {
      XCTAssertEqual(error as? VideoEditorTranscriptError, .failed("x"))
    }
    let attempts = Attempts()
    do {
      _ = try await TranscriptChunker.run(chunks: [0 ... 10, 10 ... 20]) { _ in
        _ = attempts.next()
        throw VideoEditorTranscriptError.denied
      }
      XCTFail("expected failure")
    } catch {
      XCTAssertEqual(error as? VideoEditorTranscriptError, .denied)
      XCTAssertEqual(attempts.value, 1)
    }
  }

  // MARK: Service

  func testSelectionPrefersTheFirstAvailableEngineThenRemoteOnlyWhenAllowed() async {
    let first = FakeEngine(.speechAnalyzer, availability: .unsupported)
    let second = FakeEngine(.sfSpeech, availability: .available)
    let remote = FakeEngine(.remote, availability: .available)
    let service = VideoEditorTranscriptService(engines: [first, second], remote: remote)
    var plan = await service.plan(locale: Locale(identifier: "en_US"))
    XCTAssertEqual(plan?.engine.id, .sfSpeech)

    let downloadable = VideoEditorTranscriptService(
      engines: [FakeEngine(.speechAnalyzer, availability: .needsModelDownload), second], remote: remote
    )
    plan = await downloadable.plan(locale: Locale(identifier: "en_US"))
    XCTAssertEqual(plan?.engine.id, .speechAnalyzer)
    XCTAssertEqual(plan?.availability, .needsModelDownload)

    let none = VideoEditorTranscriptService(engines: [first], remote: remote)
    plan = await none.plan(locale: Locale(identifier: "vi_VN"))
    XCTAssertNil(plan)
    plan = await none.plan(locale: Locale(identifier: "vi_VN"), allowRemote: true)
    XCTAssertEqual(plan?.engine.id, .remote)
  }

  func testTranscribeUsesMicrophoneTrackCachesAndThrowsWhenUnsupported() async throws {
    let url = try await VideoEditorActivityFixture.makeVideoFile(in: tempDirectory, duration: 2, audio: true)
    let asset = AVURLAsset(url: url)
    let engine = FakeEngine(.sfSpeech, availability: .available)
    let service = VideoEditorTranscriptService(engines: [engine])
    let locale = Locale(identifier: "en_US")

    let first = try await service.transcribe(asset: asset, roles: [.microphone], locale: locale, contextualStrings: ["Snapzy"])
    let second = try await service.transcribe(asset: asset, roles: [.microphone], locale: locale)
    XCTAssertEqual(first, second)
    XCTAssertEqual(engine.calls, 1)
    XCTAssertEqual(engine.lastContext, ["Snapzy"])
    XCTAssertEqual(engine.lastTrackCount, 1)

    _ = try await service.transcribe(asset: asset, roles: [.microphone], locale: Locale(identifier: "de_DE"))
    XCTAssertEqual(engine.calls, 2, "another locale is a different cache entry")

    let unsupported = VideoEditorTranscriptService(engines: [FakeEngine(.sfSpeech, availability: .unsupported)])
    do {
      _ = try await unsupported.transcribe(asset: asset, roles: [.microphone], locale: locale)
      XCTFail("expected unsupported")
    } catch {
      XCTAssertEqual(error as? VideoEditorTranscriptError, .unsupported("en_US"))
    }
  }

  // MARK: Remote

  func testRemoteEngineRefusesWithoutOptIn() async {
    let model = CustomOCRModel(name: "Whisper", baseURL: "https://api.example.com/v1", modelIdentifier: "whisper-1")
    let engine = RemoteTranscriptionEngine(model: model, userOptedIn: false)
    let availability = await engine.availability(for: Locale(identifier: "en_US"))
    XCTAssertEqual(availability, .unsupported)
    do {
      _ = try await engine.transcribe(asset: AVURLAsset(url: tempDirectory), tracks: [], locale: Locale(identifier: "en_US"), contextualStrings: [], progress: nil)
      XCTFail("expected refusal")
    } catch {
      XCTAssertEqual(error as? VideoEditorTranscriptError, .remoteNotAllowed)
    }
  }

  func testRemoteEndpointAndResponseParsing() throws {
    XCTAssertEqual(RemoteTranscriptionEngine.endpointURL(forBaseURL: "https://x.io/")?.absoluteString, "https://x.io/v1/audio/transcriptions")
    XCTAssertEqual(RemoteTranscriptionEngine.endpointURL(forBaseURL: "http://localhost:11434/v1")?.absoluteString, "http://localhost:11434/v1/audio/transcriptions")
    XCTAssertEqual(RemoteTranscriptionEngine.endpointURL(forBaseURL: "https://x.io/v1/chat/completions")?.absoluteString, "https://x.io/v1/audio/transcriptions")

    let words = try RemoteTranscriptionEngine.parse(Data(#"{"words":[{"word":" Hi","start":0.5,"end":0.9}],"segments":[]}"#.utf8))
    XCTAssertEqual(words, [.init(start: 0.5, duration: 0.4, text: "Hi")])
    let segments = try RemoteTranscriptionEngine.parse(Data(#"{"segments":[{"text":"Hello there","start":1,"end":3}]}"#.utf8))
    XCTAssertEqual(segments, [.init(start: 1, duration: 2, text: "Hello there")])
    XCTAssertThrowsError(try RemoteTranscriptionEngine.parse(Data("nope".utf8)))
  }
}

// MARK: - Fakes

private nonisolated final class Attempts: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.lock(); defer { lock.unlock() }; return count }
  func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}

private nonisolated final class FakeEngine: TranscriptEngine, @unchecked Sendable {
  let id: TranscriptEngineID
  private let available: TranscriptEngineAvailability
  private let lock = NSLock()
  private var _calls = 0
  private var _context: [String] = []
  private var _trackCount = 0

  init(_ id: TranscriptEngineID, availability: TranscriptEngineAvailability) {
    self.id = id
    self.available = availability
  }

  var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
  var lastContext: [String] { lock.lock(); defer { lock.unlock() }; return _context }
  var lastTrackCount: Int { lock.lock(); defer { lock.unlock() }; return _trackCount }

  func availability(for locale: Locale) async -> TranscriptEngineAvailability { available }

  func transcribe(
    asset: AVAsset,
    tracks: [AVAssetTrack],
    locale: Locale,
    contextualStrings: [String],
    progress: (@Sendable (TranscriptProgress) -> Void)?
  ) async throws -> TranscriptResult {
    lock.lock()
    _calls += 1
    _context = contextualStrings
    _trackCount = tracks.count
    lock.unlock()
    return TranscriptResult(words: [.init(start: 0, duration: 1, text: locale.identifier)])
  }

  func cancel() {}
}
