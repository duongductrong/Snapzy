//
//  WallpaperQualityConfig.swift
//  ClaudeShot
//
//  Configuration for wallpaper rendering quality and performance testing
//  Adjust these values to test different performance/quality tradeoffs
//

import Foundation

/// Configuration for wallpaper rendering quality and performance testing
/// Adjust these values to test different performance/quality tradeoffs
struct WallpaperQualityConfig {

  // MARK: - Resolution

  /// Max preview dimension (pixels). Affects memory & render speed.
  /// - 1024: Low memory (~1MB), may show pixelation on 4K displays
  /// - 2048: Balanced (~4MB), good for most displays (DEFAULT)
  /// - 4096: High quality (~16MB), for 5K+ displays
  static var maxResolution: CGFloat = 2048

  // MARK: - Blur

  /// Blur radius for .blurred wallpaper style
  static var blurRadius: CGFloat = 20

  /// Pre-compute blur on load vs real-time per-frame
  static var usePrecomputedBlur: Bool = true

  // MARK: - Debug

  /// Overlay showing actual render dimensions on canvas
  static var showDebugOverlay: Bool = false

  /// Console logging of load times and memory usage
  static var logPerformanceMetrics: Bool = false
}
