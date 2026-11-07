//
//  MeasureSession.swift
//  SnapzyCLICore
//
//  The file side of `snapzy measure`: load an image (or a staged capture),
//  run `MeasureRunner`, and keep or delete the capture. Captures come in
//  through a closure so tests can hand in a staged fixture without a socket.
//

import Foundation
import SnapzyCLIProtocol
import SnapzyMeasureCore

enum MeasureSession {
  /// `measure image`: `path` may be relative to `currentDirectory` or start with `~`.
  static func measureImage(
    path: String,
    currentDirectory: URL,
    request: MeasureRequest,
    scale scaleOverride: Double?
  ) throws -> CLIMeasureResult {
    let url = resolve(path, currentDirectory: currentDirectory)
    let loaded = try load(url)
    let scale = scaleOverride ?? loaded.scale
    return try CLIMeasureResult(
      source: CLIMeasureSource(
        kind: .image,
        path: url.path,
        width: loaded.image.width,
        height: loaded.image.height,
        scale: scale
      ),
      tolerance: request.tolerance,
      measurements: MeasureRunner.measure(image: loaded.image, scale: scale, request: request)
    )
  }

  /// `measure screen|window|area`: runs `capture`, measures the single staged file at the
  /// capture's scale, then moves it to `keep` (honoring `force`) or deletes it.
  static func measureCapture(
    kind: CLIMeasureSource.Kind,
    request: MeasureRequest,
    keep: OutputDestination?,
    force: Bool,
    writer: OutputWriter = OutputWriter(),
    capture: () throws -> CLICaptureResult
  ) throws -> CLIMeasureResult {
    var result = try capture()
    let staged = result.files.map(\.path)
    guard result.files.count == 1 else {
      staged.forEach { try? FileManager.default.removeItem(atPath: $0) }
      throw CLIError(.internal, "Expected one capture to measure, got \(result.files.count)")
    }

    var keptPath: String?
    if let keep {
      // Keep first, so the image survives even when a point is out of bounds.
      result = try writer.apply(result, to: keep, force: force) { _ in
        throw CLIError(.invalidArguments, "--keep cannot write to stdout")
      }
      keptPath = result.files[0].path
    }
    defer {
      if keptPath == nil {
        try? FileManager.default.removeItem(atPath: staged[0])
      }
    }

    let file = result.files[0]
    let loaded: MeasureLoadedImage
    do {
      loaded = try MeasureImageLoader.load(url: URL(fileURLWithPath: file.path))
    } catch {
      throw CLIError(.internal, "Could not read the capture at \(file.path): \(error)")
    }
    return try CLIMeasureResult(
      source: CLIMeasureSource(
        kind: kind,
        path: keptPath,
        width: loaded.image.width,
        height: loaded.image.height,
        scale: file.scale,
        displayID: file.displayID,
        window: file.window
      ),
      tolerance: request.tolerance,
      measurements: MeasureRunner.measure(image: loaded.image, scale: file.scale, request: request)
    )
  }

  static func resolve(_ path: String, currentDirectory: URL) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expanded, relativeTo: currentDirectory).standardizedFileURL
  }

  /// Loader failures as CLI errors: a missing file is "not found", anything else about the
  /// file is the caller's argument.
  static func load(_ url: URL, maxPixels: Int = MeasureImageLoader.defaultMaxPixels) throws -> MeasureLoadedImage {
    do {
      return try MeasureImageLoader.load(url: url, maxPixels: maxPixels)
    } catch let error as MeasureImageLoaderError {
      switch error {
      case .notFound(let path):
        throw CLIError(
          .targetNotFound,
          "No image at \(path)",
          hint: "Relative paths start at the current directory"
        )
      case .unreadable(let path):
        throw CLIError(
          .invalidArguments,
          "\(path) is not an image Snapzy can read",
          hint: "Pass a PNG, JPEG, HEIC, TIFF or another format macOS can open"
        )
      case let .tooLarge(width, height, maxPixels):
        let megapixels = CLIMeasureNumber.text(Double(maxPixels) / 1_000_000)
        throw CLIError(
          .invalidArguments,
          "The image is \(width)×\(height) pixels, over the \(megapixels) megapixel limit",
          hint: "Crop or downscale it first"
        )
      }
    }
  }
}
