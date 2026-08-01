//
//  OCRModelDownloadService.swift
//  Snapzy
//
//  Downloads, verifies, and installs downloadable OCR model files.
//

import CryptoKit
import Foundation

/// Download seam used by `OCRModelStore` so tests can fake installs.
protocol OCRModelDownloading: Sendable {
  /// Downloads all files of `definition` into `installDirectory`, reporting
  /// aggregate progress (0...1, monotonic, ends at 1.0).
  func download(
    _ definition: OCRModelDefinition,
    to installDirectory: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws
}

/// Typed failures surfaced by `OCRModelDownloadService`.
enum OCRModelDownloadError: LocalizedError, Equatable {
  case network(String)
  case checksumMismatch(file: String)
  case invalidDictionary
  case cancelled
  case io(String)

  var errorDescription: String? {
    switch self {
    case .network(let message):
      return "Model download failed: \(message)"
    case .checksumMismatch(let file):
      return "Checksum verification failed for \(file)."
    case .invalidDictionary:
      return "The downloaded dictionary file is empty or not a valid character table."
    case .cancelled:
      return "Model download cancelled."
    case .io(let message):
      return "Could not store the model files: \(message)"
    }
  }
}

/// Downloads a model's files sequentially into a staging directory, verifies
/// SHA256 checksums and the character dictionary, then moves everything into
/// the install directory. Cancelling aborts the download and cleans staging.
final class OCRModelDownloadService: OCRModelDownloading, @unchecked Sendable {
  private let session: URLSessionProtocol
  private let fileManager: FileManager
  private let stagingRoot: URL

  init(
    session: URLSessionProtocol = URLSession.shared,
    fileManager: FileManager = .default,
    stagingRoot: URL? = nil
  ) {
    self.session = session
    self.fileManager = fileManager
    self.stagingRoot = stagingRoot ?? fileManager.temporaryDirectory
  }

  func download(
    _ definition: OCRModelDefinition,
    to installDirectory: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    let staging = stagingRoot
      .appendingPathComponent("SnapzyOCR-\(definition.id)-\(UUID().uuidString)", isDirectory: true)
    do {
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    } catch {
      throw OCRModelDownloadError.io(error.localizedDescription)
    }
    defer { try? fileManager.removeItem(at: staging) }

    try await downloadFiles(of: definition, to: staging, progress: progress)
    try verifyFiles(of: definition, in: staging)
    // A cancel/remove landing during download or verification wins over the move.
    if Task.isCancelled { throw OCRModelDownloadError.cancelled }
    try moveFiles(of: definition, from: staging, to: installDirectory)
  }

  // MARK: - Download

  private func downloadFiles(
    of definition: OCRModelDefinition,
    to staging: URL,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    // Weight each file by its expected size; unknown sizes count as 1 byte.
    let weights = definition.files.map { max($0.expectedBytes ?? 1, 1) }
    let total = Double(weights.reduce(0, +))
    var completed: Int64 = 0

    for (index, file) in definition.files.enumerated() {
      if Task.isCancelled { throw OCRModelDownloadError.cancelled }
      let stagedURL = staging.appendingPathComponent(file.name)
      let tempURL = try await download(file, weight: weights[index], completed: completed, total: total, progress: progress)
      do {
        try fileManager.moveItem(at: tempURL, to: stagedURL)
      } catch {
        throw OCRModelDownloadError.io(error.localizedDescription)
      }
      completed += weights[index]
      progress(min(Double(completed) / total, 1.0))
    }
  }

  private func download(
    _ file: OCRModelFile,
    weight: Int64,
    completed: Int64,
    total: Double,
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> URL {
    do {
      return try await session.download(from: file.url) { fraction in
        let current = Double(completed) + Double(weight) * fraction
        progress(min(current / total, 1.0))
      }
    } catch let error as URLError where error.code == .cancelled {
      throw OCRModelDownloadError.cancelled
    } catch is CancellationError {
      throw OCRModelDownloadError.cancelled
    } catch {
      throw OCRModelDownloadError.network(error.localizedDescription)
    }
  }

  // MARK: - Verification

  private func verifyFiles(of definition: OCRModelDefinition, in staging: URL) throws {
    for file in definition.files {
      let url = staging.appendingPathComponent(file.name)
      guard fileManager.fileExists(atPath: url.path) else {
        throw OCRModelDownloadError.io("Missing downloaded file \(file.name)")
      }
      if let expectedSHA256 = file.sha256 {
        let actualSHA256 = try sha256Hex(of: url)
        guard actualSHA256 == expectedSHA256 else {
          throw OCRModelDownloadError.checksumMismatch(file: file.name)
        }
      }
      if file.name == "dict.txt" { try verifyDictionary(at: url) }
    }
  }

  /// dict.txt must be UTF-8 with >= 100 non-empty lines; rejects truncated
  /// downloads and HTML error pages saved as the dictionary.
  private func verifyDictionary(at url: URL) throws {
    let content = try? String(contentsOf: url, encoding: .utf8)
    let nonEmptyLines = content?.components(separatedBy: .newlines)
      .count { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? 0
    guard nonEmptyLines >= 100 else { throw OCRModelDownloadError.invalidDictionary }
  }

  private func sha256Hex(of url: URL) throws -> String {
    guard let stream = InputStream(url: url) else {
      throw OCRModelDownloadError.io("Cannot read \(url.lastPathComponent)")
    }
    stream.open()
    defer { stream.close() }

    var hasher = SHA256()
    var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read < 0 {
        throw OCRModelDownloadError.io(stream.streamError?.localizedDescription ?? "Read failed")
      }
      if read == 0 { break }
      buffer.withUnsafeBytes { rawBuffer in
        hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: rawBuffer.prefix(read)))
      }
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - Install

  private func moveFiles(of definition: OCRModelDefinition, from staging: URL, to installDirectory: URL) throws {
    do {
      if fileManager.fileExists(atPath: installDirectory.path) {
        try fileManager.removeItem(at: installDirectory)
      }
      try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)
      for file in definition.files {
        try fileManager.moveItem(
          at: staging.appendingPathComponent(file.name),
          to: installDirectory.appendingPathComponent(file.name)
        )
      }
    } catch {
      throw OCRModelDownloadError.io(error.localizedDescription)
    }
  }
}
