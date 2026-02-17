//
//  ZoomPreviewOverlay.swift
//  Snapzy
//
//  Overlay that applies zoom effect to video preview in real-time
//

import AVFoundation
import SwiftUI

/// Wrapper view that applies zoom transforms and background to the video player
struct ZoomableVideoPlayerSection: View {
  @ObservedObject var state: VideoEditorState

  @State private var currentZoomLevel: CGFloat = 1.0
  @State private var currentZoomCenter: CGPoint = CGPoint(x: 0.5, y: 0.5)

  private let animationDuration: Double = 0.25

  var body: some View {
    GeometryReader { geometry in
      let scaleFactor = previewScaleFactor(for: geometry.size)
      let scaledPadding = state.backgroundPadding * scaleFactor
      let scaledCornerRadius = state.backgroundCornerRadius * scaleFactor
      let scaledShadowRadius = state.backgroundShadowIntensity * 20 * scaleFactor
      let scaledShadowY = state.backgroundShadowIntensity * 10 * scaleFactor

      // Calculate the composite frame size (video + padding) maintaining aspect ratio
      let compositeSize = calculateCompositeSize(containerSize: geometry.size, scaledPadding: scaledPadding)

      ZStack {
        // Background layer - fills composite area only, no black gaps
        if state.backgroundStyle != .none {
          backgroundView
            .frame(width: compositeSize.width, height: compositeSize.height)
            .clipped()
        }

        // Video with effects - use scaled values for WYSIWYG with export
        videoPlayerContent(in: geometry.size)
          .cornerRadius(scaledCornerRadius)
          .shadow(
            color: .black.opacity(Double(state.backgroundShadowIntensity) * 0.5),
            radius: scaledShadowRadius,
            x: 0,
            y: scaledShadowY
          )
          .padding(scaledPadding)
      }
      .frame(width: compositeSize.width, height: compositeSize.height)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignmentValue)
    }
    .onReceive(state.$currentTime) { time in
      updateZoomState(at: CMTimeGetSeconds(time))
    }
    .onChange(of: state.zoomSegments) { _ in
      updateZoomState(at: CMTimeGetSeconds(state.currentTime))
    }
  }

  // MARK: - Background View

  @ViewBuilder
  private var backgroundView: some View {
    Group {
      switch state.backgroundStyle {
      case .none:
        Color.clear
      case .gradient(let preset):
        LinearGradient(
          colors: preset.colors,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      case .solidColor(let color):
        color
      case .wallpaper:
        // Use cached image for 60fps performance (no disk I/O during render)
        if let nsImage = state.cachedBackgroundImage {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Color.gray // Placeholder while loading
        }
      case .blurred:
        // Use pre-computed blur for 60fps performance (no real-time blur)
        if let nsImage = state.cachedBlurredImage {
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else if let nsImage = state.cachedBackgroundImage {
          // Fallback to non-blurred while computing blur
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Color.gray
        }
      }
    }
    .drawingGroup() // Metal rasterization for 60fps
  }

  // MARK: - Video Player Content

  @ViewBuilder
  private func videoPlayerContent(in size: CGSize) -> some View {
    VideoPlayerSection(player: state.player)
      .scaleEffect(currentZoomLevel)
      .offset(zoomOffset(in: size))
      .clipped()
      .animation(.easeInOut(duration: animationDuration), value: currentZoomLevel)
      .animation(.easeInOut(duration: animationDuration), value: currentZoomCenter)
      .overlay(alignment: .topTrailing) {
        zoomIndicator
          .allowsHitTesting(false)
      }
      .contentShape(Rectangle())
  }

  // MARK: - Alignment

  private var alignmentValue: Alignment {
    switch state.backgroundAlignment {
    case .topLeft: return .topLeading
    case .top: return .top
    case .topRight: return .topTrailing
    case .left: return .leading
    case .center: return .center
    case .right: return .trailing
    case .bottomLeft: return .bottomLeading
    case .bottom: return .bottom
    case .bottomRight: return .bottomTrailing
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

  // MARK: - Preview Scale Factor

  /// Calculate scale factor between preview container and export size
  /// This ensures padding/cornerRadius in preview matches export proportionally (WYSIWYG)
  private func previewScaleFactor(for containerSize: CGSize) -> CGFloat {
    // Use export size for WYSIWYG preview - shows scaled video matching export result
    let effectiveSize = state.exportSettings.exportSize(from: state.naturalSize)
    guard effectiveSize.width > 0 && effectiveSize.height > 0 &&
          containerSize.width > 0 && containerSize.height > 0 else { return 1.0 }

    // Calculate how the video fits in the container (aspect fit)
    let containerAspect = containerSize.width / containerSize.height
    let videoAspect = effectiveSize.width / effectiveSize.height

    let fittedSize: CGSize
    if containerAspect > videoAspect {
      // Container is wider - video height fills container
      fittedSize = CGSize(
        width: containerSize.height * videoAspect,
        height: containerSize.height
      )
    } else {
      // Container is taller - video width fills container
      fittedSize = CGSize(
        width: containerSize.width,
        height: containerSize.width / videoAspect
      )
    }

    // Scale factor = preview size / effective size
    // This converts "pixels" in state to "points" in preview
    return min(fittedSize.width / effectiveSize.width, fittedSize.height / effectiveSize.height)
  }

  // MARK: - Composite Size Calculation

  /// Calculate the size of the composite frame (video + padding) that fits within the container
  /// Uses export dimensions for WYSIWYG preview - shows scaled video matching export result
  private func calculateCompositeSize(containerSize: CGSize, scaledPadding: CGFloat) -> CGSize {
    // Use export size for WYSIWYG preview
    let effectiveSize = state.exportSettings.exportSize(from: state.naturalSize)
    guard effectiveSize.width > 0 && effectiveSize.height > 0 &&
          containerSize.width > 0 && containerSize.height > 0 else {
      return containerSize
    }

    // Use raw padding (absolute pixels) to match export behavior exactly
    // Export adds padding in absolute pixels to the scaled video dimensions
    let compositeWidth = effectiveSize.width + (state.backgroundPadding * 2)
    let compositeHeight = effectiveSize.height + (state.backgroundPadding * 2)
    let compositeAspect = compositeWidth / compositeHeight

    // Fit composite into container maintaining aspect ratio
    let containerAspect = containerSize.width / containerSize.height

    if containerAspect > compositeAspect {
      // Container is wider - composite height fills container
      return CGSize(
        width: containerSize.height * compositeAspect,
        height: containerSize.height
      )
    } else {
      // Container is taller - composite width fills container
      return CGSize(
        width: containerSize.width,
        height: containerSize.width / compositeAspect
      )
    }
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
