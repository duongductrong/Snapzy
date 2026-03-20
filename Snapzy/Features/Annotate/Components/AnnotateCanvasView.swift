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

  /// Crop toolbar is only visible while the crop rect is actively editable.
  private var isCropToolbarVisible: Bool {
    state.selectedTool == .crop && state.isCropActive
  }

  var body: some View {
    VStack(spacing: 0) {
      GeometryReader { geometry in
        ZStack {
          // Background
//          Color(nsColor: .textBackgroundColor)

          if state.hasImage {
            // Centered, scaled canvas
            canvasContent(in: geometry.size)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .onAppear { state.canvasContainerSize = geometry.size }
              .onChange(of: geometry.size) { newSize in state.canvasContainerSize = newSize }
          } else {
            // Drop zone when no image loaded
            AnnotateDropZoneView(isDragOver: $isDragOver)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      if isCropToolbarVisible {
        HStack {
          Spacer(minLength: 0)
          CropToolbarView(state: state)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.2), value: isCropToolbarVisible)
    .onReceive(NotificationCenter.default.publisher(for: .annotateScrollZoom)) { notification in
      guard state.hasImage,
            let delta = notification.userInfo?["delta"] as? CGFloat else { return }
      let step = delta * 0.1
      withAnimation(.easeOut(duration: 0.15)) {
        state.zoomLevel = state.clampedZoom(state.zoomLevel + step)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .annotateMagnifyZoom)) { notification in
      guard state.hasImage,
            let magnification = notification.userInfo?["magnification"] as? CGFloat else { return }
      withAnimation(.easeOut(duration: 0.1)) {
        state.zoomLevel = state.clampedZoom(state.zoomLevel + magnification)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .annotateZoomIn)) { _ in
      guard state.hasImage else { return }
      withAnimation(.easeOut(duration: 0.15)) {
        state.zoomLevel = state.clampedZoom(state.zoomLevel + 0.25)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .annotateZoomOut)) { _ in
      guard state.hasImage else { return }
      withAnimation(.easeOut(duration: 0.15)) {
        state.zoomLevel = state.clampedZoom(state.zoomLevel - 0.25)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .annotateZoomReset)) { _ in
      guard state.hasImage else { return }
      withAnimation(.easeOut(duration: 0.15)) {
        state.zoomLevel = 1.0
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .annotateSpaceDown)) { _ in
      guard state.hasImage,
            state.zoomLevel > 1.0,
            state.editingTextAnnotationId == nil else { return }
      state.isSpacePanning = true
    }
    .onReceive(NotificationCenter.default.publisher(for: .annotateSpaceUp)) { _ in
      state.isSpacePanning = false
    }
    .onReceive(NotificationCenter.default.publisher(for: .annotatePanDrag)) { notification in
      guard state.isSpacePanning,
            let dx = notification.userInfo?["deltaX"] as? CGFloat,
            let dy = notification.userInfo?["deltaY"] as? CGFloat else { return }
      state.panOffset.width += dx
      state.panOffset.height += dy
      state.clampPanOffset()
    }
    .onChange(of: state.zoomLevel) { _ in
      state.resetPanIfNeeded()
    }
    .onDrop(of: [.fileURL, .image], isTargeted: $isDragOver) { providers in
      handleDrop(providers: providers)
    }
    .focusable()
    .modifier(FocusEffectDisabledModifier())
    .focused($isCanvasFocused)
    .background(
      KeyEventHandlerView { char in
        handleToolShortcutChar(char)
      }
    )
    .onAppear {
      isCanvasFocused = true
    }
    .overlay(alignment: .bottom) {
      if showDropError {
        dropErrorBanner
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
      .padding(.bottom, isCropToolbarVisible ? 96 : 20)
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

    // When crop is applied, use CROP dimensions for image display frame
    // This ensures the image frame fits within the background+padding area
    let imgWidth: CGFloat
    let imgHeight: CGFloat
    if isCropApplied, let cropRect = state.cropRect {
      imgWidth = cropRect.width * scale
      imgHeight = cropRect.height * scale
    } else {
      imgWidth = state.imageWidth * scale
      imgHeight = state.imageHeight * scale
    }

    // Image offset for alignment (relative to ZStack center)
    let imageDisplaySize = CGSize(width: imgWidth, height: imgHeight)

    // Calculate offset based on crop state
    let offset: CGPoint
    if isCropApplied {
      // When crop is applied, image frame is already crop-sized, use normal alignment
      offset = state.imageOffset(
        for: CGSize(width: bgWidth, height: bgHeight),
        imageDisplaySize: imageDisplaySize,
        displayPadding: currentPadding * scale
      )
    } else {
      // Normal alignment offset
      offset = state.imageOffset(
        for: CGSize(width: bgWidth, height: bgHeight),
        imageDisplaySize: imageDisplaySize,
        displayPadding: currentPadding * scale
      )
    }

    // Calculate clipping rect for applied crop (in display coordinates, relative to full image frame)
    // Used during crop EDITING to clip the drawing canvas
    let fullImgWidth = state.imageWidth * scale
    let fullImgHeight = state.imageHeight * scale
    let clipRect: CGRect? = (state.isCropActive && state.cropRect != nil) ? state.cropRect.map { cropRect in
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
          // When crop is applied, render only the cropped portion
          if isCropApplied, let cropRect = state.cropRect {
            croppedImageLayer(
              cropRect: cropRect,
              scale: scale
            )
          } else {
            imageLayer(width: imgWidth, height: imgHeight)
          }

          // Drawing canvas matches image position
          if isCropApplied, let cropRect = state.cropRect {
            let cropOffset = cropDisplayOffset(for: cropRect, scale: scale)

            // When crop is applied, clip drawing to crop dimensions
            CanvasDrawingView(state: state, displayScale: scale)
              .frame(width: fullImgWidth, height: fullImgHeight)
              .offset(x: cropOffset.x, y: cropOffset.y)
              .frame(width: imgWidth, height: imgHeight)
              .clipped()
          } else {
            CanvasDrawingView(state: state, displayScale: scale)
              .frame(width: imgWidth, height: imgHeight)
              .clipShape(
                CropClipShape(clipRect: clipRect, containerSize: CGSize(width: imgWidth, height: imgHeight))
              )
          }

          // Text editing overlay (when editing a text annotation)
          if state.editingTextAnnotationId != nil {
            if isCropApplied, let cropRect = state.cropRect {
              let cropOffset = cropDisplayOffset(for: cropRect, scale: scale)

              TextEditOverlay(
                state: state,
                scale: scale,
                imageSize: CGSize(width: state.imageWidth, height: state.imageHeight)
              )
              .frame(width: fullImgWidth, height: fullImgHeight)
              .offset(x: cropOffset.x, y: cropOffset.y)
              .frame(width: imgWidth, height: imgHeight)
              .clipped()
            } else {
              TextEditOverlay(
                state: state,
                scale: scale,
                imageSize: CGSize(width: state.imageWidth, height: state.imageHeight)
              )
              .frame(width: imgWidth, height: imgHeight)
            }
          }
        }
        .offset(x: offset.x, y: offset.y)
        .modifier(MockupTransformModifier(state: state, isEnabled: shouldShowMockupTransforms))

        // Crop overlay - ONLY shown during active crop editing (NOT when crop is just applied)
        // This prevents CropSolidMask from covering the gradient/wallpaper background
        if state.selectedTool == .crop && state.isCropActive {
          CropOverlayView(
            state: state,
            scale: scale,
            imageSize: CGSize(width: state.imageWidth, height: state.imageHeight)
          )
          .frame(width: fullImgWidth, height: fullImgHeight)
          .offset(x: offset.x, y: offset.y)
        }
      }
      .scaleEffect(state.zoomLevel)
      .offset(x: state.panOffset.width, y: state.panOffset.height)

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
        .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
        .shadow(
          color: .black.opacity(state.backgroundStyle != .none ? currentShadowIntensity : 0),
          radius: 15,
          x: 0,
          y: 8
        )
    }
  }

  // MARK: - Cropped Image Layer

  /// Renders only the cropped portion of the source image.
  /// Uses offset + frame + clipped pattern to display just the crop region.
  @ViewBuilder
  private func croppedImageLayer(
    cropRect: CGRect,
    scale: CGFloat
  ) -> some View {
    let currentCornerRadius = state.effectiveCornerRadius
    let currentShadowIntensity = state.effectiveShadowIntensity
    let cropOffset = cropDisplayOffset(for: cropRect, scale: scale)
    let cropWidth = cropRect.width * scale
    let cropHeight = cropRect.height * scale
    let fullImageWidth = state.imageWidth * scale
    let fullImageHeight = state.imageHeight * scale

    if let sourceImage = state.sourceImage {
      // Render full image, offset so crop region is at top-left, then clip
      Image(nsImage: sourceImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: fullImageWidth, height: fullImageHeight)
        .offset(x: cropOffset.x, y: cropOffset.y)
        .frame(width: cropWidth, height: cropHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
        .shadow(
          color: .black.opacity(state.backgroundStyle != .none ? currentShadowIntensity : 0),
          radius: 15,
          x: 0,
          y: 8
        )
    }
  }

  /// Aligns cropped content to the same visible crop window used by the image and canvas.
  private func cropDisplayOffset(for cropRect: CGRect, scale: CGFloat) -> CGPoint {
    let fullImageWidth = state.imageWidth * scale
    let fullImageHeight = state.imageHeight * scale
    let cropWidth = cropRect.width * scale
    let cropHeight = cropRect.height * scale

    return CGPoint(
      x: (fullImageWidth - cropWidth) / 2 - (cropRect.origin.x * scale),
      y: (fullImageHeight - cropHeight) / 2 - ((state.imageHeight - cropRect.origin.y - cropRect.height) * scale)
    )
  }

  // MARK: - Drag and Drop

  // MARK: - Keyboard Shortcuts

  /// Handle tool switching keyboard shortcuts (macOS 13+ compatible)
  private func handleToolShortcutChar(_ char: Character) {
    // Skip if no image loaded
    guard state.hasImage else { return }

    let lowered = Character(String(char).lowercased())

    // Look up tool for this key
    guard let tool = AnnotateShortcutManager.shared.tool(for: lowered) else { return }

    // Commit any active text edit before switching
    if state.editingTextAnnotationId != nil {
      state.commitTextEditing()
    }

    // Deselect active annotation when switching tools
    state.selectedAnnotationId = nil

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



// MARK: - Focus Effect Disabled Modifier (macOS 13 compat)

/// Wraps `.focusEffectDisabled()` which is only available on macOS 14+
private struct FocusEffectDisabledModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 14.0, *) {
      content.focusEffectDisabled()
    } else {
      content
    }
  }
}

// MARK: - Key Event Handler (macOS 13 compat, replaces .onKeyPress)

/// NSViewRepresentable that intercepts keyboard events via AppKit for macOS 13 compatibility
struct KeyEventHandlerView: NSViewRepresentable {
  let onKey: (Character) -> Void

  func makeNSView(context: Context) -> KeyEventNSView {
    KeyEventNSView(onKey: onKey)
  }

  func updateNSView(_ nsView: KeyEventNSView, context: Context) {
    nsView.onKey = onKey
  }
}

final class KeyEventNSView: NSView {
  var onKey: (Character) -> Void
  private var windowObserver: NSObjectProtocol?

  init(onKey: @escaping (Character) -> Void) {
    self.onKey = onKey
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // Remove old observer
    if let obs = windowObserver {
      NotificationCenter.default.removeObserver(obs)
      windowObserver = nil
    }

    guard let window = window else { return }

    // Grab first responder on initial attach
    DispatchQueue.main.async { [weak self] in
      self?.window?.makeFirstResponder(self)
    }

    // Watch for first responder changes — reclaim when focus goes
    // to a generic view (not DrawingCanvasNSView or text editor)
    windowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didUpdateNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      self?.reclaimFirstResponderIfNeeded()
    }
  }

  /// Reclaim first responder if no important view holds it
  private func reclaimFirstResponderIfNeeded() {
    guard let window = window else { return }
    let current = window.firstResponder

    // Already the first responder — nothing to do
    if current === self { return }

    // DrawingCanvasNSView has focus — it handles shortcuts too, leave it
    if current is DrawingCanvasNSView { return }

    // A text view has focus (e.g. TextEditor) — leave it for typing
    if current is NSTextView { return }

    // Generic view has focus (e.g. clicked empty area) — reclaim
    window.makeFirstResponder(self)
  }

  override func keyDown(with event: NSEvent) {
    guard let chars = event.charactersIgnoringModifiers, let char = chars.first else {
      super.keyDown(with: event)
      return
    }
    onKey(char)
  }

  deinit {
    if let obs = windowObserver {
      NotificationCenter.default.removeObserver(obs)
    }
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
