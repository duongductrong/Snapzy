//
//  PPOCRSessionManager.swift
//  Snapzy
//
//  Shared ONNX Runtime environment and per-model PP-OCR session cache.
//

import Foundation
import OnnxRuntimeBindings

/// Errors raised before inference when a downloaded model is unusable.
enum PPOCRError: LocalizedError {
  case modelFilesMissing(modelID: String, file: String)

  var errorDescription: String? {
    switch self {
    case .modelFilesMissing(let modelID, let file):
      return "OCR model '\(modelID)' is missing '\(file)'. Re-download the model and try again."
    }
  }
}

/// Det/rec `ORTSession`s for one installed model plus its CTC dictionary.
struct PPOCRModelSessions {
  let det: ORTSession
  let rec: ORTSession
  let dictionary: [String]
  /// Which scripts `dictionary` can actually spell. PP-OCR substitutes the
  /// nearest in-dictionary glyph for anything it cannot represent, so partial
  /// coverage degrades silently instead of raising.
  let coverage: OCRScriptCoverageReport
}

/// Owns the shared `ORTEnv` and lazily-created sessions per installed model.
/// Thread-safe; callers are expected off the main actor (`PPOCRProvider` is
/// non-isolated, so session creation and inference never block the UI).
final class PPOCRSessionManager: @unchecked Sendable {
  static let shared = PPOCRSessionManager()

  private let lock = NSLock()
  private var cachedEnv: ORTEnv?
  private var cachedSessions: [String: PPOCRModelSessions] = [:]

  private init() {}

  /// Returns cached sessions for `modelID`, creating them on first use.
  /// Expects `directory` to contain `det.onnx`, `rec.onnx` and `dict.txt`.
  func sessions(modelID: String, directory: URL) throws -> PPOCRModelSessions {
    lock.lock()
    if let cached = cachedSessions[modelID] {
      lock.unlock()
      return cached
    }
    lock.unlock()

    let created = try createSessions(modelID: modelID, directory: directory)
    lock.lock()
    defer { lock.unlock() }
    if let raced = cachedSessions[modelID] {
      return raced
    }
    cachedSessions[modelID] = created
    return created
  }

  /// Drops cached sessions for a model (e.g. after the model is removed).
  func unload(modelID: String) {
    lock.lock()
    cachedSessions[modelID] = nil
    lock.unlock()
  }

  private func createSessions(modelID: String, directory: URL) throws -> PPOCRModelSessions {
    let detURL = directory.appendingPathComponent("det.onnx")
    let recURL = directory.appendingPathComponent("rec.onnx")
    let dictURL = directory.appendingPathComponent("dict.txt")
    for (file, url) in [("det.onnx", detURL), ("rec.onnx", recURL), ("dict.txt", dictURL)] {
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw PPOCRError.modelFilesMissing(modelID: modelID, file: file)
      }
    }

    let env = try sharedEnv()
    let options = try ORTSessionOptions()
    try options.setIntraOpNumThreads(Int32(max(2, ProcessInfo.processInfo.processorCount / 2)))
    let det = try ORTSession(env: env, modelPath: detURL.path, sessionOptions: options)
    let rec = try ORTSession(env: env, modelPath: recURL.path, sessionOptions: options)
    let dictionary = try Self.loadDictionary(from: dictURL)
    let coverage = OCRScriptCoverageReport.analyze(dictionary: dictionary)
    Self.logCoverage(modelID: modelID, coverage: coverage)
    return PPOCRModelSessions(det: det, rec: rec, dictionary: dictionary, coverage: coverage)
  }

  /// Logged once per model, when its sessions are first created.
  ///
  /// A dictionary gap has no runtime symptom other than plausible-looking text
  /// with characters quietly swapped out — the PP-OCRv6 dictionaries omit most
  /// of the Vietnamese tone block, which reads as an accuracy regression rather
  /// than a missing capability. Recording it here makes it diagnosable from a
  /// log alone.
  private static func logCoverage(modelID: String, coverage: OCRScriptCoverageReport) {
    var context = [
      "model": modelID,
      "characters": "\(coverage.characterCount)",
      "scripts": coverage.fullySupported.map(\.rawValue).joined(separator: ","),
    ]
    let incomplete = coverage.partiallySupported
    guard !incomplete.isEmpty else {
      DiagnosticLogger.shared.log(.info, .ocr, "PP-OCR dictionary loaded", context: context)
      return
    }
    context["incomplete"] = incomplete.map(\.rawValue).joined(separator: ",")
    DiagnosticLogger.shared.log(
      .warning,
      .ocr,
      "PP-OCR dictionary cannot spell every script it partially covers; affected text loses characters silently",
      context: context
    )
  }

  private func sharedEnv() throws -> ORTEnv {
    lock.lock()
    defer { lock.unlock() }
    if let cachedEnv { return cachedEnv }
    let env = try ORTEnv(loggingLevel: .warning)
    cachedEnv = env
    return env
  }

  /// Loads dict.txt: one character per line; model index n maps to line n-1
  /// (CTC blank occupies index 0). Appends " " like PaddleOCR's
  /// `use_space_char=True` — PP-OCR rec models are exported with a trailing
  /// space class (verified: tiny rec outputs 6906 = 6904 dict + blank + space).
  /// Harmless for models without it: the extra index is simply never emitted.
  static func loadDictionary(from url: URL) throws -> [String] {
    let content = try String(contentsOf: url, encoding: .utf8)
    var lines = content.components(separatedBy: "\n").map {
      $0.hasSuffix("\r") ? String($0.dropLast()) : $0
    }
    while lines.last == "" {
      lines.removeLast()
    }
    lines.append(" ")
    return lines
  }
}

/// Thin ORT run helper shared by det and rec: wraps a flat float tensor into
/// an `ORTValue`, runs the session's single input/output, reads back floats.
enum PPOCRTensorRunner {
  static func run(session: ORTSession, tensor: [Float], shape: [Int]) throws -> [Float] {
    let inputNames = try session.inputNames()
    let outputNames = try session.outputNames()
    guard let inputName = inputNames.first, let outputName = outputNames.first else {
      throw Self.malformedSessionError
    }
    let data = tensor.withUnsafeBufferPointer { buffer in
      NSMutableData(bytes: buffer.baseAddress, length: buffer.count * MemoryLayout<Float>.size)
    }
    let value = try ORTValue(
      tensorData: data,
      elementType: .float,
      shape: shape.map { NSNumber(value: $0) }
    )
    let outputs = try session.run(
      withInputs: [inputName: value],
      outputNames: Set([outputName]),
      runOptions: nil
    )
    guard let output = outputs[outputName] else {
      throw Self.malformedSessionError
    }
    let outputData = try output.tensorData() as Data
    return outputData.withUnsafeBytes { pointer in
      Array(pointer.bindMemory(to: Float.self))
    }
  }

  private static let malformedSessionError = OCRError.recognitionFailed(
    NSError(
      domain: "PPOCRTensorRunner",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "ONNX session exposes no input/output tensors"]
    )
  )
}
