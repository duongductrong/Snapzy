//
//  AnnotateCanvasView.swift
//  ClaudeShot
//
//  Canvas view displaying the image with annotations
//

import SwiftUI
import UniformTypeIdentifiers

/// Canvas view for displaying and annotating the image
struct AnnotateCanvasView: View {
  @ObservedObject var state: AnnotateState
  @State private var isDragOver = false
  @State private var showDropError = false
  @State private var dropErrorMessage = ""

  /// Supported image types for drag-drop
  static let supportedImageTypes: [UTType] = [
    .png, .jpeg, .gif, .tiff, .bmp, .heic
  ]

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // Background
//        Color(nsColor: .textBackgroundColor)

        if state.hasImage {
          // Centered, scaled canvas
          canvasContent(in: geometry.size)
            .frame(width: geometry.size.width, height: geometry.size.height)
        } else {
          // Drop zone when no image loaded
          AnnotateDropZoneView(isDragOver: $isDragOver)
        }
      }
      .onScrollWheelZoom { delta in
        guard state.hasImage else { return }
        let newZoom = state.zoomLevel + delta * 0.1
        state.zoomLevel = min(max(newZoom, 0.25), 3.0)
      }
      .onDrop(of: [.fileURL, .image], isTargeted: $isDragOver) { providers in
        handleDrop(providers: providers)
      }
      .overlay(alignment: .bottom) {
        if showDropError {
          dropErrorBanner
        }
      }
    }
  }

  /// Error banner for invalid file drops
  private var dropErrorBanner: some View {
    Text(dropErrorMessage)
      .font(.callout)
      .foregroundColor(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(Color.red.opacity(0.9))
      .cornerRadius(8)
      .padding(.bottom, 20)
      .transition(.move(edge: .bottom).combined(with: .opacity))
      .animation(.easeInOut(duration: 0.3), value: showDropError)
  }

  /// Show error message temporarily
  private func showError(_ message: String) {
    Task { @MainActor in
      dropErrorMessage = message
      withAnimation {
        showDropError = true
      }
      try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
      withAnimation {
        showDropError = false
      }
    }
  }

  private func canvasContent(in containerSize: CGSize) -> some View {
    let margin: CGFloat = 40
    let availableWidth = containerSize.width - margin * 2
    let availableHeight = containerSize.height - margin * 2

    // Calculate alignment space needed for non-center alignments
    // This expands the background to allow image movement
    let alignmentSpace: CGFloat = state.imageAlignment != .center ? 40 : 0

    // Logical canvas = image + padding + alignment space (this is what we export)
    let logicalCanvasWidth = state.imageWidth + state.padding * 2 + alignmentSpace
    let logicalCanvasHeight = state.imageHeight + state.padding * 2 + alignmentSpace

    // Scale entire canvas to fit in available space (unified scaling)
    let scaleX = availableWidth / logicalCanvasWidth
    let scaleY = availableHeight / logicalCanvasHeight
    let scale = min(scaleX, scaleY, 1.0)

    // Background = logical canvas * scale (includes padding + alignment space)
    let bgWidth = logicalCanvasWidth * scale
    let bgHeight = logicalCanvasHeight * scale

    // Image stays at ORIGINAL size (no shrinking!)
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
          imageSize: CGSize(width: state.imageWidth, height: state.imageHeight)
        )
        .frame(width: imgWidth, height: imgHeight)
        .offset(x: offset.x, y: offset.y)
      }

      // Crop overlay (when crop tool is selected or crop is active)
      if state.selectedTool == .crop || state.cropRect != nil {
        CropOverlayView(
          state: state,
          scale: scale,
          imageSize: CGSize(width: state.imageWidth, height: state.imageHeight)
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

  @ViewBuilder
  private func imageLayer(width: CGFloat, height: CGFloat) -> some View {
    if let sourceImage = state.sourceImage {
      Image(nsImage: sourceImage)
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

  // MARK: - Drag and Drop

  /// Handle dropped image files
  private func handleDrop(providers: [NSItemProvider]) -> Bool {
    for provider in providers {
      // Try file URL first
      if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
          guard error == nil,
                let data = item as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil) else {
            Task { @MainActor in
              showError("Failed to load file")
            }
            return
          }

          // Validate file type
          guard Self.isValidImageFile(url: url) else {
            Task { @MainActor in
              showError("Unsupported format. Use PNG, JPG, GIF, TIFF, BMP, or HEIC")
            }
            return
          }

          Task { @MainActor in
            state.loadImage(from: url)
          }
        }
        return true
      }

      // Try loading image data directly
      for imageType in Self.supportedImageTypes {
        if provider.hasItemConformingToTypeIdentifier(imageType.identifier) {
          provider.loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, error in
            guard let data = data,
                  let image = NSImage(data: data) else {
              Task { @MainActor in
                showError("Failed to load image data")
              }
              return
            }

            Task { @MainActor in
              state.loadImage(image, url: nil)
            }
          }
          return true
        }
      }
    }

    // No valid provider found
    showError("Unsupported file type")
    return false
  }

  /// Validate file is a supported image format
  static func isValidImageFile(url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension) else {
      return false
    }
    return supportedImageTypes.contains { type.conforms(to: $0) }
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
