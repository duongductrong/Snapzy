//
//  LiquidGlassVibrancy.swift
//  Snapzy
//
//  NSVisualEffectView bridge for HUD window vibrancy and borderless glass backdrops.
//

import AppKit
import SwiftUI

/// AppKit visual effect view bridge for macOS 13-15 fallback backdrops.
struct LiquidGlassVibrancyBackdrop: NSViewRepresentable {
  var material: NSVisualEffectView.Material = .hudWindow
  var blending: NSVisualEffectView.BlendingMode = .behindWindow

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = blending
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    if nsView.material != material {
      nsView.material = material
    }
    if nsView.blendingMode != blending {
      nsView.blendingMode = blending
    }
    if nsView.state != .active {
      nsView.state = .active
    }
  }
}
