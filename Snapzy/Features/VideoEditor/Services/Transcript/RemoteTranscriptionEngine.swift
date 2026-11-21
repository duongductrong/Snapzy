//
//  RemoteTranscriptionEngine.swift
//  Snapzy
//
//  Opt-in only: sends the audio to the OpenAI-compatible endpoint the user configured in
//  Settings → AI (`POST …/audio/transcriptions`, `verbose_json` with word timestamps).
//  Never chosen on its own: `userOptedIn` must be true, and the service only offers it
//  when the caller passes `allowRemote`. Skeleton: whole-file upload (no chunking yet).
//

import AVFoundation
import Foundation

nonisolated final class RemoteTranscriptionEngine: TranscriptEngine {
  let id = TranscriptEngineID.remote
  private let model: CustomOCRModel
  private let userOptedIn: Bool
  private let keychain: OCRKeychainStoring
  private let session: URLSessionProtocol
  private let cancelFlag = TranscriptCancelFlag()

  init(
    model: CustomOCRModel,
    userOptedIn: Bool,
    keychain: OCRKeychainStoring = OCRKeychainStore(),
    session: URLSessionProtocol = URLSession.shared
  ) {
    self.model = model
    self.userOptedIn = userOptedIn
    self.keychain = keychain
    self.session = session
  }

  func availability(for locale: Locale) async -> TranscriptEngineAvailability {
    userOptedIn && Self.endpointURL(forBaseURL: model.baseURL) != nil ? .available : .unsupported
  }

  func transcribe(
    asset: AVAsset,
    tracks: [AVAssetTrack],
    locale: Locale,
    contextualStrings: [String],
    progress: (@Sendable (TranscriptProgress) -> Void)?
  ) async throws -> TranscriptResult {
    guard userOptedIn else { throw VideoEditorTranscriptError.remoteNotAllowed }
    guard let endpoint = Self.endpointURL(forBaseURL: model.baseURL) else {
      throw VideoEditorTranscriptError.failed("invalid endpoint")
    }
    cancelFlag.reset()
    let audio = try await Self.exportAudio(asset: asset, tracks: tracks)
    defer { try? FileManager.default.removeItem(at: audio) }
    try cancelFlag.check()

    let boundary = "snapzy-\(UUID().uuidString)"
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 600
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    if let key = keychain.readKey(for: model.id), !key.isEmpty {
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = Self.multipartBody(
      boundary: boundary,
      fields: Self.fields(model: model.modelIdentifier, locale: locale, prompt: contextualStrings.joined(separator: ", ")),
      file: try Data(contentsOf: audio),
      fileName: "audio.m4a"
    )
    progress?(.transcribing(fraction: 0.1))
    let (data, response) = try await session.data(for: request)
    try cancelFlag.check()
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200 ... 299).contains(status) else {
      throw VideoEditorTranscriptError.failed("HTTP \(status)")
    }
    progress?(.transcribing(fraction: 1))
    return TranscriptResult(words: try Self.parse(data))
  }

  func cancel() {
    cancelFlag.cancel()
  }
}

// MARK: - Request / response

extension RemoteTranscriptionEngine {
  /// `…/chat/completions` or a bare base URL → `…/v1/audio/transcriptions`.
  static func endpointURL(forBaseURL baseURL: String) -> URL? {
    var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    while normalized.hasSuffix("/") { normalized.removeLast() }
    guard !normalized.isEmpty else { return nil }
    if normalized.hasSuffix("/audio/transcriptions") { return URL(string: normalized) }
    if normalized.hasSuffix("/chat/completions") { normalized = String(normalized.dropLast("/chat/completions".count)) }
    if !normalized.hasSuffix("/v1") { normalized += "/v1" }
    return URL(string: normalized + "/audio/transcriptions")
  }

  static func fields(model: String, locale: Locale, prompt: String) -> [(String, String)] {
    var fields = [("model", model), ("response_format", "verbose_json"),
                  ("timestamp_granularities[]", "word"), ("timestamp_granularities[]", "segment")]
    if let language = locale.language.languageCode?.identifier { fields.append(("language", language)) }
    if !prompt.isEmpty { fields.append(("prompt", String(prompt.prefix(800)))) }
    return fields
  }

  static func multipartBody(boundary: String, fields: [(String, String)], file: Data, fileName: String) -> Data {
    var body = Data()
    func add(_ string: String) { body.append(Data(string.utf8)) }
    for (name, value) in fields {
      add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }
    add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: audio/mp4\r\n\r\n")
    body.append(file)
    add("\r\n--\(boundary)--\r\n")
    return body
  }

  /// Word timestamps when the server gives them, else its segments (one "word" per segment).
  static func parse(_ data: Data) throws -> [VideoEditorTranscriptWord] {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw VideoEditorTranscriptError.failed("unreadable response")
    }
    func items(_ key: String, text textKey: String) -> [VideoEditorTranscriptWord] {
      (object[key] as? [[String: Any]] ?? []).compactMap { item in
        guard let text = (item[textKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let start = (item["start"] as? NSNumber)?.doubleValue,
              let end = (item["end"] as? NSNumber)?.doubleValue else { return nil }
        return .init(start: start, duration: max(end - start, 0), text: text)
      }
    }
    let words = items("words", text: "word")
    return words.isEmpty ? items("segments", text: "text") : words
  }

  static func exportAudio(asset: AVAsset, tracks: [AVAssetTrack]) async throws -> URL {
    let composition = AVMutableComposition()
    let duration = try await asset.load(.duration)
    for track in tracks {
      guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
      try target.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
    }
    guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
      throw VideoEditorTranscriptError.failed("audio export")
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapzy-transcript-\(UUID().uuidString).m4a")
    export.outputURL = url
    export.outputFileType = .m4a
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      export.exportAsynchronously { continuation.resume() }
    }
    guard export.status == .completed else {
      throw export.error ?? VideoEditorTranscriptError.failed("audio export")
    }
    return url
  }
}
