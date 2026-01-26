//
//  NSWindow+TrafficLights.swift
//  ClaudeShot
//
//  Reusable NSWindow extension for traffic light button positioning
//

import AppKit

/// Configuration for traffic light button positioning
struct TrafficLightConfiguration {
  var toolbarGap: CGFloat = 4
  var toolbarTopPadding: CGFloat = 0
  var toolbarItemHeight: CGFloat = 28
  var horizontalOffset: CGFloat = 12
  var buttonSpacing: CGFloat = 8

  static let `default` = TrafficLightConfiguration()
}

extension NSWindow {

  /// Position traffic light buttons to align with custom toolbar items
  /// - Parameter config: Configuration for positioning (uses defaults if not specified)
  func layoutTrafficLights(config: TrafficLightConfiguration = .default) {
    guard let closeButton = standardWindowButton(.closeButton),
          let miniaturizeButton = standardWindowButton(.miniaturizeButton),
          let zoomButton = standardWindowButton(.zoomButton) else {
      return
    }

    let trafficLightHeight = closeButton.frame.height

    // Center traffic lights vertically with toolbar items
    let yPosition = config.toolbarTopPadding - config.toolbarGap +
      (config.toolbarItemHeight - trafficLightHeight) / 2

    // Position buttons vertically
    closeButton.frame.origin.y = yPosition
    miniaturizeButton.frame.origin.y = yPosition
    zoomButton.frame.origin.y = yPosition

    // Position buttons horizontally
    closeButton.frame.origin.x = config.horizontalOffset
    miniaturizeButton.frame.origin.x = closeButton.frame.maxX + config.buttonSpacing
    zoomButton.frame.origin.x = miniaturizeButton.frame.maxX + config.buttonSpacing
  }
}
