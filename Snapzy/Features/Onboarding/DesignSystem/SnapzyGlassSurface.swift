//
//  SnapzyGlassSurface.swift
//  Snapzy
//
//  Liquid glass surface compositing, vibrancy backdrop, and borderless window glass.
//

import AppKit
import SwiftUI

enum SnapzyGlassLayer {
  case backdrop
  case control
}

enum SnapzyGlassHighlight: Equatable {
  case specular
  case custom(top: Double, bottom: Double)
  case none

  fileprivate var stops: (top: Color, bottom: Color)? {
    switch self {
    case .specular:
      return (SnapzySurfaceGlass.specularTopColor, SnapzySurfaceGlass.specularBottomColor)
    case let .custom(top, bottom):
      return (.white.opacity(top), .white.opacity(bottom))
    case .none:
      return nil
    }
  }
}

// MARK: - Vibrancy NSView Bridge

struct SnapzyVibrancyBackdrop: NSViewRepresentable {
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
    if nsView.material != material { nsView.material = material }
    if nsView.blendingMode != blending { nsView.blendingMode = blending }
    if nsView.state != .active { nsView.state = .active }
  }
}

// MARK: - Refraction Layer

struct SnapzyGlassRefraction<S: InsettableShape>: View {
  var shape: S
  var layer: SnapzyGlassLayer = .control

  @ViewBuilder
  var body: some View {
    fallback
  }

  @ViewBuilder
  private var fallback: some View {
    switch layer {
    case .backdrop:
      SnapzyVibrancyBackdrop(material: .hudWindow, blending: .behindWindow)
        .clipShape(shape)
    case .control:
      shape.fill(
        LinearGradient(
          colors: [
            Color.white.opacity(SnapzySurfaceGlass.fallbackControlSheenTop),
            Color.white.opacity(SnapzySurfaceGlass.fallbackControlSheenBottom),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    }
  }
}

// MARK: - Composite Glass Surface

struct SnapzyGlassSurface<S: InsettableShape>: View {
  var shape: S
  var substrate: CGFloat
  var dim: CGFloat = 0
  var tint: CGFloat = 0
  var highlight: SnapzyGlassHighlight = .specular
  var layer: SnapzyGlassLayer = .control

  var body: some View {
    ZStack {
      if substrate > 0 {
        shape.fill(Color.black.opacity(substrate))
      }

      SnapzyGlassRefraction(shape: shape, layer: layer)
        .clipShape(shape)

      if dim > 0 {
        shape.fill(Color.black.opacity(dim))
      }

      if tint > 0 {
        shape.fill(Color.white.opacity(tint))
      }

      if let stops = highlight.stops {
        shape.strokeBorder(
          LinearGradient(
            colors: [stops.top, stops.bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: SnapzySurfaceGlass.specularLineWidth
        )
      }
    }
  }
}

// MARK: - Window Backdrop

struct SnapzyGlassWindowBackdrop: View {
  var radius: CGFloat = SnapzyOnboardingMetrics.windowRadius
  var bloomRadius: CGFloat = 620

  var body: some View {
    ZStack {
      SnapzyVibrancyBackdrop(material: .hudWindow, blending: .behindWindow)

      LinearGradient(
        colors: [
          Color.black.opacity(0.46),
          Color.black.opacity(0.38),
          Color.black.opacity(0.44),
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      RadialGradient(
        colors: [Color.white.opacity(0.06), .clear],
        center: .topLeading,
        startRadius: 0,
        endRadius: bloomRadius
      )
    }
    .overlay(alignment: .top) {
      LinearGradient(
        colors: [.white.opacity(0.02), .white.opacity(0.34), .white.opacity(0.02)],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(height: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
    )
  }
}
