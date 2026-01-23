//
//  ZoomPreviewOverlay.swift
//  ClaudeShot
//
//  Overlay that applies zoom effect to video preview in real-time
//

import AVFoundation
import SwiftUI

/// Wrapper view that applies zoom transforms to the video player
struct ZoomableVideoPlayerSection: View {
  @ObservedObject var state: VideoEditorState

  @State private var currentZoomLevel: CGFloat = 1.0
  @State private var currentZoomCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)

  private let animationDuration: Double = 0.25

  var body: some View {
    GeometryReader { geometry in
      VideoPlayerSection(player: state.player)
        .scaleEffect(currentZoomLevel)
        .offset(zoomOffset(in: geometry.size))
        .clipped()
        .animation(.easeInOut(duration: animationDuration), value: currentZoomLevel)
        .animation(.easeInOut(duration: animationDuration), value: currentZoomCenter)
        .overlay(alignment: .topTrailing) {
          zoomIndicator
        }
    }
    .onReceive(state.$currentTime) { time in
      updateZoomState(at: CMTimeGetSeconds(time))
    }
    .onChange(of: state.zoomSegments) { _, _ in
      updateZoomState(at: CMTimeGetSeconds(state.currentTime))
    }
  }

  // MARK: - Zoom Offset Calculation

  private func zoomOffset(in size: CGSize) -> CGSize {
    guard currentZoomLevel > 1.0 else { return .zero }

    let transform = ZoomCalculator.calculateTransform(
      zoomLevel: currentZoomLevel,
      center: currentZoomCenter,
      viewSize: size
    )

    return transform.offset
  }

  // MARK: - Zoom Indicator

  @ViewBuilder
  private var zoomIndicator: some View {
    if currentZoomLevel > 1.01 {
      HStack(spacing: 4) {
        Image(systemName: "plus.magnifyingglass")
          .font(.system(size: 10, weight: .semibold))

        Text(String(format: "%.1fx", currentZoomLevel))
          .font(.system(size: 11, weight: .semibold))
          .monospacedDigit()
      }
      .foregroundColor(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color.purple.opacity(0.8))
      .cornerRadius(4)
      .padding(8)
      .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
  }

  // MARK: - State Updates

  private func updateZoomState(at time: TimeInterval) {
    // Find active zoom segment
    guard let segment = state.activeZoomSegment(at: time) else {
      // No active zoom - reset to default
      if currentZoomLevel != 1.0 {
        currentZoomLevel = 1.0
        currentZoomCenter = CGPoint(x: 0.5, y: 0.5)
      }
      return
    }

    // Calculate interpolated zoom values
    let interpolated = ZoomCalculator.interpolateZoom(
      segment: segment,
      currentTime: time,
      transitionDuration: animationDuration
    )

    currentZoomLevel = interpolated.level
    currentZoomCenter = interpolated.center
  }
}

// MARK: - Preview

#Preview {
  ZoomableVideoPlayerSection(
    state: VideoEditorState(url: URL(fileURLWithPath: "/tmp/test.mov"))
  )
  .frame(width: 640, height: 360)
  .background(Color.black)
}
