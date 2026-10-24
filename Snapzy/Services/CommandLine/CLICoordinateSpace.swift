//
//  CLICoordinateSpace.swift
//  Snapzy
//
//  The CLI speaks global points with a top-left origin at the main display
//  (CoreGraphics / Accessibility). AppKit uses a bottom-left origin. Both
//  share x; y flips around the main display's height.
//

import AppKit
import SnapzyCLIProtocol

nonisolated enum CLICoordinateSpace {
  static func topLeftRect(fromAppKit rect: CGRect, mainDisplayHeight: CGFloat) -> CLIRect {
    CLIRect(
      x: rect.origin.x,
      y: mainDisplayHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }

  static func appKitRect(fromTopLeft rect: CLIRect, mainDisplayHeight: CGFloat) -> CGRect {
    CGRect(
      x: rect.x,
      y: mainDisplayHeight - rect.y - rect.height,
      width: rect.width,
      height: rect.height
    )
  }

  static func cliRect(_ rect: CGRect) -> CLIRect {
    CLIRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
  }

  @MainActor
  static var mainDisplayHeight: CGFloat {
    NSScreen.screens.first(where: { $0.displayID == CGMainDisplayID() })?.frame.height
      ?? CGDisplayBounds(CGMainDisplayID()).height
  }
}
