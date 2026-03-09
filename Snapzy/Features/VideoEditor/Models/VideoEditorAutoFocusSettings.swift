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
  static let defaultZoomLevel: CGFloat = 2.0
  static let defaultFollowSpeed: Double = 0.55
  static let defaultFocusMargin: CGFloat = 0.45

  var isEnabled: Bool = false
  var zoomLevel: CGFloat = Self.defaultZoomLevel
  var followSpeed: Double = Self.defaultFollowSpeed
  var focusMargin: CGFloat = Self.defaultFocusMargin

  init(
    isEnabled: Bool = false,
    zoomLevel: CGFloat = Self.defaultZoomLevel,
    followSpeed: Double = Self.defaultFollowSpeed,
    focusMargin: CGFloat = Self.defaultFocusMargin
  ) {
    self.isEnabled = isEnabled
    self.zoomLevel = Self.clampZoomLevel(zoomLevel)
    self.followSpeed = Self.clampFollowSpeed(followSpeed)
    self.focusMargin = Self.clampFocusMargin(focusMargin)
  }

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

  static func clampZoomLevel(_ value: CGFloat) -> CGFloat {
    Swift.min(Swift.max(value, zoomRange.lowerBound), zoomRange.upperBound)
  }

  static func clampFollowSpeed(_ value: Double) -> Double {
    Swift.min(Swift.max(value, followSpeedRange.lowerBound), followSpeedRange.upperBound)
  }

  static func clampFocusMargin(_ value: CGFloat) -> CGFloat {
    Swift.min(Swift.max(value, focusMarginRange.lowerBound), focusMarginRange.upperBound)
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
