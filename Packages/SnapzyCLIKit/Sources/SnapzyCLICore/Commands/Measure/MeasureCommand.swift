//
//  MeasureCommand.swift
//  SnapzyCLICore
//
//  `measure image|screen|window|area`: the Screen Ruler edge measurements from
//  the command line. `image` runs locally without Snapzy; the others take a
//  capture through Snapzy and measure it here.
//

import ArgumentParser

struct MeasureCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "measure",
    abstract: "Measure UI elements in an image or a fresh capture.",
    discussion: """
    --at x,y measures the run of same-colored pixels around a point, like \
    hovering with Screen Ruler. --box x,y,w,h shrinks a rectangle to the edges \
    of the content inside it. Coordinates are points from the top-left corner \
    of the image (pixels with --pixels).
    """,
    subcommands: [
      MeasureImageCommand.self,
      MeasureScreenCommand.self,
      MeasureWindowCommand.self,
      MeasureAreaCommand.self,
    ]
  )
}
