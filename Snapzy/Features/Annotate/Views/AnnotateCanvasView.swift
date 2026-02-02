//
//  AnnotateCanvasView.swift
//  Snapzy
//
//  Canvas view displaying the image with annotations
//

import SwiftUI
import UniformTypeIdentifiers

/// Canvas view for displaying and annotating the image
struct AnnotateCanvasView: View {
  @ObservedObject var state: AnnotateState
  @FocusState private var isCanvasFocused: Bool
  @State private var isDragOver = false
  @State private var showDropError = false
  @State private var dropErrorMessage = ""

  /// Supported image types for drag-drop
  static let supportedImageTypes: [UTType] = [
    .png, .jpeg, .gif, .tiff, .bmp, .heic
  ]

  /// Check if any mockup transforms have been applied
  private var hasMockupTransforms: Bool {
    state.mockupRotationX != 0 ||
    state.mockupRotationY != 0 ||
    state.mockupRotationZ != 0
  }

  /// Whether to show mockup transforms (only in mockup or preview mode)
  private var shouldShowMockupTransforms: Bool {
    (state.editorMode == .mockup || state.editorMode == .preview) && hasMockupTransforms
  }

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
      .focusable()
      .focusEffectDisabled()
      .focused($isCanvasFocused)
      .onKeyPress { keyPress in
        handleToolShortcut(keyPress)
      }
      .onAppear {
        isCanvasFocused = true
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

    // Use effective values for smooth preview during slider drag
    let currentPadding = state.effectivePadding

    // Calculate alignment space needed for non-center alignments
    // This expands the background to allow image movement
    let alignmentSpace: CGFloat = state.imageAlignment != .center ? 40 : 0

    // Determine effective dimensions based on crop state
    // When crop is applied (not editing), use crop dimensions for centering
    let isCropApplied = state.cropRect != nil && !state.isCropActive
    let effectiveWidth: CGFloat
    let effectiveHeight: CGFloat

    if isCropApplied, let cropRect = state.cropRect {
      // Use crop dimensions for canvas layout
      effectiveWidth = cropRect.width
      effectiveHeight = cropRect.height
    } else {
      // Use full image dimensions
      effectiveWidth = state.imageWidth
      effectiveHeight = state.imageHeight
    }

    // Logical canvas = effective size + padding + alignment space
    let logicalCanvasWidth = effectiveWidth + currentPadding * 2 + alignmentSpace
    let logicalCanvasHeight = effectiveHeight + currentPadding * 2 + alignmentSpace

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

    // Calculate offset based on crop state
    let offset: CGPoint
    if isCropApplied, let cropRect = state.cropRect {
      // When crop is applied, offset image so crop area is centered
      let cropCenterX = cropRect.midX * scale
      let cropCenterY = (state.imageHeight - cropRect.midY) * scale // Flip Y for SwiftUI
      let imageCenterX = imgWidth / 2
      let imageCenterY = imgHeight / 2
      offset = CGPoint(
        x: imageCenterX - cropCenterX,
        y: imageCenterY - cropCenterY
      )
    } else {
      // Normal alignment offset
      offset = state.imageOffset(
        for: CGSize(width: bgWidth, height: bgHeight),
        imageDisplaySize: imageDisplaySize,
        displayPadding: currentPadding * scale
      )
    }

    // Calculate clipping rect for applied crop (in display coordinates)
    let clipRect: CGRect? = isCropApplied ? state.cropRect.map { cropRect in
      CGRect(
        x: cropRect.origin.x * scale,
        y: (state.imageHeight - cropRect.origin.y - cropRect.height) * scale,
        width: cropRect.width * scale,
        height: cropRect.height * scale
      )
    } : nil

    return ZStack {
      // Scaled content group
      ZStack {
        // Background layer (scaled canvas with padding) - NOT transformed
        backgroundLayer(width: bgWidth, height: bgHeight)

        // GROUP: Image + Annotations (transformed together in mockup mode)
        Group {
          // Image positioned within scaled padding area
          imageLayer(width: imgWidth, height: imgHeight)

          // Drawing canvas matches image position - clip to crop when applied
          CanvasDrawingView(state: state, displayScale: scale)
            .frame(width: imgWidth, height: imgHeight)
            .clipShape(
              CropClipShape(clipRect: clipRect, containerSize: CGSize(width: imgWidth, height: imgHeight))
            )

          // Text editing overlay (when editing a text annotation)
          if state.editingTextAnnotationId != nil {
            TextEditOverlay(
              state: state,
              scale: scale,
              imageSize: CGSize(width: state.imageWidth, height: state.imageHeight)
            )
            .frame(width: imgWidth, height: imgHeight)
          }
        }
        .offset(x: offset.x, y: offset.y)
        .modifier(MockupTransformModifier(state: state, isEnabled: shouldShowMockupTransforms))

        // Crop overlay (NOT transformed - editing UI stays flat)
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

      // Crop toolbar (floating at bottom) - OUTSIDE scaleEffect so it doesn't zoom
      if state.selectedTool == .crop && state.isCropActive {
        VStack {
          Spacer()
          CropToolbarView(state: state)
            .padding(.bottom, 20)
        }
      }
    }
  }

  // MARK: - Background Layer

  @ViewBuilder
  private func backgroundLayer(width: CGFloat, height: CGFloat) -> some View {
    // Use effective values for smooth preview during slider drag
    let currentCornerRadius = state.effectiveCornerRadius
    let currentShadowIntensity = state.effectiveShadowIntensity

    Group {
      switch state.backgroundStyle {
      case .none:
        EmptyView()

      case .gradient(let preset):
        RoundedRectangle(cornerRadius: currentCornerRadius)
          .fill(LinearGradient(
            colors: preset.colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ))
          .frame(width: width, height: height)
          .shadow(
            color: .black.opacity(currentShadowIntensity),
            radius: 20,
            x: 0,
            y: 10
          )

      case .wallpaper(let url):
        // Check if this is a preset wallpaper
        if url.scheme == "preset", let presetName = url.host,
           let preset = WallpaperPreset(rawValue: presetName) {
          RoundedRectangle(cornerRadius: currentCornerRadius)
            .fill(preset.gradient)
            .frame(width: width, height: height)
            .shadow(
              color: .black.opacity(currentShadowIntensity),
              radius: 20,
              x: 0,
              y: 10
            )
        } else if let nsImage = state.cachedBackgroundImage {
          // Use CACHED image instead of loading from disk every render
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipped()
            .cornerRadius(currentCornerRadius)
        }

      case .blurred(let url):
        if url.scheme == "preset" {
          EmptyView()
        } else if let nsImage = state.cachedBlurredImage {
          // Use PRE-COMPUTED blur (no real-time processing)
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipped()
            .cornerRadius(currentCornerRadius)
        } else if let nsImage = state.cachedBackgroundImage {
          // Fallback: show non-blurred while computing
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipped()
            .cornerRadius(currentCornerRadius)
        }

      case .solidColor(let color):
        RoundedRectangle(cornerRadius: currentCornerRadius)
          .fill(color)
          .frame(width: width, height: height)
          .shadow(
            color: .black.opacity(currentShadowIntensity),
            radius: 20,
            x: 0,
            y: 10
          )
      }
    }
    .drawingGroup() // Rasterize to Metal texture for performance
  }

  // MARK: - Image Layer

  @ViewBuilder
  private func imageLayer(width: CGFloat, height: CGFloat) -> some View {
    // Use effective values for smooth preview during slider drag
    let currentCornerRadius = state.effectiveCornerRadius
    let currentShadowIntensity = state.effectiveShadowIntensity

    if let sourceImage = state.sourceImage {
      Image(nsImage: sourceImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: width, height: height)
        .cornerRadius(currentCornerRadius)
        .drawingGroup() // Rasterize image with corners for performance
        .shadow(
          color: .black.opacity(state.backgroundStyle != .none ? currentShadowIntensity : 0),
          radius: 15,
          x: 0,
          y: 8
        )
    }
  }

  // MARK: - Drag and Drop

  // MARK: - Keyboard Shortcuts

  /// Handle tool switching keyboard shortcuts
  private func handleToolShortcut(_ keyPress: KeyPress) -> KeyPress.Result {
    // Skip if editing text annotation
    guard state.editingTextAnnotationId == nil else {
      return .ignored
    }

    // Skip if no image loaded
    guard state.hasImage else {
      return .ignored
    }

    // Get lowercase character for case-insensitive matching
    guard let char = keyPress.characters.lowercased().first else {
      return .ignored
    }

    // Look up tool for this key
    guard let tool = AnnotateShortcutManager.shared.tool(for: char) else {
      return .ignored
    }

    // Special handling for crop tool
    if tool == .crop {
      state.selectedTool = .crop
      if state.cropRect == nil && state.hasImage {
        state.initializeCrop()
      } else if state.cropRect != nil {
        state.isCropActive = true
      }
    } else {
      state.selectedTool = tool
    }

    return .handled
  }

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

// MARK: - Crop Clip Shape

/// Shape that clips content to crop rect when applied, or shows full content when no crop
struct CropClipShape: Shape {
  let clipRect: CGRect?
  let containerSize: CGSize

  func path(in rect: CGRect) -> Path {
    if let clipRect = clipRect {
      // Clip to crop rect
      return Path(clipRect)
    } else {
      // No clip - show full content
      return Path(rect)
    }
  }
}
