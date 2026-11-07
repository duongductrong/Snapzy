//
//  MeasureRunner.swift
//  SnapzyCLICore
//
//  The pure part of `snapzy measure`: image + scale + requested points and
//  boxes → measurements. No files, sockets or output, so it is tested on
//  synthetic images.
//

import CoreGraphics
import Foundation
import SnapzyCLIProtocol
import SnapzyMeasureCore

public struct MeasureRequest: Sendable, Equatable {
  public var points: [CLIPoint]
  public var boxes: [CLIRect]
  public var axis: MeasureAxis
  public var tolerance: Int
  public var snap: Bool
  /// Inputs are image pixels instead of points.
  public var inputsArePixels: Bool

  public init(
    points: [CLIPoint] = [],
    boxes: [CLIRect] = [],
    axis: MeasureAxis = .both,
    tolerance: Int = MeasureEdgeScanner.defaultTolerance,
    snap: Bool = true,
    inputsArePixels: Bool = false
  ) {
    self.points = points
    self.boxes = boxes
    self.axis = axis
    self.tolerance = tolerance
    self.snap = snap
    self.inputsArePixels = inputsArePixels
  }
}

public enum MeasureRunner {
  /// Spans first (in `--at` order), then boxes (in `--box` order).
  public static func measure(image: CGImage, scale: Double, request: MeasureRequest) throws -> [CLIMeasurement] {
    guard let raster = MeasureRaster(image: image) else {
      throw CLIError(.internal, "Could not read the pixels of a \(image.width)×\(image.height) image")
    }
    return try measure(raster: raster, scale: scale, request: request)
  }

  public static func measure(raster: MeasureRaster, scale: Double, request: MeasureRequest) throws -> [CLIMeasurement] {
    guard scale.isFinite, scale > 0 else {
      throw CLIError(.invalidArguments, "Scale must be greater than 0, got \(scale)")
    }
    let geometry = Geometry(
      width: raster.width,
      height: raster.height,
      scale: scale,
      inputsArePixels: request.inputsArePixels
    )

    let spans = try request.points.map { point -> CLIMeasurement in
      let pixel = try geometry.pixel(for: point)
      let span = MeasureEdgeScanner.span(in: raster, from: pixel, axis: request.axis, tolerance: request.tolerance)
      let rect = MeasurePixelRect(minX: span.left, minY: span.top, maxX: span.right, maxY: span.bottom)
      return .span(
        at: point,
        axis: request.axis,
        points: geometry.extent(rect, width: span.width, height: span.height, inPoints: true),
        pixels: geometry.extent(rect, width: span.width, height: span.height, inPoints: false)
      )
    }

    let boxes = try request.boxes.map { box -> CLIMeasurement in
      let input = try geometry.pixelRect(for: box)
      let rect = request.snap ? MeasureEdgeScanner.snap(input, in: raster, tolerance: request.tolerance) : input
      return .box(
        input: box,
        snapped: request.snap,
        points: geometry.extent(rect, width: rect.width, height: rect.height, inPoints: true),
        pixels: geometry.extent(rect, width: rect.width, height: rect.height, inPoints: false)
      )
    }

    return spans + boxes
  }

  /// Converts between command-line inputs, image pixels and points.
  struct Geometry {
    let width: Int
    let height: Int
    let scale: Double
    let inputsArePixels: Bool

    private var inputScale: Double {
      inputsArePixels ? 1 : scale
    }

    /// The pixel containing `point`.
    func pixel(for point: CLIPoint) throws -> MeasurePixel {
      let x = (point.x * inputScale).rounded(.down)
      let y = (point.y * inputScale).rounded(.down)
      guard x >= 0, y >= 0, x < Double(width), y < Double(height) else {
        throw outOfBounds("Point \(point) is outside the image")
      }
      return MeasurePixel(x: Int(x), y: Int(y))
    }

    /// Every pixel the box touches, clamped to the image. A box entirely outside is an error.
    func pixelRect(for box: CLIRect) throws -> MeasurePixelRect {
      let minX = (box.x * inputScale).rounded(.down)
      let minY = (box.y * inputScale).rounded(.down)
      let maxX = ((box.x + box.width) * inputScale).rounded(.up) - 1
      let maxY = ((box.y + box.height) * inputScale).rounded(.up) - 1
      guard maxX >= 0, maxY >= 0, minX < Double(width), minY < Double(height) else {
        throw outOfBounds("Box \(box) is outside the image")
      }
      return MeasurePixelRect(
        minX: Int(max(minX, 0)),
        minY: Int(max(minY, 0)),
        maxX: Int(min(max(maxX, minX), Double(width - 1))),
        maxY: Int(min(max(maxY, minY), Double(height - 1)))
      )
    }

    func extent(_ rect: MeasurePixelRect, width: Int?, height: Int?, inPoints: Bool) -> CLIMeasureExtent {
      let factor = inPoints ? 1 / scale : 1
      let convert = { (pixels: Int) in Self.round(Double(pixels) * factor) }
      return CLIMeasureExtent(
        width: width.map(convert),
        height: height.map(convert),
        rect: CLIRect(
          x: convert(rect.minX),
          y: convert(rect.minY),
          width: convert(rect.width),
          height: convert(rect.height)
        )
      )
    }

    /// Three decimals: enough for any real scale, without float noise in the JSON.
    static func round(_ value: Double) -> Double {
      (value * 1000).rounded() / 1000
    }

    private func outOfBounds(_ message: String) -> CLIError {
      let size = { (pixels: Int) in CLIMeasureNumber.text(Double(pixels) / scale) }
      let points = "\(size(width)) × \(size(height)) pt"
      let pixels = "\(width) × \(height) px"
      let unit = inputsArePixels ? "pixels" : "points"
      return CLIError(
        .invalidArguments,
        message,
        hint: "The image is \(points) (\(pixels), scale \(CLIMeasureNumber.text(scale))); "
          + "coordinates are \(unit) from its top-left corner"
      )
    }
  }
}
