//
//  MeasureOptions.swift
//  SnapzyCLICore
//
//  What to measure, shared by `measure image` and `measure screen|window|area`.
//

import ArgumentParser
import SnapzyCLIProtocol
import SnapzyMeasureCore

extension MeasureAxis: ExpressibleByArgument {}

struct MeasureOptions: ParsableArguments {
  /// `.unconditionalSingleValue` so a negative value is read as a value, and reported as
  /// out of bounds instead of as an unknown option.
  @Option(
    name: .customLong("at"),
    parsing: .unconditionalSingleValue,
    help: ArgumentHelp(
      "Measure the run of matching pixels around x,y. Repeatable.",
      valueName: "x,y"
    )
  )
  var points: [CLIPoint] = []

  @Option(
    name: .customLong("box"),
    parsing: .unconditionalSingleValue,
    help: ArgumentHelp(
      "Measure the content inside x,y,width,height, snapped to its edges. Repeatable.",
      valueName: "x,y,w,h"
    )
  )
  var boxes: [CLIRect] = []

  @Option(help: "Directions --at measures.")
  var axis: MeasureAxis = .both

  @Option(help: "Largest color step (0-64) that is not an edge.")
  var tolerance: Int = MeasureEdgeScanner.defaultTolerance

  @Flag(name: .customLong("no-snap"), help: "Report --box as given instead of snapping it to content.")
  var noSnap = false

  @Flag(help: "Coordinates are image pixels instead of points.")
  var pixels = false

  mutating func validate() throws {
    guard !points.isEmpty || !boxes.isEmpty else {
      throw ValidationError("Pass at least one --at or --box.")
    }
    guard MeasureEdgeScanner.toleranceRange.contains(tolerance) else {
      let range = MeasureEdgeScanner.toleranceRange
      throw ValidationError("--tolerance must be between \(range.lowerBound) and \(range.upperBound).")
    }
  }

  var request: MeasureRequest {
    MeasureRequest(
      points: points,
      boxes: boxes,
      axis: axis,
      tolerance: tolerance,
      snap: !noSnap,
      inputsArePixels: pixels
    )
  }
}
