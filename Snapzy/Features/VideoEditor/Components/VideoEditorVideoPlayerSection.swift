//
//  VideoPlayerSection.swift
//  Snapzy
//
//  NSViewRepresentable wrapper for AVPlayerView
//

import AVKit
import SwiftUI

/// SwiftUI wrapper for AVPlayerView with custom controls disabled
struct VideoPlayerSection: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.player = player
    view.controlsStyle = .none
    view.showsFullScreenToggleButton = false
    view.videoGravity = .resizeAspect
    return view
  }

  func updateNSView(_ nsView: AVPlayerView, context: Context) {
    // Player is managed by state, no updates needed
  }
}
