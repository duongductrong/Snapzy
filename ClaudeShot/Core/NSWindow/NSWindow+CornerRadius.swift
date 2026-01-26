//
//  NSWindow+CornerRadius.swift
//  ClaudeShot
//
//  Reusable NSWindow extension for custom corner radius
//

import AppKit

extension NSWindow {

  /// Default corner radius for app windows
  static let defaultCornerRadius: CGFloat = 24

  /// Apply custom corner radius to the window
  /// - Parameter radius: The corner radius to apply (default: 24)
  func applyCornerRadius(_ radius: CGFloat = NSWindow.defaultCornerRadius) {
    // Apply corner radius to the window itself using setValue
    // This modifies the actual window frame corner radius
    setValue(radius, forKey: "cornerRadius")

    // Access the window's content view and apply corner radius
    if let contentView = contentView {
      contentView.wantsLayer = true
      contentView.layer?.cornerRadius = radius
      contentView.layer?.masksToBounds = true
    }

    // Apply to the window's frame view (NSThemeFrame) for border consistency
    if let frameView = contentView?.superview {
      frameView.wantsLayer = true
      frameView.layer?.cornerRadius = radius
      frameView.layer?.masksToBounds = true

      // Find and update any visual effect views within the frame
      for subview in frameView.subviews {
        if let visualEffectView = subview as? NSVisualEffectView {
          visualEffectView.wantsLayer = true
          visualEffectView.layer?.cornerRadius = radius
          visualEffectView.layer?.masksToBounds = true
        }
      }
    }
  }
}
