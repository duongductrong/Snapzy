//
//  OCRModelDownloadServiceTests.swift
//  SnapzyTests
//
//  Download progress, verification, and cancellation coverage.
//

import CryptoKit
import XCTest
@testable import Snapzy

private final class ProgressRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [Double] = []

  var values: [Double] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func record(_ value: Double) {
    lock.lock()
    recorded.append(value)
    lock.unlock()
  }
}

final class OCRModelDownloadServiceTests: XCTestCase {
  private let detURL = URL(string: "https://models.example.com/det.onnx")!
  private let recURL = URL(string: "https://models.example.com/rec.onnx")!
  private let dictURL = URL(string: "https://models.example.com/dict.txt")!

  private var session: MockURLSession!
  private var workRoot: URL!
  private var installDir: URL!
  private var service: OCRModelDownloadService!

  override func setUp() {
    super.setUp()
    session = MockURLSession()
    workRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("OCRModelDownloadServiceTests-\(UUID().uuidString)", isDirectory: true)
    installDir = workRoot.appendingPathComponent("install", isDirectory: true)
    service = OCRModelDownloadService(session: session, stagingRoot: workRoot)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: workRoot)
    super.tearDown()
  }

  func testDownloadReportsMonotonicProgressAndInstallsFiles() async throws {
    let detData = Data(repeating: 0x01, count: 800)
    let recData = Data(repeating: 0x02, count: 1600)
    let dictData = makeDictData()
    let definition = makeDefinition(detData: detData, recData: recData, dictData: dictData)
    session.serveDownloads([
      detURL.absoluteString: detData,
      recURL.absoluteString: recData,
      dictURL.absoluteString: dictData,
    ])
    let recorder = ProgressRecorder()

    try await service.download(definition, to: installDir) { recorder.record($0) }

    let values = recorder.values
    XCTAssertFalse(values.isEmpty)
    XCTAssertEqual(values.last, 1.0)
    for (previous, next) in zip(values, values.dropFirst()) {
      XCTAssertGreaterThanOrEqual(next, previous)
    }
    for file in ["det.onnx", "rec.onnx", "dict.txt"] {
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: installDir.appendingPathComponent(file).path), file)
    }
    XCTAssertEqual(try Data(contentsOf: installDir.appendingPathComponent("dict.txt")), dictData)
    XCTAssertEqual(try Data(contentsOf: installDir.appendingPathComponent("det.onnx")), detData)
  }

  func testChecksumMismatchThrowsAndMovesNothing() async {
    let detData = Data(repeating: 0x01, count: 100)
    let recData = Data(repeating: 0x02, count: 100)
    let dictData = makeDictData()
    let definition = makeDefinition(
      detData: detData, recData: recData, dictData: dictData,
      detSHA256: String(repeating: "0", count: 64)
    )
    session.serveDownloads([
      detURL.absoluteString: detData,
      recURL.absoluteString: recData,
      dictURL.absoluteString: dictData,
    ])

    await assertDownloadFails(definition, expected: .checksumMismatch(file: "det.onnx"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path))
    XCTAssertTrue(stagingDirectories().isEmpty)
  }

  func testEmptyDictionaryThrowsInvalidDictionary() async {
    let detData = Data(repeating: 0x01, count: 100)
    let recData = Data(repeating: 0x02, count: 100)
    let definition = makeDefinition(detData: detData, recData: recData, dictData: Data())
    session.serveDownloads([
      detURL.absoluteString: detData,
      recURL.absoluteString: recData,
      dictURL.absoluteString: Data(),
    ])

    await assertDownloadFails(definition, expected: .invalidDictionary)
    XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path))
  }

  func testShortDictionaryThrowsInvalidDictionary() async {
    let detData = Data(repeating: 0x01, count: 100)
    let recData = Data(repeating: 0x02, count: 100)
    // 50 non-empty lines: valid UTF-8 but below the character-table minimum.
    let dictData = makeDictData(lines: 50)
    let definition = makeDefinition(detData: detData, recData: recData, dictData: dictData)
    session.serveDownloads([
      detURL.absoluteString: detData,
      recURL.absoluteString: recData,
      dictURL.absoluteString: dictData,
    ])

    await assertDownloadFails(definition, expected: .invalidDictionary)
    XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path))
  }

  func testNonUTF8DictionaryThrowsInvalidDictionary() async {
    let detData = Data(repeating: 0x01, count: 100)
    let recData = Data(repeating: 0x02, count: 100)
    let dictData = Data([0xFF, 0xFE, 0x00, 0x01, 0x80])
    let definition = makeDefinition(detData: detData, recData: recData, dictData: dictData)
    session.serveDownloads([
      detURL.absoluteString: detData,
      recURL.absoluteString: recData,
      dictURL.absoluteString: dictData,
    ])

    await assertDownloadFails(definition, expected: .invalidDictionary)
    XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path))
  }

  func testCancelThrowsCancelledAndCleansStaging() async throws {
    let definition = makeDefinition(
      detData: Data(repeating: 0x01, count: 10),
      recData: Data(repeating: 0x02, count: 10),
      dictData: Data("x\n".utf8)
    )
    session.downloadResponder = { _, _ in
      try await Task.sleep(nanoseconds: 5_000_000_000)
      throw OCRModelDownloadError.network("unreachable")
    }

    let task = Task {
      try await self.service.download(definition, to: installDir) { _ in }
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()

    do {
      try await task.value
      XCTFail("expected cancelled error")
    } catch let error as OCRModelDownloadError {
      XCTAssertEqual(error, .cancelled)
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertTrue(stagingDirectories().isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path))
  }

  /// Cancellation landing after the last file download (the verify/move
  /// window) must still win over the move into the install directory.
  func testCancelBetweenDownloadAndMoveThrowsCancelledAndInstallsNothing() async throws {
    let detData = Data(repeating: 0x01, count: 10)
    let recData = Data(repeating: 0x02, count: 10)
    let dictData = makeDictData()
    let definition = makeDefinition(detData: detData, recData: recData, dictData: dictData)
    let contents = [
      detURL.absoluteString: detData,
      recURL.absoluteString: recData,
      dictURL.absoluteString: dictData,
    ]
    let taskBox = TaskBox()
    session.downloadResponder = { url, _ in
      // Cancel while the last file is in flight; the pre-move check must fire.
      if url.absoluteString.hasSuffix("dict.txt") { taskBox.cancel() }
      guard let data = contents[url.absoluteString] else { throw URLError(.fileDoesNotExist) }
      let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try data.write(to: tempURL)
      return tempURL
    }

    let task = Task {
      try await self.service.download(definition, to: installDir) { _ in }
    }
    taskBox.task = task

    do {
      try await task.value
      XCTFail("expected cancelled error")
    } catch let error as OCRModelDownloadError {
      XCTAssertEqual(error, .cancelled)
    } catch {
      XCTFail("unexpected error: \(error)")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path))
  }

  // MARK: - Helpers

  /// Reference box so a download responder can cancel the running task.
  private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: Task<Void, Error>?

    var task: Task<Void, Error>? {
      get {
        lock.lock()
        defer { lock.unlock() }
        return _task
      }
      set {
        lock.lock()
        defer { lock.unlock() }
        _task = newValue
      }
    }

    func cancel() {
      task?.cancel()
    }
  }

  /// A dict.txt payload that passes the character-table validation.
  private func makeDictData(lines: Int = 120) -> Data {
    Data((0..<lines).map { "char\($0)" }.joined(separator: "\n").utf8)
  }

  private func makeDefinition(
    detData: Data,
    recData: Data,
    dictData: Data,
    detSHA256: String? = nil,
    recSHA256: String? = nil
  ) -> OCRModelDefinition {
    OCRModelDefinition(
      id: "test-model",
      displayName: "Test Model",
      parameterCountLabel: "1M",
      fp32SizeLabel: "1 MB",
      int8SizeLabel: "1 MB",
      files: [
        OCRModelFile(
          name: "det.onnx", url: detURL,
          expectedBytes: Int64(detData.count), sha256: detSHA256 ?? sha256Hex(detData)),
        OCRModelFile(
          name: "rec.onnx", url: recURL,
          expectedBytes: Int64(recData.count), sha256: recSHA256 ?? sha256Hex(recData)),
        OCRModelFile(name: "dict.txt", url: dictURL, expectedBytes: nil, sha256: nil),
      ]
    )
  }

  private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func assertDownloadFails(
    _ definition: OCRModelDefinition,
    expected: OCRModelDownloadError,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      try await service.download(definition, to: installDir) { _ in }
      XCTFail("expected \(expected)", file: file, line: line)
    } catch let error as OCRModelDownloadError {
      XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
      XCTFail("unexpected error: \(error)", file: file, line: line)
    }
  }

  private func stagingDirectories() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: workRoot.path))?
      .filter { $0.hasPrefix("SnapzyOCR-") } ?? []
  }
}
