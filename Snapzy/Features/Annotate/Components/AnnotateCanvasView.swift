//
//  AnnotateCanvasView.swift
//  Snapzy
//
//  Canvas view displaying the image with annotations
//

import SwiftUI
import UniformTypeIdentifiers

private struct AnnotateViewportMetrics: Equatable {
  let containerSize: CGSize
  let baseCanvasSize: CGSize
  let fitScale: CGFloat
}

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
            .onAppear {
              state.updateViewportMetrics(containerSize: geometry.size, baseCanvasSize: .zero, fitScale: 1.0)
            }
            .onChange(of: geometry.size) { newSize in
              state.updateViewportMetrics(containerSize: newSize, baseCanvasSize: .zero, fitScale: 1.0)
            }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
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
            state.canPanInteractively,
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
      state.pan(by: CGSize(width: dx, height: dy))
    }
    .onReceive(NotificationCenter.default.publisher(for: .annotatePanScroll)) { notification in
      guard state.hasImage,
            state.canPanInteractively,
            state.editingTextAnnotationId == nil,
            let dx = notification.userInfo?["deltaX"] as? CGFloat,
            let dy = notification.userInfo?["deltaY"] as? CGFloat else { return }
      state.pan(by: CGSize(width: dx, height: dy))
    }
    .onChange(of: state.zoomLevel) { _ in
      state.resetPanIfNeeded()
    }
    .onChange(of: state.importWarningMessage) { message in
      guard let message else { return }
      showError(message)
      state.consumeImportWarningMessage()
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
    let availableWidth = max(containerSize.width - margin * 2, 1)
    let availableHeight = max(containerSize.height - margin * 2, 1)

    // Use effective values for smooth preview during slider drag
    let currentPadding = state.effectivePadding

    // Calculate alignment space needed for non-center alignments
    // This expands the background to allow image movement
    let alignmentSpace: CGFloat = state.imageAlignment != .center ? 40 : 0

    let imageBounds = state.sourceImageBounds
    let cropBounds = state.cropRect?.standardized

    let fitBounds: CGRect
    if let cropBounds, !state.isCropActive {
      fitBounds = cropBounds
    } else {
      fitBounds = imageBounds
    }

    // Scale is tied to the currently fitted image/crop, not to the live crop rect.
    // This keeps crop dimensions predictable while users drag handles outward.
    let fitLogicalCanvasWidth = fitBounds.width + currentPadding * 2 + alignmentSpace
    let fitLogicalCanvasHeight = fitBounds.height + currentPadding * 2 + alignmentSpace
    let scaleX = availableWidth / fitLogicalCanvasWidth
    let scaleY = availableHeight / fitLogicalCanvasHeight
    let scale = min(scaleX, scaleY, 1.0)

    let foregroundBounds: CGRect
    if let cropBounds {
      if state.isCropActive {
        foregroundBounds = cropWorkspaceBounds(
          for: imageBounds,
          availableSize: CGSize(width: availableWidth, height: availableHeight),
          scale: scale
        )
      } else {
        foregroundBounds = cropBounds
      }
    } else {
      foregroundBounds = imageBounds
    }

    // Logical canvas = effective size + padding + alignment space
    let logicalCanvasWidth = foregroundBounds.width + currentPadding * 2 + alignmentSpace
    let logicalCanvasHeight = foregroundBounds.height + currentPadding * 2 + alignmentSpace

    // Background = logical canvas * scale (includes padding + alignment space)
    let bgWidth = logicalCanvasWidth * scale
    let bgHeight = logicalCanvasHeight * scale
    let viewportMetrics = AnnotateViewportMetrics(
      containerSize: containerSize,
      baseCanvasSize: CGSize(width: bgWidth, height: bgHeight),
      fitScale: scale
    )

    let foregroundWidth = foregroundBounds.width * scale
    let foregroundHeight = foregroundBounds.height * scale
    let foregroundDisplaySize = CGSize(width: foregroundWidth, height: foregroundHeight)
    let offset = state.imageOffset(
      for: CGSize(width: bgWidth, height: bgHeight),
      imageDisplaySize: foregroundDisplaySize,
      displayPadding: currentPadding * scale
    )

    return ZStack {
      // Scaled content group
      ZStack {
        // Background layer (scaled canvas with padding) - NOT transformed
        backgroundLayer(width: bgWidth, height: bgHeight)

        // GROUP: Image + Annotations (transformed together in mockup mode)
        Group {
          sourceImageLayer(visibleBounds: foregroundBounds, scale: scale)

          CanvasDrawingView(state: state, displayScale: scale, canvasBounds: foregroundBounds)
            .frame(width: foregroundWidth, height: foregroundHeight)

          // Text editing overlay (when editing a text annotation)
          if state.editingTextAnnotationId != nil {
            TextEditOverlay(
              state: state,
              scale: scale,
              canvasBounds: foregroundBounds
            )
            .frame(width: foregroundWidth, height: foregroundHeight)
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
            canvasBounds: foregroundBounds
          )
          .frame(width: foregroundWidth, height: foregroundHeight)
          .offset(x: offset.x, y: offset.y)
        }
      }
      .scaleEffect(state.zoomLevel)
      .offset(x: state.panOffset.width, y: state.panOffset.height)
    }
    .onAppear {
      state.updateViewportMetrics(
        containerSize: viewportMetrics.containerSize,
        baseCanvasSize: viewportMetrics.baseCanvasSize,
        fitScale: viewportMetrics.fitScale
      )
    }
    .onChange(of: viewportMetrics) { newMetrics in
      state.updateViewportMetrics(
        containerSize: newMetrics.containerSize,
        baseCanvasSize: newMetrics.baseCanvasSize,
        fitScale: newMetrics.fitScale
      )
    }
  }

  private func cropWorkspaceBounds(for imageBounds: CGRect, availableSize: CGSize, scale: CGFloat) -> CGRect {
    let normalizedScale = max(scale, 0.0001)
    let minimumZoom = max(AnnotateState.minimumZoomLevel, 0.0001)
    let visibleWidthAtMinimumZoom = availableSize.width / (normalizedScale * minimumZoom)
    let visibleHeightAtMinimumZoom = availableSize.height / (normalizedScale * minimumZoom)
    let workspaceWidth = max(imageBounds.width * 3, visibleWidthAtMinimumZoom)
    let workspaceHeight = max(imageBounds.height * 3, visibleHeightAtMinimumZoom)

    return CGRect(
      x: imageBounds.midX - workspaceWidth / 2,
      y: imageBounds.midY - workspaceHeight / 2,
      width: workspaceWidth,
      height: workspaceHeight
    ).standardized
  }

  // MARK: - Background Layer

  @ViewBuilder
  private func backgroundLayer(width: CGFloat, height: CGFloat) -> some View {
    let currentShadowIntensity = state.effectiveShadowIntensity

    Group {
      switch state.backgroundStyle {
      case .none:
        EmptyView()

      case .gradient(let preset):
        Rectangle()
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
          Rectangle()
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
        } else if let nsImage = state.cachedBackgroundImage {
          // Fallback: show non-blurred while computing
          Image(nsImage: nsImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipped()
        }

      case .solidColor(let color):
        Rectangle()
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
  private func sourceImageLayer(visibleBounds: CGRect, scale: CGFloat) -> some View {
    let currentCornerRadius = state.effectiveCornerRadius
    let currentShadowIntensity = state.effectiveShadowIntensity
    let imageBounds = state.sourceImageBounds
    let imageOffset = displayOffset(for: imageBounds, in: visibleBounds, scale: scale)

    if let sourceImage = state.effectiveSourceImage {
      Image(nsImage: sourceImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: imageBounds.width * scale, height: imageBounds.height * scale)
        .offset(x: imageOffset.x, y: imageOffset.y)
        .frame(width: visibleBounds.width * scale, height: visibleBounds.height * scale)
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

  private func displayOffset(for contentBounds: CGRect, in visibleBounds: CGRect, scale: CGFloat) -> CGPoint {
    return CGPoint(
      x: (contentBounds.midX - visibleBounds.midX) * scale,
      y: (visibleBounds.midY - contentBounds.midY) * scale
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

    if tool == .crop {
      state.beginCropInteraction()
    } else {
      // Commit any active text edit before switching
      if state.editingTextAnnotationId != nil {
        state.commitTextEditing()
      }

      // Deselect active annotation when switching tools
      state.selectedAnnotationId = nil
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
            if !state.importImage(from: url) {
              showError("Failed to import image")
            }
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
              if !state.importImage(image, sourceURL: nil, sourceData: data) {
                showError("Failed to import image")
              }
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
