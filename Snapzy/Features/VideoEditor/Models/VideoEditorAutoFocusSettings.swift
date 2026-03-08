//
//  VideoEditorAutoFocusSettings.swift
//  Snapzy
//
//  Configuration for mouse-follow smart camera behavior.
//

import CoreGraphics
import Foundation

struct AutoFocusSettings: Equatable {
  static let zoomRange: ClosedRange<CGFloat> = 1.0...4.0
  static let followSpeedRange: ClosedRange<Double> = 0.2...1.0
  static let focusMarginRange: ClosedRange<CGFloat> = 0.2...0.9

  var isEnabled: Bool = false
  var zoomLevel: CGFloat = 2.0
  var followSpeed: Double = 0.55
  var focusMargin: CGFloat = 0.45

  var zoomDisplayValue: String {
    if zoomLevel == floor(zoomLevel) {
      return String(format: "%.0fx", zoomLevel)
    }
    return String(format: "%.1fx", zoomLevel)
  }

  var followSpeedDisplayValue: String {
    "\(Int((followSpeed * 100).rounded()))%"
  }

  var focusMarginDisplayValue: String {
    "\(Int((focusMargin * 100).rounded()))%"
  }
}

struct AutoFocusCameraSample: Equatable {
  var time: TimeInterval
  var center: CGPoint
}

struct VideoEditorCameraState: Equatable {
  var zoomLevel: CGFloat
  var center: CGPoint

  static let identity = VideoEditorCameraState(
    zoomLevel: 1.0,
    center: CGPoint(x: 0.5, y: 0.5)
  )
}
