//
//  NSWindow+WindowSpacing.swift
//  ClaudeShot
//
//  Unified window spacing configuration for toolbar, content, and bottom bar
//

import AppKit
import SwiftUI

// MARK: - Window Spacing Configuration

/// Unified configuration for window spacing across toolbar, content, and bottom bar
struct WindowSpacingConfiguration {
  // MARK: Toolbar

  /// Standard toolbar height
  var toolbarHeight: CGFloat = 44

  /// Toolbar horizontal padding
  var toolbarHPadding: CGFloat = 16

  /// Toolbar vertical padding
  var toolbarVPadding: CGFloat = 8

  /// Spacing between toolbar items
  var toolbarItemSpacing: CGFloat = 8

  // MARK: Content

  /// Content area horizontal padding
  var contentHPadding: CGFloat = 16

  /// Content area top padding
  var contentTopPadding: CGFloat = 12

  /// Content area bottom padding
  var contentBottomPadding: CGFloat = 12

  // MARK: Bottom Bar

  /// Standard bottom bar height
  var bottomBarHeight: CGFloat = 44

  /// Bottom bar horizontal padding
  var bottomBarHPadding: CGFloat = 16

  /// Bottom bar vertical padding
  var bottomBarVPadding: CGFloat = 10

  /// Spacing between bottom bar items
  var bottomBarItemSpacing: CGFloat = 12

  // MARK: Traffic Lights

  /// Gap after traffic lights before content starts
  var trafficLightsGap: CGFloat = 12

  // MARK: Corner Radius

  /// Default corner radius for windows
  var cornerRadius: CGFloat = 24

  static let `default` = WindowSpacingConfiguration()
}

// MARK: - NSWindow Extension

extension NSWindow {

  /// Calculate the X position where traffic light buttons end
  func trafficLightsEndX(config: TrafficLightConfiguration = .default) -> CGFloat {
    guard let zoomButton = standardWindowButton(.zoomButton) else {
      return config.horizontalOffset + (3 * 14) + (2 * config.buttonSpacing)
    }
    return zoomButton.frame.maxX
  }

  /// Calculate the leading padding for toolbar content (after traffic lights)
  func toolbarLeadingInset(
    windowConfig: WindowSpacingConfiguration = .default,
    trafficConfig: TrafficLightConfiguration = .default
  ) -> CGFloat {
    return trafficLightsEndX(config: trafficConfig) + windowConfig.trafficLightsGap
  }

  /// Calculate available width for toolbar content
  func availableToolbarWidth(
    windowConfig: WindowSpacingConfiguration = .default,
    trafficConfig: TrafficLightConfiguration = .default
  ) -> CGFloat {
    let leadingInset = toolbarLeadingInset(
      windowConfig: windowConfig,
      trafficConfig: trafficConfig
    )
    return frame.width - leadingInset - windowConfig.toolbarHPadding
  }

  /// Get edge insets for content area
  func contentEdgeInsets(config: WindowSpacingConfiguration = .default) -> NSEdgeInsets {
    return NSEdgeInsets(
      top: config.contentTopPadding,
      left: config.contentHPadding,
      bottom: config.contentBottomPadding,
      right: config.contentHPadding
    )
  }
}

// MARK: - SwiftUI View Extensions

extension View {

  // MARK: Toolbar Modifiers

  /// Apply standard toolbar styling (height + padding)
  func windowToolbar(_ config: WindowSpacingConfiguration = .default) -> some View {
    self
      .frame(height: config.toolbarHeight)
      .padding(.horizontal, config.toolbarHPadding)
      .padding(.vertical, config.toolbarVPadding)
  }

  /// Apply toolbar height only
  func windowToolbarHeight(_ height: CGFloat = WindowSpacingConfiguration.default.toolbarHeight) -> some View {
    self.frame(height: height)
  }

  /// Apply toolbar padding only
  func windowToolbarPadding(_ config: WindowSpacingConfiguration = .default) -> some View {
    self
      .padding(.horizontal, config.toolbarHPadding)
      .padding(.vertical, config.toolbarVPadding)
  }

  // MARK: Bottom Bar Modifiers

  /// Apply standard bottom bar styling (height + padding)
  func windowBottomBar(_ config: WindowSpacingConfiguration = .default) -> some View {
    self
      .frame(height: config.bottomBarHeight)
      .padding(.horizontal, config.bottomBarHPadding)
      .padding(.vertical, config.bottomBarVPadding)
  }

  /// Apply bottom bar height only
  func windowBottomBarHeight(_ height: CGFloat = WindowSpacingConfiguration.default.bottomBarHeight) -> some View {
    self.frame(height: height)
  }

  /// Apply bottom bar padding only
  func windowBottomBarPadding(_ config: WindowSpacingConfiguration = .default) -> some View {
    self
      .padding(.horizontal, config.bottomBarHPadding)
      .padding(.vertical, config.bottomBarVPadding)
  }

  // MARK: Content Modifiers

  /// Apply content area insets
  func windowContent(_ config: WindowSpacingConfiguration = .default) -> some View {
    self.padding(EdgeInsets(
      top: config.contentTopPadding,
      leading: config.contentHPadding,
      bottom: config.contentBottomPadding,
      trailing: config.contentHPadding
    ))
  }

  /// Apply content horizontal padding only
  func windowContentHPadding(_ config: WindowSpacingConfiguration = .default) -> some View {
    self.padding(.horizontal, config.contentHPadding)
  }

  // MARK: Traffic Lights Modifier

  /// Apply leading inset to account for traffic light buttons
  func windowTrafficLightsInset(_ config: WindowSpacingConfiguration = .default) -> some View {
    let trafficConfig = TrafficLightConfiguration.default
    let width = trafficConfig.horizontalOffset +
                (3 * 14) +
                (2 * trafficConfig.buttonSpacing) +
                config.trafficLightsGap
    return self.padding(.leading, width)
  }

  // MARK: Corner Radius Modifier

  /// Apply corner radius clip to view
  func windowCornerRadius(_ radius: CGFloat = WindowSpacingConfiguration.default.cornerRadius) -> some View {
    self.clipShape(RoundedRectangle(cornerRadius: radius))
  }
}
