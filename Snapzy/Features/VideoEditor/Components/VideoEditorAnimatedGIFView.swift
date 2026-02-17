//
//  AnimatedGIFView.swift
//  Snapzy
//
//  NSViewRepresentable wrapper for displaying animated GIFs
//  Uses NSImageView with animates=true for native macOS GIF playback
//

import AppKit
import SwiftUI

/// Displays an animated GIF using native NSImageView
struct AnimatedGIFView: NSViewRepresentable {
  let url: URL

  func makeNSView(context: Context) -> NSImageView {
    let imageView = NSImageView()
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.animates = true
    imageView.isEditable = false
    imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

    if let image = NSImage(contentsOf: url) {
      imageView.image = image
    }

    return imageView
  }

  func updateNSView(_ nsView: NSImageView, context: Context) {
    // Re-load if URL changes
    if let image = NSImage(contentsOf: url) {
      nsView.image = image
      nsView.animates = true
    }
  }
}
