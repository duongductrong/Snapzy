//
//  AnnotateCanvasView.swift
//  ZapShot
//
//  Canvas view displaying the image with annotations
//

import SwiftUI

/// Canvas view for displaying and annotating the image
struct AnnotateCanvasView: View {
  @ObservedObject var state: AnnotateState

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // Background
        Color(white: 0.08)

        // Centered, scaled canvas
        canvasContent(in: geometry.size)
          .frame(width: geometry.size.width, height: geometry.size.height)
      }
      .onScrollWheelZoom { delta in
        let newZoom = state.zoomLevel + delta * 0.1
        state.zoomLevel = min(max(newZoom, 0.25), 3.0)
      }
    }
  }

  private func canvasContent(in containerSize: CGSize) -> some View {
    let margin: CGFloat = 40
    let availableWidth = containerSize.width - margin * 2
    let availableHeight = containerSize.height - margin * 2

    // Logical canvas = image + padding (this is what we export)
    let logicalCanvasWidth = state.imageWidth + state.padding * 2
    let logicalCanvasHeight = state.imageHeight + state.padding * 2

    // Scale entire canvas to fit in available space (unified scaling)
    let scaleX = availableWidth / logicalCanvasWidth
    let scaleY = availableHeight / logicalCanvasHeight
    let scale = min(scaleX, scaleY, 1.0)

    // Background = logical canvas * scale (includes padding)
    let bgWidth = logicalCanvasWidth * scale
    let bgHeight = logicalCanvasHeight * scale

    // Image = image size * scale
    let imgWidth = state.imageWidth * scale
    let imgHeight = state.imageHeight * scale

    // Image offset for alignment (relative to ZStack center)
    let imageDisplaySize = CGSize(width: imgWidth, height: imgHeight)
    let offset = state.imageOffset(
      for: CGSize(width: bgWidth, height: bgHeight),
      imageDisplaySize: imageDisplaySize,
      displayPadding: state.padding * scale
    )

    return ZStack {
      // Background layer (scaled canvas with padding)
      backgroundLayer(width: bgWidth, height: bgHeight)

      // Image positioned within scaled padding area
      imageLayer(width: imgWidth, height: imgHeight)
        .offset(x: offset.x, y: offset.y)

      // Drawing canvas matches image position
      CanvasDrawingView(state: state, displayScale: scale)
        .frame(width: imgWidth, height: imgHeight)
        .offset(x: offset.x, y: offset.y)

      // Text editing overlay (when editing a text annotation)
      if state.editingTextAnnotationId != nil {
        TextEditOverlay(
          state: state,
          scale: scale,
          imageOffset: offset,
          imageSize: CGSize(width: imgWidth, height: imgHeight)
        )
        .frame(width: imgWidth, height: imgHeight)
        .offset(x: offset.x, y: offset.y)
      }
    }
    .scaleEffect(state.zoomLevel)
  }

  // MARK: - Background Layer

  @ViewBuilder
  private func backgroundLayer(width: CGFloat, height: CGFloat) -> some View {
    switch state.backgroundStyle {
    case .none:
      EmptyView()

    case .gradient(let preset):
      RoundedRectangle(cornerRadius: state.cornerRadius)
        .fill(LinearGradient(
          colors: preset.colors,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ))
        .frame(width: width, height: height)
        .shadow(
          color: .black.opacity(state.shadowIntensity),
          radius: 20,
          x: 0,
          y: 10
        )

    case .wallpaper(let url):
      if let nsImage = NSImage(contentsOf: url) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: width, height: height)
          .clipped()
          .cornerRadius(state.cornerRadius)
      }

    case .blurred(let url):
      if let nsImage = NSImage(contentsOf: url) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: width, height: height)
          .blur(radius: 20)
          .clipped()
          .cornerRadius(state.cornerRadius)
      }

    case .solidColor(let color):
      RoundedRectangle(cornerRadius: state.cornerRadius)
        .fill(color)
        .frame(width: width, height: height)
        .shadow(
          color: .black.opacity(state.shadowIntensity),
          radius: 20,
          x: 0,
          y: 10
        )
    }
  }

  // MARK: - Image Layer

  private func imageLayer(width: CGFloat, height: CGFloat) -> some View {
    return Image(nsImage: state.sourceImage)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: width, height: height)
      .cornerRadius(state.cornerRadius)
      .shadow(
        color: .black.opacity(state.backgroundStyle != .none ? state.shadowIntensity : 0),
        radius: 15,
        x: 0,
        y: 8
      )
  }
}

// MARK: - Scroll Wheel Zoom Modifier

struct ScrollWheelZoomModifier: ViewModifier {
  let onZoom: (CGFloat) -> Void

  func body(content: Content) -> some View {
    content
      .background(ScrollWheelZoomView(onZoom: onZoom))
  }
}

struct ScrollWheelZoomView: NSViewRepresentable {
  let onZoom: (CGFloat) -> Void

  func makeNSView(context: Context) -> ScrollWheelZoomNSView {
    ScrollWheelZoomNSView(onZoom: onZoom)
  }

  func updateNSView(_ nsView: ScrollWheelZoomNSView, context: Context) {
    nsView.onZoom = onZoom
  }
}

final class ScrollWheelZoomNSView: NSView {
  var onZoom: (CGFloat) -> Void

  init(onZoom: @escaping (CGFloat) -> Void) {
    self.onZoom = onZoom
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func scrollWheel(with event: NSEvent) {
    // Only zoom when Command key is held
    if event.modifierFlags.contains(.command) {
      let delta = event.scrollingDeltaY
      onZoom(delta)
    } else {
      super.scrollWheel(with: event)
    }
  }
}

extension View {
  func onScrollWheelZoom(_ action: @escaping (CGFloat) -> Void) -> some View {
    modifier(ScrollWheelZoomModifier(onZoom: action))
  }
}
