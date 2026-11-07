//
//  MeasureCommandTests.swift
//  SnapzyCLICoreTests
//
//  `snapzy measure`: parsing, the pure runner on synthetic images, JSON and
//  text output, file errors, and the capture path with a fake capture.
//

import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
@testable import SnapzyCLICore
@testable import SnapzyCLIProtocol
import SnapzyMeasureCore
import UniformTypeIdentifiers
import XCTest

/// 200×100 px white image with a blue card at pixels x 40…119, y 20…59 (80×40 px).
private enum MeasureFixture {
  static let width = 200
  static let height = 100
  static let card = (minX: 40, minY: 20, maxX: 119, maxY: 59)

  static var image: CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in card.minY ... card.maxY {
      for x in card.minX ... card.maxX {
        let offset = (y * width + x) * 4
        bytes[offset] = 0
        bytes[offset + 1] = 102
        bytes[offset + 2] = 255
      }
    }
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: CGDataProvider(data: Data(bytes) as CFData)!,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )!
  }

  /// Writes the fixture as PNG; `dpi` 144 makes it a 2× image.
  static func writePNG(to url: URL, dpi: Double? = nil) throws {
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    )
    let properties = dpi.map { [kCGImagePropertyDPIWidth: $0, kCGImagePropertyDPIHeight: $0] as CFDictionary }
    CGImageDestinationAddImage(destination, image, properties)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }
}

// MARK: - Parsing

final class MeasureParsingTests: XCTestCase {
  private func parse<Command: ParsableCommand>(_: Command.Type, _ arguments: [String]) throws -> Command {
    let command = try SnapzyCommand.parseAsRoot(arguments)
    return try XCTUnwrap(command as? Command, "parsed \(Swift.type(of: command))")
  }

  private func assertUsageError(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try SnapzyCommand.parseAsRoot(arguments), file: file, line: line) { error in
      XCTAssertEqual(SnapzyCommand.exitCode(for: error), .validationFailure, file: file, line: line)
    }
  }

  func testImage_repeatableTargetsAndNegatives() throws {
    let command = try parse(
      MeasureImageCommand.self,
      [
        "measure", "image", "shot.png",
        "--at", "120,80", "--at", "-5,10", "--at=-1,-2",
        "--box", "0,0,400,100", "--box", "-10,-10,20,20",
        "--axis", "horizontal", "--tolerance", "0", "--no-snap", "--pixels", "--scale", "1.5",
      ]
    )

    XCTAssertEqual(command.path, "shot.png")
    XCTAssertEqual(command.scale, 1.5)
    XCTAssertEqual(
      command.measure.request,
      MeasureRequest(
        points: [CLIPoint(x: 120, y: 80), CLIPoint(x: -5, y: 10), CLIPoint(x: -1, y: -2)],
        boxes: [CLIRect(x: 0, y: 0, width: 400, height: 100), CLIRect(x: -10, y: -10, width: 20, height: 20)],
        axis: .horizontal,
        tolerance: 0,
        snap: false,
        inputsArePixels: true
      )
    )
  }

  func testImage_defaults() throws {
    let command = try parse(MeasureImageCommand.self, ["measure", "image", "shot.png", "--box", "0,0,10,10"])

    XCTAssertNil(command.scale)
    XCTAssertEqual(
      command.measure.request,
      MeasureRequest(boxes: [CLIRect(x: 0, y: 0, width: 10, height: 10)], axis: .both, tolerance: 3, snap: true)
    )
  }

  func testImage_rejectsBadOptions() {
    assertUsageError(["measure", "image", "shot.png"])
    assertUsageError(["measure", "image", "--at", "1,1"])
    assertUsageError(["measure", "image", "shot.png", "--at", "1"])
    assertUsageError(["measure", "image", "shot.png", "--at", "1,2,3"])
    assertUsageError(["measure", "image", "shot.png", "--box", "0,0,0,10"])
    assertUsageError(["measure", "image", "shot.png", "--at", "1,1", "--tolerance", "65"])
    assertUsageError(["measure", "image", "shot.png", "--at", "1,1", "--tolerance", "-1"])
    assertUsageError(["measure", "image", "shot.png", "--at", "1,1", "--axis", "diagonal"])
    assertUsageError(["measure", "image", "shot.png", "--at", "1,1", "--scale", "0"])
  }

  func testCapture_sharesSelectorsWithCaptureCommands() throws {
    let window = try parse(
      MeasureWindowCommand.self,
      [
        "measure",
        "window",
        "--app",
        "Safari",
        "--title",
        "^Docs",
        "--index",
        "1",
        "--at",
        "24,180",
        "--box",
        "0,0,800,60",
      ]
    )
    let screen = try parse(MeasureScreenCommand.self, ["measure", "screen", "--display", "7", "--at", "1,1"])
    let area = try parse(MeasureAreaCommand.self, ["measure", "area", "--rect", "-1440,0,600,400", "--at", "50,50"])

    XCTAssertEqual(
      try window.selection.selector(),
      .app(AppWindowQuery(app: "Safari", titlePattern: "^Docs", index: 1))
    )
    XCTAssertEqual(window.measure.points, [CLIPoint(x: 24, y: 180)])
    XCTAssertEqual(window.measure.boxes, [CLIRect(x: 0, y: 0, width: 800, height: 60)])
    XCTAssertEqual(screen.selection.display, .id(7))
    XCTAssertEqual(try parse(MeasureScreenCommand.self, ["measure", "screen", "--at", "1,1"]).selection.display, .main)
    XCTAssertEqual(area.selection.rect, CLIRect(x: -1440, y: 0, width: 600, height: 400))
  }

  func testCapture_rejectsBadOptions() {
    assertUsageError(["measure", "screen", "--display", "all", "--at", "1,1"])
    assertUsageError(["measure", "screen"])
    assertUsageError(["measure", "window", "--at", "1,1"])
    assertUsageError(["measure", "window", "--id", "1", "--active", "--at", "1,1"])
    assertUsageError(["measure", "area", "--at", "1,1"])
    assertUsageError(["measure", "area", "--rect", "0,0,10,10", "--at", "1,1", "--keep", "-"])
    // Capture-only flags do not leak into measure.
    assertUsageError(["measure", "window", "--active", "--at", "1,1", "--no-shadow"])
    assertUsageError(["measure", "screen", "--at", "1,1", "--format", "jpg"])
  }

  func testCapture_keepAndForce() throws {
    let command = try parse(
      MeasureAreaCommand.self,
      ["measure", "area", "--rect", "0,0,10,10", "--at", "1,1", "--keep", "out/", "--force"]
    )

    XCTAssertEqual(command.keep.keep, "out/")
    XCTAssertTrue(command.keep.force)
    XCTAssertNil(try parse(MeasureAreaCommand.self, ["measure", "area", "--rect", "0,0,10,10", "--at", "1,1"]).keep
      .keep)
  }

  func testCaptureOptionsAreFixedForMeasuring() {
    XCTAssertEqual(
      MeasureCapture.captureOptions,
      CaptureOptions(format: .png, quality: nil, maxDimension: nil, showCursor: false, windowShadow: false)
    )
  }

  func testUsageHintStopsAtSubcommands() {
    XCTAssertEqual(
      SnapzyCommand.subcommandPath(in: ["measure", "image", "shot.png", "--at", "1"]),
      ["measure", "image"]
    )
    XCTAssertEqual(SnapzyCommand.subcommandPath(in: ["list", "windows", "--app", "x"]), ["list", "windows"])
    XCTAssertEqual(SnapzyCommand.subcommandPath(in: ["bogus"]), [])
  }
}

// MARK: - Runner

final class MeasureRunnerTests: XCTestCase {
  private let image = MeasureFixture.image

  private func measure(scale: Double, _ request: MeasureRequest) throws -> [CLIMeasurement] {
    try MeasureRunner.measure(image: image, scale: scale, request: request)
  }

  private func extent(_ width: Double?, _ height: Double?, _ x: Double, _ y: Double, _ w: Double, _ h: Double)
    -> CLIMeasureExtent {
    CLIMeasureExtent(width: width, height: height, rect: CLIRect(x: x, y: y, width: w, height: h))
  }

  func testSpan_scale1() throws {
    let at = CLIPoint(x: 50, y: 30)

    XCTAssertEqual(
      try measure(scale: 1, MeasureRequest(points: [at])),
      [.span(at: at, axis: .both, points: extent(80, 40, 40, 20, 80, 40), pixels: extent(80, 40, 40, 20, 80, 40))]
    )
  }

  func testSpan_scale2_pointsAreHalfThePixels() throws {
    let at = CLIPoint(x: 25, y: 15)

    XCTAssertEqual(
      try measure(scale: 2, MeasureRequest(points: [at])),
      [.span(at: at, axis: .both, points: extent(40, 20, 20, 10, 40, 20), pixels: extent(80, 40, 40, 20, 80, 40))]
    )
  }

  func testSpan_pixelInputsAtScale2() throws {
    let at = CLIPoint(x: 50, y: 30)
    let result = try measure(scale: 2, MeasureRequest(points: [at], inputsArePixels: true))

    XCTAssertEqual(result.first?.pixels, extent(80, 40, 40, 20, 80, 40))
    XCTAssertEqual(result.first?.points, extent(40, 20, 20, 10, 40, 20))
  }

  func testSpan_singleAxisLeavesOtherNil() throws {
    let at = CLIPoint(x: 50, y: 30)
    let horizontal = try measure(scale: 1, MeasureRequest(points: [at], axis: .horizontal))
    let vertical = try measure(scale: 1, MeasureRequest(points: [at], axis: .vertical))

    XCTAssertEqual(horizontal.first?.pixels, extent(80, nil, 40, 30, 80, 1))
    XCTAssertEqual(vertical.first?.pixels, extent(nil, 40, 50, 20, 1, 40))
  }

  func testSpan_fractionalScaleRoundsToThreeDecimals() throws {
    let result = try measure(scale: 3, MeasureRequest(points: [CLIPoint(x: 20, y: 10)]))

    XCTAssertEqual(result.first?.points.width, 26.667)
    XCTAssertEqual(result.first?.points.height, 13.333)
  }

  func testBox_snapsToContent() throws {
    let box = CLIRect(x: 0, y: 0, width: 200, height: 100)

    XCTAssertEqual(
      try measure(scale: 1, MeasureRequest(boxes: [box])),
      [.box(input: box, snapped: true, points: extent(80, 40, 40, 20, 80, 40), pixels: extent(80, 40, 40, 20, 80, 40))]
    )
  }

  func testBox_noSnapAndClampingAtScale2() throws {
    let inside = CLIRect(x: 10, y: 5, width: 20, height: 10)
    let overhanging = CLIRect(x: 90, y: 40, width: 50, height: 50)
    let result = try measure(scale: 2, MeasureRequest(boxes: [inside, overhanging], snap: false))

    XCTAssertEqual(result[0].pixels, extent(40, 20, 20, 10, 40, 20))
    XCTAssertEqual(result[0].points, extent(20, 10, 10, 5, 20, 10))
    XCTAssertEqual(result[1].points, extent(10, 10, 90, 40, 10, 10))
  }

  func testSpansComeBeforeBoxes() throws {
    let result = try measure(
      scale: 1,
      MeasureRequest(points: [CLIPoint(x: 5, y: 5)], boxes: [CLIRect(x: 0, y: 0, width: 200, height: 100)])
    )

    guard case .span = result[0], case .box = result[1] else {
      return XCTFail("unexpected order \(result)")
    }
  }

  func testOutOfBoundsIsInvalidArgumentsWithImageSize() throws {
    for request in [
      MeasureRequest(points: [CLIPoint(x: 100, y: 10)]),
      MeasureRequest(points: [CLIPoint(x: -0.5, y: 10)]),
      MeasureRequest(boxes: [CLIRect(x: 100, y: 0, width: 10, height: 10)]),
      MeasureRequest(boxes: [CLIRect(x: -20, y: 0, width: 20, height: 10)]),
    ] {
      XCTAssertThrowsError(try measure(scale: 2, request)) { error in
        let error = error as? CLIError
        XCTAssertEqual(error?.code, .invalidArguments)
        XCTAssertEqual(
          error?.hint,
          "The image is 100 × 50 pt (200 × 100 px, scale 2); coordinates are points from its top-left corner"
        )
      }
    }
    XCTAssertNoThrow(try measure(scale: 2, MeasureRequest(points: [CLIPoint(x: 99.9, y: 49.9)])))
  }
}

// MARK: - Output

final class MeasureOutputTests: XCTestCase {
  private let result = CLIMeasureResult(
    source: CLIMeasureSource(kind: .image, path: "/tmp/shot.png", width: 200, height: 100, scale: 2),
    tolerance: 3,
    measurements: [
      .span(
        at: CLIPoint(x: 25, y: 15),
        axis: .horizontal,
        points: CLIMeasureExtent(width: 40.5, height: nil, rect: CLIRect(x: 20, y: 15, width: 40.5, height: 0.5)),
        pixels: CLIMeasureExtent(width: 81, height: nil, rect: CLIRect(x: 40, y: 30, width: 81, height: 1))
      ),
      .box(
        input: CLIRect(x: 0, y: 0, width: 100, height: 50),
        snapped: true,
        points: CLIMeasureExtent(width: 40, height: 20, rect: CLIRect(x: 20, y: 10, width: 40, height: 20)),
        pixels: CLIMeasureExtent(width: 80, height: 40, rect: CLIRect(x: 40, y: 20, width: 80, height: 40))
      ),
    ]
  )

  func testJSON_golden() throws {
    let json = try OutputRenderer(mode: .json(pretty: false)).render(result)

    XCTAssertEqual(
      json,
      #"{"measurements":[{"at":{"x":25,"y":15},"axis":"horizontal","kind":"span","#
        + #""pixels":{"height":null,"rect":{"height":1,"width":81,"x":40,"y":30},"width":81},"#
        + #""points":{"height":null,"rect":{"height":0.5,"width":40.5,"x":20,"y":15},"width":40.5}},"#
        + #"{"input":{"height":50,"width":100,"x":0,"y":0},"kind":"box","#
        + #""pixels":{"height":40,"rect":{"height":40,"width":80,"x":40,"y":20},"width":80},"#
        + #""points":{"height":20,"rect":{"height":20,"width":40,"x":20,"y":10},"width":40},"snapped":true}],"#
        + #""source":{"height":100,"kind":"image","path":"/tmp/shot.png","scale":2,"width":200},"tolerance":3}"#
        + "\n"
    )
  }

  func testJSON_captureSourceCarriesWindow() throws {
    let window = CLIWindow(
      id: 42,
      title: "Docs",
      app: CLIWindowOwner(name: "Safari", bundleID: "com.apple.Safari", pid: 7),
      frame: CLIRect(x: 0, y: 25, width: 800, height: 600),
      displayID: 1,
      isOnScreen: true,
      isActive: true
    )
    let source = CLIMeasureSource(
      kind: .window,
      path: nil,
      width: 1600,
      height: 1200,
      scale: 2,
      displayID: 1,
      window: window
    )
    let json = try OutputRenderer.json(source, pretty: false)

    XCTAssertTrue(
      json.hasPrefix(#"{"displayID":1,"height":1200,"kind":"window","scale":2,"width":1600,"window":{"#),
      json
    )
    XCTAssertFalse(json.contains("path"), json)
  }

  func testHuman_oneLinePerMeasurement() throws {
    XCTAssertEqual(
      try OutputRenderer(mode: .human).render(result),
      """
      span @25,15  40.5 pt  (81 px)
      box 0,0,100,50 → 20,10,40,20  40 × 20 pt  (80 × 40 px)

      """
    )
  }
}

// MARK: - Files and captures

final class MeasureSessionTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SnapzyMeasureTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private let span = MeasureRequest(points: [CLIPoint(x: 25, y: 15)])

  // MARK: measure image

  func testImage_relativePathAndDPIScale() throws {
    try MeasureFixture.writePNG(to: directory.appendingPathComponent("shot@2x.png"), dpi: 144)

    let result = try MeasureSession.measureImage(
      path: "shot@2x.png",
      currentDirectory: directory,
      request: span,
      scale: nil
    )

    XCTAssertEqual(result.source.kind, .image)
    XCTAssertEqual(result.source.path, directory.appendingPathComponent("shot@2x.png").standardizedFileURL.path)
    XCTAssertEqual([result.source.width, result.source.height], [200, 100])
    XCTAssertEqual(result.source.scale, 2)
    XCTAssertEqual(result.tolerance, 3)
    XCTAssertEqual(result.measurements.first?.points.width, 40)
  }

  func testImage_scaleOverride() throws {
    try MeasureFixture.writePNG(to: directory.appendingPathComponent("shot.png"), dpi: 144)

    let result = try MeasureSession.measureImage(
      path: directory.appendingPathComponent("shot.png").path,
      currentDirectory: URL(fileURLWithPath: "/"),
      request: MeasureRequest(points: [CLIPoint(x: 50, y: 30)]),
      scale: 1
    )

    XCTAssertEqual(result.source.scale, 1)
    XCTAssertEqual(result.measurements.first?.points.width, 80)
  }

  func testImage_errorCodes() throws {
    try Data("not an image".utf8).write(to: directory.appendingPathComponent("notes.png"))
    try MeasureFixture.writePNG(to: directory.appendingPathComponent("big.png"))

    XCTAssertThrowsError(
      try MeasureSession.measureImage(path: "missing.png", currentDirectory: directory, request: span, scale: nil)
    ) { error in
      XCTAssertEqual((error as? CLIError)?.code, .targetNotFound)
      XCTAssertEqual(CLIErrorCode.targetNotFound.exitCode, 4)
    }
    XCTAssertThrowsError(
      try MeasureSession.measureImage(path: "notes.png", currentDirectory: directory, request: span, scale: nil)
    ) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
    }
    XCTAssertThrowsError(try MeasureSession.load(
      directory.appendingPathComponent("big.png"),
      maxPixels: 10_000
    )) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
      XCTAssertEqual((error as? CLIError)?.message, "The image is 200×100 pixels, over the 0.01 megapixel limit")
    }
  }

  func testResolve_expandsTilde() {
    XCTAssertEqual(
      MeasureSession.resolve("~/shot.png", currentDirectory: directory).path,
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("shot.png").standardizedFileURL.path
    )
  }

  // MARK: measure screen|window|area

  private func stagedCapture(count: Int = 1, window: CLIWindow? = nil) throws -> CLICaptureResult {
    let staging = directory.appendingPathComponent("staging", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let files = try (0 ..< count).map { index -> CLICapturedFile in
      let url = staging.appendingPathComponent("snapzy-cli-\(index).png")
      try MeasureFixture.writePNG(to: url)
      return CLICapturedFile(
        path: url.path, format: .png, width: 200, height: 100, scale: 2, bytes: 1, displayID: 3, window: window
      )
    }
    return CLICaptureResult(files: files, durationMs: 1)
  }

  func testCapture_measuresAtCaptureScaleAndDeletesStagedFile() throws {
    let capture = try stagedCapture()

    let result = try MeasureSession.measureCapture(kind: .screen, request: span, keep: nil, force: false) { capture }

    XCTAssertEqual(
      result.source,
      CLIMeasureSource(kind: .screen, path: nil, width: 200, height: 100, scale: 2, displayID: 3)
    )
    XCTAssertEqual(result.measurements.first?.points, CLIMeasureExtent(
      width: 40, height: 20, rect: CLIRect(x: 20, y: 10, width: 40, height: 20)
    ))
    XCTAssertFalse(FileManager.default.fileExists(atPath: capture.files[0].path))
  }

  func testCapture_keepMovesFileAndReportsPath() throws {
    let capture = try stagedCapture()
    let target = directory.appendingPathComponent("kept/window.png")

    let result = try MeasureSession.measureCapture(
      kind: .window, request: span, keep: .file(target), force: false
    ) { capture }

    XCTAssertEqual(result.source.path, target.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: capture.files[0].path))
  }

  func testCapture_keepHonorsForce() throws {
    let target = directory.appendingPathComponent("window.png")
    try Data("old".utf8).write(to: target)

    let first = try stagedCapture()
    XCTAssertThrowsError(
      try MeasureSession.measureCapture(kind: .window, request: span, keep: .file(target), force: false) { first }
    ) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
    }
    XCTAssertEqual(try Data(contentsOf: target), Data("old".utf8))

    let second = try stagedCapture()
    _ = try MeasureSession.measureCapture(kind: .window, request: span, keep: .file(target), force: true) { second }
    XCTAssertNotEqual(try Data(contentsOf: target), Data("old".utf8))
  }

  func testCapture_outOfBoundsDeletesStagedFileUnlessKept() throws {
    let outside = MeasureRequest(points: [CLIPoint(x: 500, y: 0)])
    let capture = try stagedCapture()

    XCTAssertThrowsError(
      try MeasureSession.measureCapture(kind: .area, request: outside, keep: nil, force: false) { capture }
    ) { error in
      XCTAssertEqual((error as? CLIError)?.code, .invalidArguments)
      XCTAssertTrue((error as? CLIError)?.hint?.contains("100 × 50 pt") == true)
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: capture.files[0].path))

    let kept = directory.appendingPathComponent("kept.png")
    _ = try? MeasureSession.measureCapture(kind: .area, request: outside, keep: .file(kept), force: false) {
      try stagedCapture()
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
  }

  func testCapture_errorsPassThroughUnchanged() {
    let busy = CLIError(.busy, "Snapzy is already capturing", hint: "Retry")

    XCTAssertThrowsError(
      try MeasureSession.measureCapture(kind: .screen, request: span, keep: nil, force: false) { throw busy }
    ) { error in
      XCTAssertEqual(error as? CLIError, busy)
    }
  }

  func testCapture_windowSourceAndMultipleFiles() throws {
    let window = CLIWindow(
      id: 9,
      title: nil,
      app: CLIWindowOwner(name: "Finder", bundleID: "com.apple.finder", pid: 1),
      frame: CLIRect(x: 0, y: 0, width: 100, height: 50),
      displayID: 3,
      isOnScreen: true,
      isActive: false
    )
    let single = try stagedCapture(window: window)
    let result = try MeasureSession.measureCapture(kind: .window, request: span, keep: nil, force: false) { single }
    XCTAssertEqual(result.source.window, window)

    let several = try stagedCapture(count: 2)
    XCTAssertThrowsError(
      try MeasureSession.measureCapture(kind: .screen, request: span, keep: nil, force: false) { several }
    ) { error in
      XCTAssertEqual((error as? CLIError)?.code, .internal)
    }
    XCTAssertTrue(several.files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
  }

  // MARK: - Review regressions

  func testNumberText_hugeValuesDoNotTrap() {
    XCTAssertEqual(CLIMeasureNumber.text(12), "12")
    XCTAssertEqual(CLIMeasureNumber.text(1234.5674), "1234.567")
    XCTAssertFalse(CLIMeasureNumber.text(1e30).isEmpty)
  }

  func testKeep_rejectsNonPNGFileNames() throws {
    XCTAssertThrowsError(try SnapzyCommand.parseAsRoot(["measure", "screen", "--at", "1,1", "--keep", "shot.jpg"]))
    XCTAssertNoThrow(try SnapzyCommand.parseAsRoot(["measure", "screen", "--at", "1,1", "--keep", "shot.png"]))
    XCTAssertNoThrow(try SnapzyCommand.parseAsRoot(["measure", "screen", "--at", "1,1", "--keep", "out/"]))
  }
}
