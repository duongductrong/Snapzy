//
//  OutputTests.swift
//  SnapzyCLICoreTests
//

@testable import SnapzyCLICore
@testable import SnapzyCLIProtocol
import XCTest

final class OutputRendererTests: XCTestCase {
  func testMode_jsonWhenPiped_prettyOnlyWhenAskedOnTerminal() {
    XCTAssertEqual(OutputRenderer.mode(jsonFlag: false, stdoutIsTerminal: false), .json(pretty: false))
    XCTAssertEqual(OutputRenderer.mode(jsonFlag: true, stdoutIsTerminal: false), .json(pretty: false))
    XCTAssertEqual(OutputRenderer.mode(jsonFlag: true, stdoutIsTerminal: true), .json(pretty: true))
    XCTAssertEqual(OutputRenderer.mode(jsonFlag: false, stdoutIsTerminal: true), .human)
  }

  func testRenderError_jsonAndHuman() {
    let error = CLIError(.notAuthorized, "Terminal is not allowed", hint: "Approve it in Snapzy")

    XCTAssertEqual(
      OutputRenderer(mode: .json(pretty: false)).render(error: error),
      #"{"error":{"code":"notAuthorized","hint":"Approve it in Snapzy","message":"Terminal is not allowed"}}"# + "\n"
    )
    XCTAssertEqual(
      OutputRenderer(mode: .human).render(error: error),
      "error: Terminal is not allowed\nhint: Approve it in Snapzy\n"
    )
  }

  func testRenderValue_humanWindowList() throws {
    let list = CLIWindowList(windows: [
      CLIWindow(
        id: 42,
        title: "README.md",
        app: CLIWindowOwner(name: "Code", bundleID: "com.microsoft.VSCode", pid: 7),
        frame: CLIRect(x: 0, y: 25, width: 1200, height: 800),
        displayID: 1,
        isOnScreen: true,
        isActive: true
      ),
    ])

    XCTAssertEqual(
      try OutputRenderer(mode: .human).render(list),
      "42  Code — README.md  0,25,1200,800  active\n"
    )
  }
}

final class OutputWriterTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyCLIKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private func stagedResult(count: Int = 1) throws -> CLICaptureResult {
    let staging = directory.appendingPathComponent("staging", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let files = try (0 ..< count).map { index -> CLICapturedFile in
      let url = staging.appendingPathComponent("snapzy-cli-\(index).png")
      try Data("image-\(index)".utf8).write(to: url)
      return CLICapturedFile(path: url.path, format: .png, width: 10, height: 10, scale: 1, bytes: 7)
    }
    return CLICaptureResult(files: files, durationMs: 1)
  }

  private func apply(
    _ result: CLICaptureResult,
    _ argument: String?,
    force: Bool = false,
    stdout: (Data) throws -> Void = { _ in XCTFail("unexpected stdout") }
  ) throws -> CLICaptureResult {
    let destination = OutputDestination.resolve(argument, currentDirectory: directory)
    return try OutputWriter().apply(result, to: destination, force: force, writeStandardOutput: stdout)
  }

  func testResolve() {
    XCTAssertEqual(OutputDestination.resolve(nil, currentDirectory: directory), .staging)
    XCTAssertEqual(OutputDestination.resolve("-", currentDirectory: directory), .standardOutput)
    XCTAssertEqual(
      OutputDestination.resolve("out/", currentDirectory: directory),
      .directory(URL(
        fileURLWithPath: directory.appendingPathComponent("out").standardizedFileURL.path,
        isDirectory: true
      ))
    )
    XCTAssertEqual(
      OutputDestination.resolve(directory.path, currentDirectory: URL(fileURLWithPath: "/")),
      .directory(URL(fileURLWithPath: directory.standardizedFileURL.path, isDirectory: true))
    )
    XCTAssertEqual(
      OutputDestination.resolve("a/b.png", currentDirectory: directory),
      .file(directory.appendingPathComponent("a/b.png").standardizedFileURL)
    )
  }

  func testStaging_leavesResultUntouched() throws {
    let result = try stagedResult()
    XCTAssertEqual(try apply(result, nil), result)
  }

  func testFile_movesAndCreatesParents() throws {
    let written = try apply(stagedResult(), "nested/dir/shot.png")
    let target = directory.appendingPathComponent("nested/dir/shot.png").standardizedFileURL

    XCTAssertEqual(written.files.map(\.path), [target.path])
    XCTAssertEqual(try Data(contentsOf: target), Data("image-0".utf8))
  }

  func testFile_refusesOverwriteWithoutForce() throws {
    let target = directory.appendingPathComponent("shot.png")
    try Data("old".utf8).write(to: target)

    XCTAssertThrowsError(try apply(stagedResult(), "shot.png")) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
    }
    XCTAssertEqual(try Data(contentsOf: target), Data("old".utf8))

    _ = try apply(stagedResult(), "shot.png", force: true)
    XCTAssertEqual(try Data(contentsOf: target), Data("image-0".utf8))
  }

  func testFile_multipleCapturesGetNumberedNames() throws {
    let written = try apply(stagedResult(count: 2), "shot.png")

    XCTAssertEqual(
      written.files.map { URL(fileURLWithPath: $0.path).lastPathComponent },
      ["shot-1.png", "shot-2.png"]
    )
  }

  func testDirectory_keepsStagingNames() throws {
    let written = try apply(stagedResult(count: 2), "out/")

    XCTAssertEqual(
      written.files.map(\.path),
      ["snapzy-cli-0.png", "snapzy-cli-1.png"].map {
        directory.appendingPathComponent("out").appendingPathComponent($0).standardizedFileURL.path
      }
    )
  }

  func testStandardOutput_streamsSingleFile() throws {
    var streamed = Data()
    let result = try stagedResult()

    let written = try apply(result, "-") { streamed.append($0) }

    XCTAssertEqual(streamed, Data("image-0".utf8))
    XCTAssertEqual(written.files.map(\.path), ["-"])
    XCTAssertFalse(FileManager.default.fileExists(atPath: result.files[0].path))
  }

  func testStandardOutput_rejectsMultipleFiles() throws {
    XCTAssertThrowsError(try apply(stagedResult(count: 2), "-")) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
    }
  }

  func testPreflight_rejectsExistingFileBeforeCapture() throws {
    let target = directory.appendingPathComponent("shot.png")
    try Data("old".utf8).write(to: target)
    let writer = OutputWriter()

    XCTAssertThrowsError(try writer.preflight(.file(target), force: false)) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
    }
    XCTAssertNoThrow(try writer.preflight(.file(target), force: true))
    XCTAssertNoThrow(try writer.preflight(.file(directory.appendingPathComponent("new.png")), force: false))
    XCTAssertNoThrow(try writer.preflight(.directory(directory), force: false))
  }

  func testExistingTargetErrorPointsAtStagedCapture() throws {
    let result = try stagedResult(count: 2)
    try Data("old".utf8).write(to: directory.appendingPathComponent("shot-2.png"))

    XCTAssertThrowsError(try apply(result, "shot.png")) { error in
      let hint = (error as? CLIError)?.hint ?? ""
      XCTAssertTrue(hint.contains("--force"), hint)
      XCTAssertTrue(hint.contains(result.files[1].path), hint)
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: result.files[0].path))
  }

  func testForce_replacesWithoutLeavingTemporaryFiles() throws {
    let target = directory.appendingPathComponent("shot.png")
    try Data("old".utf8).write(to: target)

    _ = try apply(stagedResult(), "shot.png", force: true)

    XCTAssertEqual(try Data(contentsOf: target), Data("image-0".utf8))
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.contains("snapzy-") }
    XCTAssertEqual(leftovers, [])
  }
}
