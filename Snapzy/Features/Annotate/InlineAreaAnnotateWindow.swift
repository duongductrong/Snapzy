//
//  InlineAreaAnnotateWindow.swift
//  Snapzy
//
//  Per-display overlays for selecting and annotating a screenshot region.
//

import AppKit
import SwiftUI

@MainActor
final class InlineAreaAnnotateCoordinator {
  static let shared = InlineAreaAnnotateCoordinator()
  private var activeWindows: [InlineAreaAnnotatePanel] = []
  private var previouslyActiveApplication: NSRunningApplication?

  func start(
    screens: [NSScreen],
    primaryDisplayID: CGDirectDisplayID,
    backdrops: [CGDirectDisplayID: AreaSelectionBackdrop],
    frozenSession: FrozenAreaCaptureSession,
    saveDirectory: URL,
    outputFormat: ImageFormat,
    context: CaptureContext = .empty,
    onComplete: @escaping (CaptureResult) -> Void
  ) {
    closeActiveWindows()
    let availableScreens = screens.filter { screen in
      guard let displayID = screen.displayID else { return false }
      return backdrops[displayID] != nil
    }
    guard !availableScreens.isEmpty else {
      onComplete(.failure(.noDisplayFound))
      return
    }

    previouslyActiveApplication = NSWorkspace.shared.frontmostApplication
    NSApp.activate(ignoringOtherApps: true)

    let wrappedOnComplete: (CaptureResult) -> Void = { [weak self] result in
      guard let self else {
        onComplete(result)
        return
      }
      self.previouslyActiveApplication?.activate(options: [])
      self.previouslyActiveApplication = nil
      onComplete(result)
    }

    let desktopFrame = InlineAreaAnnotateSession.desktopFrame(for: availableScreens.map(\.frame))
    let displays = availableScreens.compactMap { screen -> InlineAreaAnnotateDisplay? in
      guard let displayID = screen.displayID,
            let backdrop = backdrops[displayID] else { return nil }
      return InlineAreaAnnotateDisplay(
        displayID: displayID,
        screenFrame: screen.frame,
        localFrame: InlineAreaAnnotateSession.localFrame(for: screen.frame, in: desktopFrame),
        controlInsets: InlineAreaControlInsets(screen: screen),
        backdropImage: NSImage(cgImage: backdrop.image, size: screen.frame.size)
      )
    }
    guard !displays.isEmpty else {
      wrappedOnComplete(.failure(.noDisplayFound))
      return
    }

    let session = InlineAreaAnnotateSession(
      primaryDisplayID: primaryDisplayID,
      desktopFrame: desktopFrame,
      displays: displays,
      frozenSession: frozenSession,
      saveDirectory: saveDirectory,
      outputFormat: outputFormat,
      context: context,
      onComplete: wrappedOnComplete
    )

    let windows = displays.map { display in
      InlineAreaAnnotatePanel(display: display, session: session)
    }
    activeWindows = windows

    for window in windows {
      window.onClose = { [weak self, weak window] in
        guard let self, let window else { return }
        self.activeWindows.removeAll { $0 === window }
      }
      session.attach(window: window)
      window.orderFrontRegardless()
      if window.displayID == primaryDisplayID {
        window.makeKey()
      }
    }
    if !windows.contains(where: { $0.displayID == primaryDisplayID }) {
      windows.first?.makeKey()
    }
  }

  private func closeActiveWindows() {
    let windows = activeWindows
    activeWindows.removeAll()
    for window in windows {
      window.close()
    }
    previouslyActiveApplication?.activate(options: [])
    previouslyActiveApplication = nil
  }
}

final class InlineAreaAnnotatePanel: NSPanel {
  var onClose: (() -> Void)?
  let displayID: CGDirectDisplayID

  private let session: InlineAreaAnnotateSession
  private var didNotifyClose = false

  init(display: InlineAreaAnnotateDisplay, session: InlineAreaAnnotateSession) {
    displayID = display.displayID
    self.session = session
    super.init(
      contentRect: display.screenFrame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    isFloatingPanel = true
    isOpaque = false
    backgroundColor = .clear
    level = .screenSaver
    ignoresMouseEvents = false
    acceptsMouseMovedEvents = true
    isReleasedWhenClosed = false
    hasShadow = false
    hidesOnDeactivate = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    animationBehavior = .none
    becomesKeyOnlyIfNeeded = true

    isMovable = false
    isMovableByWindowBackground = false
    minSize = display.screenFrame.size
    maxSize = display.screenFrame.size
    if let nsAppearance = ThemeManager.shared.nsAppearance {
      appearance = nsAppearance
    } else {
      let isDark = ThemeManager.shared.systemAppearance == .dark
      appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    let rootView = InlineAreaAnnotateRootView(
      session: session,
      display: display
    )
    .preferredColorScheme(ThemeManager.shared.systemAppearance)
    let hostingView = InlineAreaHostingView(rootView: rootView)
    hostingView.session = session
    contentView = hostingView
  }

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    false
  }

  override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
    self.minSize = frameRect.size
    self.maxSize = frameRect.size
    super.setFrame(frameRect, display: displayFlag)
  }

  override func keyDown(with event: NSEvent) {
    if session.handleKeyEvent(event) { return }
    super.keyDown(with: event)
  }

  override func keyUp(with event: NSEvent) {
    if session.handleKeyEvent(event) { return }
    super.keyUp(with: event)
  }

  override func close() {
    super.close()
    guard !didNotifyClose else { return }
    didNotifyClose = true
    session.windowDidClose()
    onClose?()
  }
}

private final class InlineAreaHostingView: NSHostingView<AnyView> {
  var session: InlineAreaAnnotateSession?

  convenience init<Content: View>(rootView: Content) {
    self.init(rootView: AnyView(rootView))
  }

  required init(rootView: AnyView) {
    super.init(rootView: rootView)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
    true
  }

  override func resetCursorRects() {
    if let session, session.phase == .selecting {
      addCursorRect(bounds, cursor: NSCursor.vectorScreenshotCrosshairLight)
    } else {
      super.resetCursorRects()
    }
  }
}

private struct InlineAreaAnnotateRootView: View {
  @ObservedObject var session: InlineAreaAnnotateSession
  let display: InlineAreaAnnotateDisplay

  @State private var movingStartRect: CGRect?
  @State private var movingPreviewRect: CGRect?
  @State private var resizingStartRect: CGRect?
  @State private var resizePreviewRect: CGRect?
  @State private var activeResizeHandle: InlineAreaResizeHandle?
  @State private var cursorIndicatorPoint: CGPoint?
  @State private var propertiesContentWidth: CGFloat = 0

  var body: some View {
    GeometryReader { geometry in
      let desktopRect = resizePreviewRect ?? movingPreviewRect ?? session.selectionRect
      let viewportRect = desktopRect.map(rectInViewport)
      let isSelectionPreviewing = resizePreviewRect != nil || movingPreviewRect != nil
      let showsCursorIndicator = movingPreviewRect != nil

      ZStack(alignment: .topLeading) {
        ForEach(session.displays) { backdropDisplay in
          Image(nsImage: backdropDisplay.backdropImage)
            .resizable()
            .frame(width: backdropDisplay.localFrame.width, height: backdropDisplay.localFrame.height)
            .position(
              x: backdropDisplay.localFrame.midX - display.localFrame.minX,
              y: backdropDisplay.localFrame.midY - display.localFrame.minY
            )
        }

        selectionDimLayer(size: geometry.size, rect: viewportRect)

        if let desktopRect, let viewportRect {
          if session.phase == .annotating {
            annotateSurface(rect: viewportRect, usesBackdropPreview: isSelectionPreviewing)
            if session.isMoveModifierActive {
              spaceMoveHitArea(rect: viewportRect, desktopRect: desktopRect)
            }
            resizeHandles(rect: viewportRect, desktopRect: desktopRect)
            if session.controlDisplayID(for: desktopRect) == display.displayID {
              controls(rect: viewportRect, desktopRect: desktopRect, containerSize: geometry.size)
            }
          } else {
            selectionBorder(rect: viewportRect)
          }
        }

        if showsCursorIndicator, let cursorIndicatorPoint {
          InlineAreaCursorIndicator(point: cursorIndicatorPoint)
        }
      }
      .coordinateSpace(name: InlineAreaCoordinateSpace.root)
      .onContinuousHover(coordinateSpace: .named(InlineAreaCoordinateSpace.root)) { phase in
        switch phase {
        case let .active(location):
          cursorIndicatorPoint = location
          updateNativeCursorForIndicator(showsCursorIndicator)
        case .ended:
          cursorIndicatorPoint = nil
          InlineAreaNativeCursor.restoreArrow()
        }
      }
      .inlineAreaSelectionGesture(selectionGesture, isEnabled: session.phase == .selecting)
    }
    .ignoresSafeArea()
    .onAppear {
      if session.phase == .selecting {
        session.refreshCursor()
        DispatchQueue.main.async {
          session.refreshCursor()
          DispatchQueue.main.async {
            session.refreshCursor()
          }
        }
      }
    }
  }

  private var selectionGesture: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .named(InlineAreaCoordinateSpace.root))
      .onChanged { value in
        guard session.phase == .selecting else { return }
        let currentLocation = desktopPoint(for: value.location)
        cursorIndicatorPoint = value.location
        updateNativeCursorForIndicator(true)
        session.beginSelection(at: desktopPoint(for: value.startLocation))
        session.updateSelection(to: currentLocation)
      }
      .onEnded { value in
        guard session.phase == .selecting else { return }
        session.endSelection(at: desktopPoint(for: value.location))
        cursorIndicatorPoint = nil
        InlineAreaNativeCursor.restoreArrow()
      }
  }

  private func rectInViewport(_ desktopRect: CGRect) -> CGRect {
    desktopRect.offsetBy(dx: -display.localFrame.minX, dy: -display.localFrame.minY)
  }

  private func desktopPoint(for viewportPoint: CGPoint) -> CGPoint {
    CGPoint(
      x: viewportPoint.x + display.localFrame.minX,
      y: viewportPoint.y + display.localFrame.minY
    )
  }

  private func selectionDimLayer(size: CGSize, rect: CGRect?) -> some View {
    Canvas { context, canvasSize in
      var path = Path(CGRect(origin: .zero, size: canvasSize))
      if let rect {
        path.addPath(Path(rect.standardized))
      }
      context.fill(path, with: .color(.black.opacity(0.42)), style: FillStyle(eoFill: true))
    }
    .frame(width: size.width, height: size.height)
  }

  private func annotateSurface(rect: CGRect, usesBackdropPreview: Bool) -> some View {
    let imageSize = session.state.sourceImage?.size ?? rect.size
    let displayScale = max(rect.width / max(imageSize.width, 1), 0.0001)

    return ZStack {
      if !usesBackdropPreview, let image = session.state.effectiveSourceImage {
        Image(nsImage: image)
          .resizable()
          .frame(width: rect.width, height: rect.height)
      }

      CanvasDrawingView(
        state: session.state,
        displayScale: displayScale,
        canvasBounds: CGRect(origin: .zero, size: imageSize)
      )
      .frame(width: rect.width, height: rect.height)

      if session.state.editingTextAnnotationId != nil {
        TextEditOverlay(
          state: session.state,
          scale: displayScale,
          canvasBounds: CGRect(origin: .zero, size: imageSize)
        )
        .frame(width: rect.width, height: rect.height)
        .clipped()
      }
    }
    .frame(width: rect.width, height: rect.height)
    .overlay(
      selectionBorder(rect: CGRect(origin: .zero, size: rect.size))
        .allowsHitTesting(false)
    )
    .position(x: rect.midX, y: rect.midY)
  }

  private func spaceMoveHitArea(rect: CGRect, desktopRect: CGRect) -> some View {
    Color.clear
      .contentShape(Rectangle())
      .frame(width: rect.width, height: rect.height)
      .position(x: rect.midX, y: rect.midY)
      .gesture(moveGesture(for: desktopRect))
      .onHover { hovering in
        if hovering {
          NSCursor.openHand.set()
        } else {
          NSCursor.arrow.set()
        }
      }
  }

  @ViewBuilder
  private func controls(rect: CGRect, desktopRect: CGRect, containerSize: CGSize) -> some View {
    let placement = controlPlacement(
      for: rect,
      containerSize: containerSize,
      showsProperties: session.state.showsQuickPropertiesBar,
      propertiesContentWidth: propertiesContentWidth,
      controlInsets: display.controlInsets
    )

    InlineAreaControlDeck(
      session: session,
      maxWidth: placement.toolbarWidth,
      moveGesture: moveGesture(for: desktopRect)
    )
    .frame(width: placement.toolbarWidth, height: InlineAreaLayout.toolbarHeight)
    .position(placement.toolbarCenter)
    .transaction { transaction in
      transaction.animation = nil
    }

    InlineAreaPropertiesBar(
      state: session.state,
      maxWidth: placement.propertiesWidth,
      popoverEdge: placement.propertiesPopoverEdge,
      onContentWidthChange: { width in
        let roundedWidth = ceil(width)
        guard abs(propertiesContentWidth - roundedWidth) > 0.5 else { return }
        propertiesContentWidth = roundedWidth
      }
    )
    .frame(width: placement.propertiesWidth, height: InlineAreaLayout.propertiesHeight)
    .opacity(session.state.showsQuickPropertiesBar ? 1 : 0)
    .allowsHitTesting(session.state.showsQuickPropertiesBar)
    .position(placement.propertiesCenter)
    .transaction { transaction in
      transaction.animation = nil
    }

    InlineAreaActionRail(session: session)
      .frame(width: InlineAreaLayout.actionRailWidth, height: InlineAreaLayout.actionRailHeight)
      .position(placement.actionRailCenter)
      .transaction { transaction in
        transaction.animation = nil
      }
  }

  private func moveGesture(for desktopRect: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 2, coordinateSpace: .named(InlineAreaCoordinateSpace.root))
      .onChanged { value in
        guard activeResizeHandle == nil else { return }
        if movingStartRect == nil {
          movingStartRect = desktopRect
        }
        guard let start = movingStartRect else { return }
        let previewRect = session.clampedSelectionPreview(
          for: start.offsetBy(dx: value.translation.width, dy: value.translation.height)
        )
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
          cursorIndicatorPoint = value.location
          movingPreviewRect = previewRect
        }
        updateNativeCursorForIndicator(true)
      }
      .onEnded { value in
        let start = movingStartRect ?? desktopRect
        let finalRect = session.clampedSelectionPreview(
          for: start.offsetBy(dx: value.translation.width, dy: value.translation.height)
        )
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
          session.moveSelection(to: finalRect, refreshImage: true)
          movingPreviewRect = nil
          movingStartRect = nil
        }
        cursorIndicatorPoint = nil
        InlineAreaNativeCursor.restoreOpenHand()
      }
  }

  @ViewBuilder
  private func resizeHandles(rect: CGRect, desktopRect: CGRect) -> some View {
    InlineAreaResizeHandlesOverlay()
      .frame(width: rect.width, height: rect.height)
      .position(x: rect.midX, y: rect.midY)
      .allowsHitTesting(false)

    ForEach(InlineAreaResizeHandle.allCases) { handle in
      InlineAreaResizeHandleHitTarget(handle: handle)
        .position(handle.position(in: rect))
        .gesture(resizeGesture(
          for: handle,
          desktopRect: desktopRect,
          containerSize: session.desktopFrame.size
        ))
    }
  }

  private func resizeGesture(
    for handle: InlineAreaResizeHandle,
    desktopRect: CGRect,
    containerSize: CGSize
  ) -> some Gesture {
    DragGesture(minimumDistance: 1, coordinateSpace: .global)
      .onChanged { value in
        if resizingStartRect == nil {
          resizingStartRect = desktopRect
        }
        guard let start = resizingStartRect else { return }
        let previewRect = resizedSelectionRect(
          from: start,
          handle: handle,
          translation: value.translation,
          containerSize: containerSize
        )
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
          activeResizeHandle = handle
          movingPreviewRect = nil
          resizePreviewRect = previewRect
        }
      }
      .onEnded { value in
        let start = resizingStartRect ?? desktopRect
        let finalRect = resizedSelectionRect(
          from: start,
          handle: handle,
          translation: value.translation,
          containerSize: containerSize
        )
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
          session.resizeSelection(to: finalRect, previousRect: start)
          resizePreviewRect = nil
          resizingStartRect = nil
          activeResizeHandle = nil
        }
      }
  }

  private func resizedSelectionRect(
    from start: CGRect,
    handle: InlineAreaResizeHandle,
    translation: CGSize,
    containerSize: CGSize
  ) -> CGRect {
    let rect = start.standardized
    let minSize = InlineAreaLayout.minimumSelectionSize
    var minX = rect.minX
    var maxX = rect.maxX
    var minY = rect.minY
    var maxY = rect.maxY

    if handle.adjustsLeft {
      minX = clamped(rect.minX + translation.width, min: 0, max: maxX - minSize)
    }
    if handle.adjustsRight {
      maxX = clamped(rect.maxX + translation.width, min: minX + minSize, max: containerSize.width)
    }
    if handle.adjustsTop {
      minY = clamped(rect.minY + translation.height, min: 0, max: maxY - minSize)
    }
    if handle.adjustsBottom {
      maxY = clamped(rect.maxY + translation.height, min: minY + minSize, max: containerSize.height)
    }

    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
  }

  private func selectionBorder(rect: CGRect) -> some View {
    Rectangle()
      .strokeBorder(Color.white, lineWidth: InlineAreaResizeHandleChrome.borderWidth)
      .shadow(color: .black.opacity(0.45), radius: 2)
      .frame(width: rect.width, height: rect.height)
      .position(x: rect.midX, y: rect.midY)
  }

  private func controlPlacement(
    for rect: CGRect,
    containerSize: CGSize,
    showsProperties: Bool,
    propertiesContentWidth: CGFloat,
    controlInsets: InlineAreaControlInsets
  ) -> InlineAreaControlPlacement {
    InlineAreaControlGeometry.placement(
      for: rect,
      containerSize: containerSize,
      showsProperties: showsProperties,
      propertiesContentWidth: propertiesContentWidth,
      controlInsets: controlInsets
    )
  }

  private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
    guard minValue <= maxValue else { return value }
    return min(max(value, minValue), maxValue)
  }

  private func updateNativeCursorForIndicator(_ isIndicatorVisible: Bool) {
    if session.phase == .selecting {
      NSCursor.vectorScreenshotCrosshairLight.set()
    } else if isIndicatorVisible {
      InlineAreaNativeCursor.hide()
    } else {
      InlineAreaNativeCursor.restoreArrow()
    }
  }
}

private enum InlineAreaCoordinateSpace {
  static let root = "inline-area-annotate-root"
}

private struct InlineAreaCursorIndicator: View {
  let point: CGPoint

  private let frameSize: CGFloat = 28
  private let lineLength: CGFloat = 10

  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      var path = Path()
      path.move(to: CGPoint(x: center.x, y: center.y - lineLength))
      path.addLine(to: CGPoint(x: center.x, y: center.y + lineLength))
      path.move(to: CGPoint(x: center.x - lineLength, y: center.y))
      path.addLine(to: CGPoint(x: center.x + lineLength, y: center.y))

      context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 4)
      context.stroke(path, with: .color(.white), lineWidth: 1.5)
    }
    .frame(width: frameSize, height: frameSize)
    .position(point)
    .allowsHitTesting(false)
  }
}

private enum InlineAreaNativeCursor {
  private static let hiddenCursor: NSCursor = {
    let image = NSImage(size: NSSize(width: 1, height: 1))
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: 1,
      pixelsHigh: 1,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 4,
      bitsPerPixel: 32
    )
    if let rep {
      if let bitmapData = rep.bitmapData {
        for offset in 0 ..< (rep.bytesPerRow * rep.pixelsHigh) {
          bitmapData[offset] = 0
        }
      }
      image.addRepresentation(rep)
    }
    return NSCursor(image: image, hotSpot: .zero)
  }()

  static func hide() {
    hiddenCursor.set()
  }

  static func restoreArrow() {
    NSCursor.arrow.set()
  }

  static func restoreOpenHand() {
    NSCursor.openHand.set()
  }
}

private struct InlineAreaSelectionGestureModifier<SelectionGesture: Gesture>: ViewModifier {
  let selectionGesture: SelectionGesture
  let isEnabled: Bool

  func body(content: Content) -> some View {
    if isEnabled {
      content
        .contentShape(Rectangle())
        .gesture(selectionGesture)
    } else {
      content
    }
  }
}

private extension View {
  func inlineAreaSelectionGesture<SelectionGesture: Gesture>(
    _ selectionGesture: SelectionGesture,
    isEnabled: Bool
  ) -> some View {
    modifier(InlineAreaSelectionGestureModifier(
      selectionGesture: selectionGesture,
      isEnabled: isEnabled
    ))
  }
}

struct InlineAreaControlInsets: Equatable {
  var top: CGFloat
  var leading: CGFloat
  var bottom: CGFloat
  var trailing: CGFloat

  static let zero = InlineAreaControlInsets()

  init(
    top: CGFloat = 0,
    leading: CGFloat = 0,
    bottom: CGFloat = 0,
    trailing: CGFloat = 0
  ) {
    self.top = max(0, top)
    self.leading = max(0, leading)
    self.bottom = max(0, bottom)
    self.trailing = max(0, trailing)
  }

  init(screen: NSScreen) {
    self.init(
      screenFrame: screen.frame,
      visibleFrame: screen.visibleFrame,
      safeAreaInsets: screen.safeAreaInsets
    )
  }

  init(
    screenFrame: CGRect,
    visibleFrame: CGRect,
    safeAreaInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  ) {
    let visibleTop = max(0, screenFrame.maxY - visibleFrame.maxY)
    let visibleLeading = max(0, visibleFrame.minX - screenFrame.minX)
    let visibleBottom = max(0, visibleFrame.minY - screenFrame.minY)
    let visibleTrailing = max(0, screenFrame.maxX - visibleFrame.maxX)

    self.init(
      top: max(visibleTop, safeAreaInsets.top),
      leading: max(visibleLeading, safeAreaInsets.left),
      bottom: max(visibleBottom, safeAreaInsets.bottom),
      trailing: max(visibleTrailing, safeAreaInsets.right)
    )
  }

  var controlTopPadding: CGFloat {
    top + InlineAreaLayout.screenPadding
  }

  var controlLeadingPadding: CGFloat {
    leading + InlineAreaLayout.screenPadding
  }

  var controlBottomPadding: CGFloat {
    bottom + InlineAreaLayout.screenPadding
  }

  var controlTrailingPadding: CGFloat {
    trailing + InlineAreaLayout.screenPadding
  }
}

enum InlineAreaVerticalSide {
  case above
  case below
}

private enum InlineAreaResizeHandle: CaseIterable, Identifiable {
  case topLeft
  case top
  case topRight
  case right
  case bottomRight
  case bottom
  case bottomLeft
  case left

  var id: Self {
    self
  }

  var adjustsLeft: Bool {
    switch self {
    case .topLeft, .bottomLeft, .left:
      return true
    default:
      return false
    }
  }

  var adjustsRight: Bool {
    switch self {
    case .topRight, .right, .bottomRight:
      return true
    default:
      return false
    }
  }

  var adjustsTop: Bool {
    switch self {
    case .topLeft, .top, .topRight:
      return true
    default:
      return false
    }
  }

  var adjustsBottom: Bool {
    switch self {
    case .bottomLeft, .bottom, .bottomRight:
      return true
    default:
      return false
    }
  }

  var cursor: NSCursor {
    switch self {
    case .top, .bottom:
      return .resizeUpDown
    case .left, .right:
      return .resizeLeftRight
    case .topLeft, .bottomRight:
      return InlineAreaResizeCursor.diagonal(nwse: true)
    case .topRight, .bottomLeft:
      return InlineAreaResizeCursor.diagonal(nwse: false)
    }
  }

  func position(in rect: CGRect) -> CGPoint {
    switch self {
    case .topLeft:
      return CGPoint(x: rect.minX, y: rect.minY)
    case .top:
      return CGPoint(x: rect.midX, y: rect.minY)
    case .topRight:
      return CGPoint(x: rect.maxX, y: rect.minY)
    case .right:
      return CGPoint(x: rect.maxX, y: rect.midY)
    case .bottomRight:
      return CGPoint(x: rect.maxX, y: rect.maxY)
    case .bottom:
      return CGPoint(x: rect.midX, y: rect.maxY)
    case .bottomLeft:
      return CGPoint(x: rect.minX, y: rect.maxY)
    case .left:
      return CGPoint(x: rect.minX, y: rect.midY)
    }
  }
}

private enum InlineAreaResizeHandleChrome {
  static let borderWidth: CGFloat = 1.5
  static let hitSize: CGFloat = 24
  static let cornerLength: CGFloat = 20
  static let edgeLength: CGFloat = 24
  static let thickness: CGFloat = 3
}

private struct InlineAreaResizeHandlesOverlay: View {
  var body: some View {
    Canvas { context, size in
      let rect = CGRect(origin: .zero, size: size)
      let shortestSide = min(rect.width, rect.height)
      let cornerLength = min(
        InlineAreaResizeHandleChrome.cornerLength,
        max(10, shortestSide * 0.38)
      )

      drawCornerHandles(in: rect, length: cornerLength, context: &context)
      drawEdgeHandles(in: rect, cornerLength: cornerLength, context: &context)
    }
  }

  private func drawCornerHandles(
    in rect: CGRect,
    length: CGFloat,
    context: inout GraphicsContext
  ) {
    drawCorner(
      at: CGPoint(x: rect.minX, y: rect.minY),
      corner: .topLeft,
      length: length,
      context: &context
    )
    drawCorner(
      at: CGPoint(x: rect.maxX, y: rect.minY),
      corner: .topRight,
      length: length,
      context: &context
    )
    drawCorner(
      at: CGPoint(x: rect.minX, y: rect.maxY),
      corner: .bottomLeft,
      length: length,
      context: &context
    )
    drawCorner(
      at: CGPoint(x: rect.maxX, y: rect.maxY),
      corner: .bottomRight,
      length: length,
      context: &context
    )
  }

  private func drawCorner(
    at point: CGPoint,
    corner: InlineAreaResizeHandle,
    length: CGFloat,
    context: inout GraphicsContext
  ) {
    let thickness = InlineAreaResizeHandleChrome.thickness

    let horizontalRect: CGRect
    let verticalRect: CGRect

    switch corner {
    case .topLeft:
      horizontalRect = CGRect(x: point.x, y: point.y, width: length, height: thickness)
      verticalRect = CGRect(x: point.x, y: point.y, width: thickness, height: length)
    case .topRight:
      horizontalRect = CGRect(x: point.x - length, y: point.y, width: length, height: thickness)
      verticalRect = CGRect(x: point.x - thickness, y: point.y, width: thickness, height: length)
    case .bottomLeft:
      horizontalRect = CGRect(x: point.x, y: point.y - thickness, width: length, height: thickness)
      verticalRect = CGRect(x: point.x, y: point.y - length, width: thickness, height: length)
    case .bottomRight:
      horizontalRect = CGRect(x: point.x - length, y: point.y - thickness, width: length, height: thickness)
      verticalRect = CGRect(x: point.x - thickness, y: point.y - length, width: thickness, height: length)
    default:
      return
    }

    drawHandleBar(horizontalRect, context: &context)
    drawHandleBar(verticalRect, context: &context)
  }

  private func drawEdgeHandles(
    in rect: CGRect,
    cornerLength: CGFloat,
    context: inout GraphicsContext
  ) {
    let thickness = InlineAreaResizeHandleChrome.thickness
    let minimumGap: CGFloat = 12

    if rect.width >= cornerLength * 2 + minimumGap {
      let length = min(
        InlineAreaResizeHandleChrome.edgeLength,
        max(10, rect.width - cornerLength * 2 - 8)
      )
      let halfLength = length / 2
      drawHandleBar(
        CGRect(x: rect.midX - halfLength, y: rect.minY, width: length, height: thickness),
        context: &context
      )
      drawHandleBar(
        CGRect(x: rect.midX - halfLength, y: rect.maxY - thickness, width: length, height: thickness),
        context: &context
      )
    }

    if rect.height >= cornerLength * 2 + minimumGap {
      let length = min(
        InlineAreaResizeHandleChrome.edgeLength,
        max(10, rect.height - cornerLength * 2 - 8)
      )
      let halfLength = length / 2
      drawHandleBar(
        CGRect(x: rect.minX, y: rect.midY - halfLength, width: thickness, height: length),
        context: &context
      )
      drawHandleBar(
        CGRect(x: rect.maxX - thickness, y: rect.midY - halfLength, width: thickness, height: length),
        context: &context
      )
    }
  }

  private func drawHandleBar(_ rect: CGRect, context: inout GraphicsContext) {
    context.fill(
      Path(rect.offsetBy(dx: 0, dy: 1)),
      with: .color(.black.opacity(0.5))
    )
    context.fill(Path(rect), with: .color(.white))
  }
}

private struct InlineAreaResizeHandleHitTarget: View {
  let handle: InlineAreaResizeHandle

  var body: some View {
    Color.clear
      .frame(width: InlineAreaResizeHandleChrome.hitSize, height: InlineAreaResizeHandleChrome.hitSize)
      .contentShape(Rectangle())
      .onHover { hovering in
        if hovering {
          handle.cursor.set()
        } else {
          NSCursor.arrow.set()
        }
      }
  }
}

struct InlineAreaControlPlacement {
  let toolbarWidth: CGFloat
  let propertiesWidth: CGFloat
  let toolbarCenter: CGPoint
  let propertiesCenter: CGPoint
  let propertiesPopoverEdge: Edge
  let actionRailCenter: CGPoint
}

private enum InlineAreaToolbarMetrics {
  static let iconButtonSize: CGFloat = ToolbarConstants.iconButtonSize
  static let iconSize: CGFloat = ToolbarConstants.iconSize
  static let buttonCornerRadius: CGFloat = ToolbarConstants.buttonCornerRadius
  static let toolbarCornerRadius: CGFloat = ToolbarConstants.toolbarCornerRadius
  static let dividerHeight: CGFloat = ToolbarConstants.dividerHeight
  static let itemSpacing: CGFloat = ToolbarConstants.itemSpacing
  static let groupSpacing: CGFloat = ToolbarConstants.groupSpacing
  static let horizontalPadding: CGFloat = ToolbarConstants.horizontalPadding
  static let verticalPadding: CGFloat = ToolbarConstants.verticalPadding
  static let actionRailSpacing: CGFloat = ToolbarConstants.itemSpacing
  static let actionRailPadding: CGFloat = ToolbarConstants.verticalPadding
  static let actionRailDividerWidth: CGFloat = 24
  static let actionRailDividerHeight: CGFloat = 1
  static let actionRailDividerVerticalPadding: CGFloat = 4
  static let hoverAnimation: Animation = ToolbarConstants.hoverAnimation
}

enum InlineAreaLayout {
  static let toolbarHeight: CGFloat = InlineAreaToolbarMetrics.iconButtonSize + InlineAreaToolbarMetrics.verticalPadding * 2
  static let propertiesHeight: CGFloat = 38
  static let controlStackSpacing: CGFloat = 6
  static let selectionGap: CGFloat = 12
  static let screenPadding: CGFloat = 16
  static let controlPanelOuterHorizontalInset: CGFloat = 12
  static let minimumSelectionSize: CGFloat = 24
  static let actionRailWidth: CGFloat = InlineAreaToolbarMetrics.iconButtonSize + InlineAreaToolbarMetrics.actionRailPadding * 2
  static let actionRailHeight: CGFloat = InlineAreaToolbarMetrics.iconButtonSize * 4
    + InlineAreaToolbarMetrics.actionRailSpacing * 4
    + InlineAreaToolbarMetrics.actionRailDividerHeight
    + InlineAreaToolbarMetrics.actionRailDividerVerticalPadding * 2
    + InlineAreaToolbarMetrics.actionRailPadding * 2

  static func reservedControlHeight(showsProperties: Bool) -> CGFloat {
    if showsProperties {
      return toolbarHeight + controlStackSpacing + propertiesHeight
    }
    return toolbarHeight
  }
}

enum InlineAreaControlGeometry {
  static func placement(
    for rect: CGRect,
    containerSize: CGSize,
    showsProperties: Bool,
    propertiesContentWidth: CGFloat,
    controlInsets: InlineAreaControlInsets
  ) -> InlineAreaControlPlacement {
    let toolbarWidth = controlDeckWidth(
      for: containerSize,
      controlInsets: controlInsets
    )
    let propertiesWidth = propertiesBarWidth(
      for: containerSize,
      toolbarWidth: toolbarWidth,
      showsProperties: showsProperties,
      contentWidth: propertiesContentWidth,
      controlInsets: controlInsets
    )
    let toolbarX = clampedControlCenterX(
      rect.midX,
      width: toolbarWidth,
      containerSize: containerSize,
      controlInsets: controlInsets
    )
    let propertiesX = clampedControlCenterX(
      rect.midX,
      width: propertiesWidth,
      containerSize: containerSize,
      controlInsets: controlInsets
    )
    let verticalSide = preferredVerticalSide(
      for: rect,
      containerSize: containerSize,
      showsProperties: showsProperties,
      controlInsets: controlInsets
    )
    let centers = controlCenters(
      for: rect,
      side: verticalSide,
      containerSize: containerSize,
      showsProperties: showsProperties,
      controlInsets: controlInsets
    )
    let splitSides = splitControlSides(
      for: rect,
      preferredSide: verticalSide,
      containerSize: containerSize,
      showsProperties: showsProperties,
      controlInsets: controlInsets
    )
    let toolbarCenterY = splitSides == nil
      ? centers.toolbar
      : singleControlCenter(
        for: rect,
        height: InlineAreaLayout.toolbarHeight,
        side: splitSides?.toolbar ?? verticalSide,
        containerSize: containerSize,
        controlInsets: controlInsets
      )
    let propertiesCenterY = splitSides == nil
      ? centers.properties
      : singleControlCenter(
        for: rect,
        height: InlineAreaLayout.propertiesHeight,
        side: splitSides?.properties ?? verticalSide,
        containerSize: containerSize,
        controlInsets: controlInsets
      )
    let propertiesSide = splitSides?.properties ?? verticalSide

    return InlineAreaControlPlacement(
      toolbarWidth: toolbarWidth,
      propertiesWidth: propertiesWidth,
      toolbarCenter: CGPoint(x: toolbarX, y: toolbarCenterY),
      propertiesCenter: CGPoint(x: propertiesX, y: propertiesCenterY),
      propertiesPopoverEdge: propertiesSide == .above ? .bottom : .top,
      actionRailCenter: actionRailPosition(
        for: rect,
        containerSize: containerSize,
        controlInsets: controlInsets
      )
    )
  }

  private static func controlDeckWidth(
    for containerSize: CGSize,
    controlInsets: InlineAreaControlInsets
  ) -> CGFloat {
    min(664, availableControlWidth(for: containerSize, controlInsets: controlInsets))
  }

  private static func propertiesBarWidth(
    for containerSize: CGSize,
    toolbarWidth: CGFloat,
    showsProperties: Bool,
    contentWidth: CGFloat,
    controlInsets: InlineAreaControlInsets
  ) -> CGFloat {
    let availableWidth = availableControlWidth(for: containerSize, controlInsets: controlInsets)
    guard showsProperties else {
      return min(toolbarWidth, availableWidth)
    }

    let measuredContentWidth = contentWidth + InlineAreaLayout.controlPanelOuterHorizontalInset
    let measuredWidth = contentWidth > 0 ? measuredContentWidth : toolbarWidth
    return min(availableWidth, max(toolbarWidth, measuredWidth))
  }

  private static func availableControlWidth(
    for containerSize: CGSize,
    controlInsets: InlineAreaControlInsets
  ) -> CGFloat {
    max(
      0,
      containerSize.width - controlInsets.controlLeadingPadding - controlInsets.controlTrailingPadding
    )
  }

  private static func clampedControlCenterX(
    _ preferredX: CGFloat,
    width: CGFloat,
    containerSize: CGSize,
    controlInsets: InlineAreaControlInsets
  ) -> CGFloat {
    let minX = width / 2 + controlInsets.controlLeadingPadding
    let maxX = containerSize.width - width / 2 - controlInsets.controlTrailingPadding
    guard minX <= maxX else {
      return containerSize.width / 2
    }
    return clamped(preferredX, min: minX, max: maxX)
  }

  private static func preferredVerticalSide(
    for rect: CGRect,
    containerSize: CGSize,
    showsProperties: Bool,
    controlInsets: InlineAreaControlInsets
  ) -> InlineAreaVerticalSide {
    let reservedHeight = InlineAreaLayout.reservedControlHeight(showsProperties: showsProperties)
    let aboveSpace = spaceAbove(rect, controlInsets: controlInsets)
    let belowSpace = spaceBelow(rect, containerSize: containerSize, controlInsets: controlInsets)

    if aboveSpace >= reservedHeight {
      return .above
    }
    if belowSpace >= reservedHeight {
      return .below
    }
    if rect.minY <= controlInsets.controlTopPadding + InlineAreaLayout.selectionGap {
      return .below
    }
    return aboveSpace >= belowSpace ? .above : .below
  }

  private static func splitControlSides(
    for rect: CGRect,
    preferredSide: InlineAreaVerticalSide,
    containerSize: CGSize,
    showsProperties: Bool,
    controlInsets: InlineAreaControlInsets
  ) -> (toolbar: InlineAreaVerticalSide, properties: InlineAreaVerticalSide)? {
    guard showsProperties else { return nil }

    let aboveSpace = spaceAbove(rect, controlInsets: controlInsets)
    let belowSpace = spaceBelow(rect, containerSize: containerSize, controlInsets: controlInsets)

    if aboveSpace >= InlineAreaLayout.reservedControlHeight(showsProperties: true)
      || belowSpace >= InlineAreaLayout.reservedControlHeight(showsProperties: true)
    {
      return nil
    }

    switch preferredSide {
    case .above:
      if aboveSpace >= InlineAreaLayout.toolbarHeight,
         belowSpace >= InlineAreaLayout.propertiesHeight
      {
        return (.above, .below)
      }
      if aboveSpace >= InlineAreaLayout.propertiesHeight,
         belowSpace >= InlineAreaLayout.toolbarHeight
      {
        return (.below, .above)
      }
    case .below:
      if belowSpace >= InlineAreaLayout.toolbarHeight,
         aboveSpace >= InlineAreaLayout.propertiesHeight
      {
        return (.below, .above)
      }
      if belowSpace >= InlineAreaLayout.propertiesHeight,
         aboveSpace >= InlineAreaLayout.toolbarHeight
      {
        return (.above, .below)
      }
    }

    return nil
  }

  private static func controlCenters(
    for rect: CGRect,
    side: InlineAreaVerticalSide,
    containerSize: CGSize,
    showsProperties: Bool,
    controlInsets: InlineAreaControlInsets
  ) -> (toolbar: CGFloat, properties: CGFloat) {
    let reservedHeight = InlineAreaLayout.reservedControlHeight(showsProperties: showsProperties)
    let minGroupCenter = controlInsets.controlTopPadding + reservedHeight / 2
    let maxGroupCenter = containerSize.height - controlInsets.controlBottomPadding - reservedHeight / 2
    let rawGroupCenter: CGFloat

    switch side {
    case .above:
      rawGroupCenter = rect.minY - InlineAreaLayout.selectionGap - reservedHeight / 2
    case .below:
      rawGroupCenter = rect.maxY + InlineAreaLayout.selectionGap + reservedHeight / 2
    }

    let groupCenter = clamped(rawGroupCenter, min: minGroupCenter, max: maxGroupCenter)
    let groupTop = groupCenter - reservedHeight / 2
    let toolbarCenter = groupTop + InlineAreaLayout.toolbarHeight / 2
    let propertiesCenter = showsProperties
      ? groupTop + InlineAreaLayout.toolbarHeight + InlineAreaLayout.controlStackSpacing
      + InlineAreaLayout.propertiesHeight / 2
      : toolbarCenter

    return (toolbarCenter, propertiesCenter)
  }

  private static func singleControlCenter(
    for rect: CGRect,
    height: CGFloat,
    side: InlineAreaVerticalSide,
    containerSize: CGSize,
    controlInsets: InlineAreaControlInsets
  ) -> CGFloat {
    let rawCenter: CGFloat

    switch side {
    case .above:
      rawCenter = rect.minY - InlineAreaLayout.selectionGap - height / 2
    case .below:
      rawCenter = rect.maxY + InlineAreaLayout.selectionGap + height / 2
    }

    return clamped(
      rawCenter,
      min: controlInsets.controlTopPadding + height / 2,
      max: containerSize.height - controlInsets.controlBottomPadding - height / 2
    )
  }

  private static func actionRailPosition(
    for rect: CGRect,
    containerSize: CGSize,
    controlInsets: InlineAreaControlInsets
  ) -> CGPoint {
    let rightX = rect.maxX + InlineAreaLayout.actionRailWidth / 2 + InlineAreaLayout.selectionGap
    let leftX = rect.minX - InlineAreaLayout.actionRailWidth / 2 - InlineAreaLayout.selectionGap
    let minimumX = InlineAreaLayout.actionRailWidth / 2 + controlInsets.controlLeadingPadding
    let maximumX = containerSize.width - InlineAreaLayout.actionRailWidth / 2 - controlInsets.controlTrailingPadding
    let x: CGFloat
    if rightX <= maximumX {
      x = rightX
    } else if leftX >= minimumX {
      x = leftX
    } else {
      x = clamped(
        rect.maxX - InlineAreaLayout.actionRailWidth / 2 - InlineAreaLayout.selectionGap,
        min: minimumX,
        max: maximumX
      )
    }
    let y = clamped(
      rect.midY,
      min: InlineAreaLayout.actionRailHeight / 2 + controlInsets.controlTopPadding,
      max: containerSize.height - InlineAreaLayout.actionRailHeight / 2 - controlInsets.controlBottomPadding
    )
    return CGPoint(x: x, y: y)
  }

  private static func spaceAbove(
    _ rect: CGRect,
    controlInsets: InlineAreaControlInsets
  ) -> CGFloat {
    rect.minY - controlInsets.controlTopPadding - InlineAreaLayout.selectionGap
  }

  private static func spaceBelow(
    _ rect: CGRect,
    containerSize: CGSize,
    controlInsets: InlineAreaControlInsets
  ) -> CGFloat {
    containerSize.height - rect.maxY - controlInsets.controlBottomPadding - InlineAreaLayout.selectionGap
  }

  private static func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
    guard minValue <= maxValue else { return value }
    return min(max(value, minValue), maxValue)
  }
}

private enum InlineAreaChrome {
  static let cornerRadius: CGFloat = InlineAreaToolbarMetrics.toolbarCornerRadius
  static let controlCornerRadius: CGFloat = InlineAreaToolbarMetrics.buttonCornerRadius
  static let controlSize: CGFloat = InlineAreaToolbarMetrics.iconButtonSize
  static let moveControlWidth: CGFloat = 72
  static let propertyControlHeight: CGFloat = 24
  static let itemBackground = Color.primary.opacity(0.06)
  static let itemSelectedBackground = Color.primary.opacity(0.12)
  static let itemSelectedForeground = Color.primary
  static let itemSelectedBorder = Color.clear
  static let itemBorder = Color.clear
  static let divider = Color.primary.opacity(0.15)
  static let primaryText = Color.primary.opacity(0.86)
  static let secondaryText = Color.secondary.opacity(0.88)
  static let toolbarIconForeground = Color.primary.opacity(0.85)
  static let toolbarIconSelectedForeground = Color.primary
  static let toolbarIconInactiveToggleForeground = Color.primary.opacity(0.5)
  static let toolbarHoverBackground = Color.primary.opacity(0.10)
}

private struct InlineAreaPanelBorder: View {
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    RoundedRectangle(cornerRadius: InlineAreaChrome.cornerRadius, style: .continuous)
      .strokeBorder(
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12),
        lineWidth: 1.0
      )
  }
}

private struct InlineAreaPanelBackgroundTint: View {
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    if colorScheme == .dark {
      Color.black.opacity(0.25)
    } else {
      Color.white.opacity(0.15)
    }
  }
}

private extension View {
  func inlineAreaPanelChrome() -> some View {
    background(InlineAreaPanelBackgroundTint())
      .background(InlineAreaHudMaterialBackground(cornerRadius: InlineAreaChrome.cornerRadius))
      .clipShape(RoundedRectangle(cornerRadius: InlineAreaChrome.cornerRadius, style: .continuous))
      .overlay(InlineAreaPanelBorder())
      .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
      .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
  }
}

private struct InlineAreaHudMaterialBackground: NSViewRepresentable {
  let cornerRadius: CGFloat

  func makeNSView(context _: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    configure(view)
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
    configure(nsView)
  }

  private func configure(_ view: NSVisualEffectView) {
    view.material = .hudWindow
    view.state = .active
    view.blendingMode = .withinWindow
    view.wantsLayer = true
    view.layer?.cornerRadius = cornerRadius
    view.layer?.cornerCurve = .continuous
    view.layer?.masksToBounds = true

    // Explicitly set vibrancy appearance to match color scheme
    let isDark = ThemeManager.shared.systemAppearance == .dark
    view.appearance = NSAppearance(named: isDark ? .vibrantDark : .vibrantLight)
  }
}

private enum InlineAreaResizeCursor {
  static func diagonal(nwse: Bool) -> NSCursor {
    let size = NSSize(width: 16, height: 16)
    let image = NSImage(size: size)
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    NSColor.labelColor.setStroke()

    let path = NSBezierPath()
    path.lineWidth = 1.8
    path.lineCapStyle = .round

    if nwse {
      path.move(to: NSPoint(x: 3, y: 13))
      path.line(to: NSPoint(x: 13, y: 3))
      path.move(to: NSPoint(x: 3, y: 9))
      path.line(to: NSPoint(x: 3, y: 13))
      path.line(to: NSPoint(x: 7, y: 13))
      path.move(to: NSPoint(x: 9, y: 3))
      path.line(to: NSPoint(x: 13, y: 3))
      path.line(to: NSPoint(x: 13, y: 7))
    } else {
      path.move(to: NSPoint(x: 3, y: 3))
      path.line(to: NSPoint(x: 13, y: 13))
      path.move(to: NSPoint(x: 3, y: 7))
      path.line(to: NSPoint(x: 3, y: 3))
      path.line(to: NSPoint(x: 7, y: 3))
      path.move(to: NSPoint(x: 9, y: 13))
      path.line(to: NSPoint(x: 13, y: 13))
      path.line(to: NSPoint(x: 13, y: 9))
    }

    path.stroke()
    image.unlockFocus()
    return NSCursor(image: image, hotSpot: NSPoint(x: 8, y: 8))
  }
}

private struct InlineAreaControlDeck<MoveGesture: Gesture>: View {
  @ObservedObject var session: InlineAreaAnnotateSession
  let maxWidth: CGFloat
  let moveGesture: MoveGesture

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: InlineAreaToolbarMetrics.itemSpacing) {
        InlineAreaMoveHandle()
          .gesture(moveGesture)

        InlineAreaDivider()

        ForEach(Array(AnnotationToolType.inlineToolGroups.enumerated()), id: \.offset) { index, tools in
          if index > 0 {
            InlineAreaDivider()
          }
          InlineAreaToolGroup(tools: tools, selectedTool: session.state.selectedTool) { tool in
            session.state.activateTool(tool)
          }
        }

        InlineAreaDivider()

        InlineAreaIconButton(
          icon: "arrow.uturn.backward",
          tooltip: L10n.Common.undo,
          isEnabled: session.state.canUndo
        ) {
          session.state.undo()
        }

        InlineAreaIconButton(
          icon: "arrow.uturn.forward",
          tooltip: L10n.Common.redo,
          isEnabled: session.state.canRedo
        ) {
          session.state.redo()
        }
      }
      .fixedSize(horizontal: true, vertical: false)
    }
    .frame(maxWidth: max(0, maxWidth - InlineAreaToolbarMetrics.horizontalPadding * 2))
    .padding(.horizontal, InlineAreaToolbarMetrics.horizontalPadding)
    .padding(.vertical, InlineAreaToolbarMetrics.verticalPadding)
    .inlineAreaPanelChrome()
    .animation(.easeOut(duration: 0.16), value: session.state.selectedTool)
  }
}

private struct InlineAreaToolGroup: View {
  let tools: [AnnotationToolType]
  let selectedTool: AnnotationToolType
  let action: (AnnotationToolType) -> Void

  var body: some View {
    HStack(spacing: InlineAreaToolbarMetrics.groupSpacing) {
      ForEach(tools, id: \.self) { tool in
        InlineAreaToolButton(tool: tool, selectedTool: selectedTool) {
          action(tool)
        }
      }
    }
  }
}

private struct InlineAreaToolButton: View {
  let tool: AnnotationToolType
  let selectedTool: AnnotationToolType
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: tool.icon)
        .font(.system(size: InlineAreaToolbarMetrics.iconSize, weight: .medium))
        .foregroundColor(.primary.opacity(isSelected || isHovering ? 1.0 : 0.85))
        .frame(width: InlineAreaChrome.controlSize, height: InlineAreaChrome.controlSize)
        .background(buttonBackground)
        .contentShape(RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
    .help(tool.displayName)
    .onHover { isHovering = $0 }
    .animation(InlineAreaToolbarMetrics.hoverAnimation, value: isHovering)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var isSelected: Bool {
    selectedTool == tool
  }

  private var buttonBackground: some View {
    RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous)
      .fill(isSelected ? Color.primary.opacity(0.12) : (isHovering ? Color.primary.opacity(0.10) : Color.clear))
  }
}

private struct InlineAreaMoveHandle: View {
  @State private var isHovering = false

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
        .font(.system(size: 12, weight: .medium))

      Text("Space")
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
    }
    .foregroundColor(.primary.opacity(isHovering ? 1.0 : 0.85))
    .frame(width: InlineAreaChrome.moveControlWidth, height: InlineAreaChrome.controlSize)
    .background(
      RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous)
        .fill(isHovering ? Color.primary.opacity(0.10) : Color.clear)
    )
    .contentShape(RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous))
    .help(L10n.AnnotateUI.moveSelection)
    .onHover { isHovering = $0 }
    .animation(InlineAreaToolbarMetrics.hoverAnimation, value: isHovering)
  }
}

private struct InlineAreaIconButton: View {
  let icon: String
  let tooltip: String
  var isEnabled: Bool = true
  var isProminent: Bool = false
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: InlineAreaToolbarMetrics.iconSize, weight: .medium))
        .foregroundColor(foregroundColor)
        .frame(width: InlineAreaChrome.controlSize, height: InlineAreaChrome.controlSize)
        .background(background)
        .contentShape(RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.42)
    .help(tooltip)
    .onHover { isHovering = $0 }
    .animation(InlineAreaToolbarMetrics.hoverAnimation, value: isHovering)
  }

  private var foregroundColor: Color {
    .primary.opacity(isHovering || isProminent ? 1.0 : 0.85)
  }

  private var background: some View {
    RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous)
      .fill(isHovering ? Color.primary.opacity(0.10) : Color.clear)
  }
}

private struct InlineAreaDivider: View {
  var body: some View {
    RecordingToolbarDivider()
  }
}

private struct InlineAreaPropertiesBar: View {
  @ObservedObject var state: AnnotateState
  let maxWidth: CGFloat
  let popoverEdge: Edge
  let onContentWidthChange: (CGFloat) -> Void

  private let strokeColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]
  private let fillColors: [Color] = [.clear, .red, .orange, .yellow, .green, .blue, .purple, .white, .black]
  private let textBackgroundColors: [Color] = [.clear, .white, .black, .yellow, .blue]

  var body: some View {
    ZStack(alignment: .leading) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          contextPill

          if state.quickPropertiesSupportsStrokeColor {
            InlineAreaColorControl(
              title: colorTitle,
              selectedColor: state.quickStrokeColorBinding,
              colors: strokeColors,
              role: .annotationStroke,
              popoverEdge: popoverEdge
            )
          }

          if state.quickPropertiesSupportsFill {
            InlineAreaColorControl(
              title: L10n.Common.fill,
              selectedColor: state.quickFillColorBinding,
              colors: fillColors,
              role: .annotationFill,
              popoverEdge: popoverEdge
            )
          }

          if state.quickPropertiesSupportsTextBackground {
            InlineAreaColorControl(
              title: L10n.Common.background,
              selectedColor: state.quickTextBackgroundBinding,
              colors: textBackgroundColors,
              role: .textBackground,
              popoverEdge: popoverEdge
            )
          }

          if state.quickPropertiesSupportsBlurType {
            InlineAreaSegmentedPicker(
              title: L10n.AnnotateUI.blurType,
              items: BlurType.allCases,
              selection: state.quickBlurTypeBinding,
              icon: { $0.icon },
              tooltip: \.displayName
            )
          }

          if state.quickPropertiesSupportsArrowStyle {
            InlineAreaSegmentedPicker(
              title: L10n.Common.style,
              items: ArrowStyle.allCases,
              selection: state.quickArrowStyleBinding,
              icon: { $0.icon },
              isFlipped: { $0 == .curvedRight },
              tooltip: \.displayName
            )

            InlineAreaSegmentedPicker(
              title: L10n.Common.display,
              items: ArrowType.allCases,
              selection: state.quickArrowTypeBinding,
              icon: { $0.icon },
              isFlipped: { _ in state.arrowStyle == .curvedRight },
              tooltip: \.displayName
            )

            if state.quickPropertiesSupportsArrowBendDirection {
              InlineAreaArrowBendControl(
                bendDirection: state.quickArrowBendDirectionBinding
              )
            }

            if state.quickPropertiesSupportsArrowEndpoints {
              InlineAreaSegmentedPicker(
                title: L10n.AnnotateUI.arrowStartHead,
                items: ArrowEndpointStyle.allCases,
                selection: state.quickArrowStartHeadBinding,
                icon: { $0.icon },
                tooltip: \.displayName
              )

              InlineAreaSegmentedPicker(
                title: L10n.AnnotateUI.arrowEndHead,
                items: ArrowEndpointStyle.allCases,
                selection: state.quickArrowEndHeadBinding,
                icon: { $0.icon },
                tooltip: \.displayName
              )
            }
          }

          if state.quickPropertiesSupportsWatermark {
            InlineAreaTextFieldControl(title: L10n.Common.text, text: state.quickWatermarkTextBinding)

            InlineAreaSegmentedPicker(
              title: L10n.Common.style,
              items: WatermarkStyle.allCases,
              selection: state.quickWatermarkStyleBinding,
              icon: { $0.icon },
              tooltip: \.displayName
            )
          }

          if state.quickPropertiesSupportsStrokeWidth {
            InlineAreaSliderControl(
              title: state.quickStrokeWidthLabel,
              icon: state.quickStrokeWidthIcon,
              value: state.quickStrokeWidthBinding,
              range: AnnotationProperties.controlValueRange,
              step: 1,
              displayText: state.quickStrokeWidthDisplayText,
              onEditingChanged: state.setQuickPropertiesControlEditing
            )
          }

          if state.quickPropertiesSupportsTextFontSize {
            InlineAreaSliderControl(
              title: L10n.Common.size,
              icon: "textformat.size",
              value: state.quickTextFontSizeBinding,
              range: 12 ... 72,
              step: 1,
              displayText: "\(Int(state.quickTextFontSizeBinding.wrappedValue.rounded()))",
              onEditingChanged: state.setQuickPropertiesControlEditing
            )
          }

          if state.quickPropertiesSupportsCornerRadius {
            InlineAreaSliderControl(
              title: L10n.Common.corners,
              icon: "roundedbottom.horizontal",
              value: state.quickCornerRadiusBinding,
              range: 0 ... 60,
              step: 1,
              displayText: "\(Int(state.quickCornerRadiusBinding.wrappedValue.rounded()))",
              onEditingChanged: state.setQuickPropertiesControlEditing
            )
          }

          if state.quickPropertiesSupportsWatermark {
            InlineAreaSliderControl(
              title: L10n.AnnotateUI.watermarkOpacity,
              icon: "circle.lefthalf.filled",
              value: state.quickWatermarkOpacityBinding,
              range: 0.05 ... 0.65,
              step: 0.01,
              displayText: "\(Int((state.quickWatermarkOpacityBinding.wrappedValue * 100).rounded()))%",
              onEditingChanged: state.setQuickPropertiesControlEditing
            )

            InlineAreaSliderControl(
              title: L10n.Common.rotation,
              icon: "rotate.right",
              value: state.quickWatermarkRotationBinding,
              range: -45 ... 45,
              step: 1,
              displayText: "\(Int(state.quickWatermarkRotationBinding.wrappedValue.rounded()))deg",
              onEditingChanged: state.setQuickPropertiesControlEditing
            )
          }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
          GeometryReader { proxy in
            Color.clear.preference(
              key: InlineAreaPropertiesContentWidthKey.self,
              value: proxy.size.width
            )
          }
        )
      }
      .frame(maxWidth: max(0, maxWidth - InlineAreaLayout.controlPanelOuterHorizontalInset))
    }
    .frame(width: maxWidth, height: InlineAreaLayout.propertiesHeight, alignment: .leading)
    .inlineAreaPanelChrome()
    .onPreferenceChange(InlineAreaPropertiesContentWidthKey.self) { width in
      onContentWidthChange(max(0, width))
    }
  }

  private var colorTitle: String {
    state.quickPropertiesTool == .text ? L10n.Common.text : L10n.Common.color
  }

  private var contextPill: some View {
    HStack(spacing: 6) {
      Image(systemName: state.quickPropertiesTool?.icon ?? "slider.horizontal.3")
        .font(.system(size: 11, weight: .bold))

      Text(state.quickPropertiesContextTitle)
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .foregroundColor(InlineAreaChrome.primaryText)
    .padding(.horizontal, 8)
    .frame(height: InlineAreaChrome.propertyControlHeight)
    .frame(maxWidth: 142)
    .background(
      Capsule()
        .fill(InlineAreaChrome.itemBackground)
    )
  }
}

private struct InlineAreaPropertiesContentWidthKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

private struct InlineAreaColorControl: View {
  let title: String
  @Binding var selectedColor: Color
  let colors: [Color]
  let role: AnnotateColorPaletteRole
  let popoverEdge: Edge

  @ObservedObject private var paletteStore = AnnotateColorPaletteStore.shared
  @State private var showsPopover = false

  var body: some View {
    InlineAreaPropertyGroup(title: title) {
      HStack(spacing: 5) {
        Button {
          showsPopover.toggle()
        } label: {
          HStack(spacing: 5) {
            InlineAreaColorSwatch(color: selectedColor, isSelected: false, size: 15)
            Image(systemName: "chevron.down")
              .font(.system(size: 8, weight: .bold))
              .foregroundColor(InlineAreaChrome.secondaryText)
          }
          .frame(width: 40, height: InlineAreaChrome.propertyControlHeight)
          .background(
            RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous)
              .fill(InlineAreaChrome.itemBackground)
          )
        }
        .buttonStyle(.plain)
        .help(title)
        .popover(isPresented: $showsPopover, arrowEdge: popoverEdge) {
          InlineAreaColorPopover(
            title: title,
            selectedColor: $selectedColor,
            colors: colors,
            role: role
          ) {
            showsPopover = false
          }
        }

        ForEach(Array(paletteStore.favoriteColors(for: role).prefix(3)), id: \.self) { color in
          Button {
            selectedColor = color
          } label: {
            InlineAreaColorSwatch(
              color: color,
              isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
              size: 15
            )
            .frame(width: 20, height: InlineAreaChrome.propertyControlHeight)
          }
          .buttonStyle(.plain)
          .help(L10n.Common.favorite)
          .annotateColorDraggable(color, sourceFavoriteRole: role)
        }
      }
    }
  }
}

private struct InlineAreaColorPopover: View {
  let title: String
  @Binding var selectedColor: Color
  let colors: [Color]
  let role: AnnotateColorPaletteRole
  let dismiss: () -> Void

  @ObservedObject private var paletteStore = AnnotateColorPaletteStore.shared
  @State private var draftCustomColor = Color.red
  @State private var activeDraftTarget: ColorDraftTarget?
  @State private var originalSelectedColor: Color?
  @State private var showsFavoriteSelectionPopover = false

  private enum ColorDraftTarget {
    case customPalette
    case favorite
  }

  private let columns = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 5)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(Typography.labelMedium)
        .foregroundColor(.secondary)
        .lineLimit(1)

      let favorites = favoriteColors
      if !favorites.isEmpty {
        Text(L10n.Common.favorite)
          .font(Typography.labelSmall)
          .foregroundColor(.secondary)

        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
          ForEach(favorites, id: \.self) { color in
            favoriteColorButton(color)
          }

          if canAddFavorite {
            favoriteDropSlot
          }
        }
      } else {
        Text(L10n.Common.favorite)
          .font(Typography.labelSmall)
          .foregroundColor(.secondary)

        favoriteEmptyDropTarget
      }

      Divider()

      Text(L10n.Common.colors)
        .font(Typography.labelSmall)
        .foregroundColor(.secondary)

      LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
        ForEach(colors, id: \.self) { color in
          paletteColorButton(color, overlayAction: nil, overlayHelp: "")
        }

        ForEach(paletteStore.customColors, id: \.self) { color in
          paletteColorButton(
            color,
            overlayAction: {
              paletteStore.removeColor(color)
            },
            overlayHelp: L10n.Common.deleteAction
          )
        }

        if activeDraftTarget == .customPalette {
          draftCustomColorButton
        }

        if activeDraftTarget != .customPalette {
          Button {
            beginCustomColorDraft()
          } label: {
            AnnotateAddColorSwatch(size: 22)
          }
          .buttonStyle(.plain)
          .help(L10n.Common.custom)
          .accessibilityLabel(L10n.Common.custom)
        }
      }

      if activeDraftTarget == .customPalette {
        colorPickerPanel
          .padding(.top, 2)
      }
    }
    .padding(12)
    .frame(width: 196, alignment: .leading)
    .onAppear {
      syncDraftColor(with: selectedColor)
    }
    .onChange(of: selectedColor) { color in
      syncDraftColor(with: color)
    }
    .onChange(of: favoriteColors.count) { count in
      if count >= AnnotateColorPaletteStore.maximumFavoriteColorCount {
        closeFavoriteSelectionPopover()
      }
    }
    .onDisappear {
      showsFavoriteSelectionPopover = false
      cancelCustomColorDraftIfNeeded(keepFavoriteSelectionPopoverOpen: false)
    }
  }

  private var favoriteColors: [Color] {
    paletteStore.favoriteColors(for: role)
  }

  private var canAddFavorite: Bool {
    favoriteColors.count < AnnotateColorPaletteStore.maximumFavoriteColorCount
  }

  private var favoriteVaultColors: [Color] {
    guard canAddFavorite else { return [] }

    return (colors + paletteStore.customColors).reduce(into: [Color]()) { result, color in
      guard !AnnotateColorPaletteStore.isClear(color),
            !paletteStore.isFavorite(color, for: role),
            !result.contains(where: { AnnotateColorPaletteStore.colorsMatch($0, color) })
      else {
        return
      }

      result.append(color)
    }
  }

  private var favoriteDropSlot: some View {
    InlineAreaFavoriteDropSlot(
      onTap: showFavoriteSelectionPopover
    ) { payload in
      handleFavoriteDrop(payload)
    }
    .popover(isPresented: $showsFavoriteSelectionPopover, arrowEdge: .trailing) {
      favoriteSelectionPopover
    }
  }

  private var favoriteEmptyDropTarget: some View {
    InlineAreaFavoriteEmptyDropTarget(
      onTap: showFavoriteSelectionPopover
    ) { payload in
      handleFavoriteDrop(payload)
    }
    .popover(isPresented: $showsFavoriteSelectionPopover, arrowEdge: .trailing) {
      favoriteSelectionPopover
    }
  }

  private var favoriteSelectionPopover: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(L10n.Common.colors)
        .font(Typography.labelSmall)
        .foregroundColor(.secondary)

      LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
        ForEach(favoriteVaultColors, id: \.self) { color in
          favoriteVaultColorButton(color)
        }

        if activeDraftTarget == .favorite {
          draftFavoriteColorButton
        }

        if activeDraftTarget != .favorite && canAddFavorite {
          Button {
            beginFavoriteColorDraft()
          } label: {
            AnnotateAddColorSwatch(size: 22)
          }
          .buttonStyle(.plain)
          .help(L10n.Common.custom)
          .accessibilityLabel(L10n.Common.custom)
        }
      }

      if activeDraftTarget == .favorite {
        colorPickerPanel
          .padding(.top, 2)
      }
    }
    .padding(12)
    .frame(width: 196, alignment: .leading)
    .onDisappear {
      if activeDraftTarget == .favorite {
        cancelColorDraft(keepFavoriteSelectionPopoverOpen: false)
      }
    }
  }

  private var draftFavoriteColorButton: some View {
    InlineAreaColorSwatch(
      color: draftCustomColor,
      isSelected: true,
      size: 22
    )
    .contentShape(Circle())
    .onTapGesture {
      selectedColor = draftCustomColor
    }
    .frame(width: 24, height: 24)
    .help(L10n.Common.custom)
  }

  private var draftCustomColorButton: some View {
    InlineAreaColorSwatch(
      color: draftCustomColor,
      isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, draftCustomColor),
      size: 22
    )
    .contentShape(Circle())
    .onTapGesture {
      selectedColor = draftCustomColor
    }
    .frame(width: 24, height: 24)
    .help(L10n.Common.custom)
  }

  private var colorPickerPanel: some View {
    AnnotateCustomColorPickerPanel(
      selectedColor: $selectedColor,
      draftColor: $draftCustomColor,
      onCancel: {
        cancelColorDraft()
      },
      onApply: applyColorDraft
    )
  }

  private func favoriteVaultColorButton(_ color: Color) -> some View {
    InlineAreaPaletteColorButton(
      color: color,
      title: AnnotateColorPaletteStore.isClear(color) ? L10n.Common.none : title,
      isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
      sourceFavoriteRole: nil,
      overlayAction: nil,
      overlayHelp: "",
      onSelect: {
        addVaultColorToFavorites(color)
      }
    )
  }

  private func syncDraftColor(with color: Color) {
    guard !AnnotateColorPaletteStore.isClear(color) else { return }
    draftCustomColor = color
  }

  private func selectColorAndDismiss(_ color: Color) {
    originalSelectedColor = nil
    activeDraftTarget = nil
    showsFavoriteSelectionPopover = false
    selectedColor = color
    dismiss()
  }

  private func beginCustomColorDraft() {
    showsFavoriteSelectionPopover = false
    beginColorDraft(target: .customPalette)
  }

  private func showFavoriteSelectionPopover() {
    guard canAddFavorite else {
      closeFavoriteSelectionPopover()
      return
    }

    if activeDraftTarget == .customPalette {
      cancelColorDraft()
    }

    showsFavoriteSelectionPopover = true
  }

  private func beginFavoriteColorDraft() {
    guard canAddFavorite else {
      closeFavoriteSelectionPopover()
      return
    }

    beginColorDraft(target: .favorite)
  }

  private func beginColorDraft(target: ColorDraftTarget) {
    if activeDraftTarget != nil {
      cancelColorDraft()
    }

    originalSelectedColor = selectedColor
    syncDraftColor(with: selectedColor)
    selectedColor = draftCustomColor
    activeDraftTarget = target
  }

  private func applyColorDraft() {
    guard !AnnotateColorPaletteStore.isClear(draftCustomColor) else { return }

    let target = activeDraftTarget

    switch target {
    case .customPalette:
      paletteStore.addColor(draftCustomColor)
    case .favorite:
      guard canAddFavorite else {
        cancelColorDraft(keepFavoriteSelectionPopoverOpen: false)
        return
      }

      paletteStore.addColor(draftCustomColor)
      paletteStore.addFavorite(draftCustomColor, for: role)
    case nil:
      return
    }

    selectedColor = draftCustomColor
    originalSelectedColor = nil
    activeDraftTarget = nil
    if target == .favorite {
      showsFavoriteSelectionPopover = false
    }
  }

  private func cancelColorDraft(keepFavoriteSelectionPopoverOpen: Bool = true) {
    let target = activeDraftTarget
    let shouldKeepFavoriteSelectionPopover = target == .favorite && keepFavoriteSelectionPopoverOpen

    guard let originalSelectedColor else {
      activeDraftTarget = nil
      if target == .favorite {
        showsFavoriteSelectionPopover = shouldKeepFavoriteSelectionPopover
      }
      return
    }

    selectedColor = originalSelectedColor
    draftCustomColor = originalSelectedColor
    self.originalSelectedColor = nil
    activeDraftTarget = nil
    if target == .favorite {
      showsFavoriteSelectionPopover = shouldKeepFavoriteSelectionPopover
    }
  }

  private func cancelCustomColorDraftIfNeeded(keepFavoriteSelectionPopoverOpen: Bool = true) {
    guard activeDraftTarget != nil else { return }
    cancelColorDraft(keepFavoriteSelectionPopoverOpen: keepFavoriteSelectionPopoverOpen)
  }

  private func closeFavoriteSelectionPopover() {
    showsFavoriteSelectionPopover = false
    if activeDraftTarget == .favorite {
      cancelColorDraft(keepFavoriteSelectionPopoverOpen: false)
    }
  }

  private func addVaultColorToFavorites(_ color: Color) {
    guard canAddFavorite else {
      closeFavoriteSelectionPopover()
      return
    }

    originalSelectedColor = nil
    activeDraftTarget = nil
    paletteStore.addFavorite(color, for: role)
    selectedColor = color
    showsFavoriteSelectionPopover = false
  }

  private func favoriteColorButton(_ color: Color) -> some View {
    InlineAreaPaletteColorButton(
      color: color,
      title: AnnotateColorPaletteStore.isClear(color) ? L10n.Common.none : title,
      isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
      sourceFavoriteRole: role,
      overlayAction: {
        paletteStore.removeFavorite(color, for: role)
      },
      overlayHelp: L10n.Common.deleteAction,
      onDropPayload: { payload in
        handleFavoriteDrop(payload, targetColor: color)
      },
      onSelect: {
        selectColorAndDismiss(color)
      }
    )
  }

  private func paletteColorButton(
    _ color: Color,
    overlayAction: (() -> Void)?,
    overlayHelp: String
  ) -> some View {
    InlineAreaPaletteColorButton(
      color: color,
      title: AnnotateColorPaletteStore.isClear(color) ? L10n.Common.none : title,
      isSelected: AnnotateColorPaletteStore.colorsMatch(selectedColor, color),
      sourceFavoriteRole: nil,
      overlayAction: overlayAction,
      overlayHelp: overlayHelp,
      onSelect: {
        selectColorAndDismiss(color)
      }
    )
  }

  private func handleFavoriteDrop(_ payload: AnnotateColorDragPayload) {
    guard canAcceptFavoriteDrop(payload) else { return }

    paletteStore.acceptFavoriteDrop(
      payload,
      for: role
    )
    if !canAddFavorite {
      closeFavoriteSelectionPopover()
    }
  }

  private func handleFavoriteDrop(
    _ payload: AnnotateColorDragPayload,
    targetColor: Color
  ) {
    guard canAcceptFavoriteDrop(payload) else { return }

    paletteStore.acceptFavoriteDrop(
      payload,
      for: role,
      targetColor: targetColor
    )
    if !canAddFavorite {
      closeFavoriteSelectionPopover()
    }
  }

  private func canAcceptFavoriteDrop(_ payload: AnnotateColorDragPayload) -> Bool {
    paletteStore.isFavorite(payload.color, for: role) || canAddFavorite
  }
}

private struct InlineAreaPaletteColorButton: View {
  let color: Color
  let title: String
  let isSelected: Bool
  let sourceFavoriteRole: AnnotateColorPaletteRole?
  let overlayAction: (() -> Void)?
  let overlayHelp: String
  var onDropPayload: ((AnnotateColorDragPayload) -> Void)? = nil
  let onSelect: () -> Void

  var body: some View {
    if let onDropPayload {
      content
        .onDrop(of: AnnotateColorDragPayload.supportedContentTypes, isTargeted: $isDropTargeted) { providers in
          AnnotateColorDragPayload.load(from: providers) { payload in
            guard let payload else { return }
            onDropPayload(payload)
          }
        }
    } else {
      content
    }
  }

  @State private var isDropTargeted = false

  private var content: some View {
    ZStack(alignment: .topTrailing) {
      InlineAreaColorSwatch(
        color: color,
        isSelected: isSelected,
        size: 22
      )
      .contentShape(Circle())
      .onTapGesture(perform: onSelect)
      .help(title)
      .annotateColorDraggable(color, sourceFavoriteRole: sourceFavoriteRole)

      if let overlayAction {
        Button(action: overlayAction) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color.white, Color.secondary.opacity(0.9))
            .background(
              Circle()
                .fill(InlineAreaChrome.itemBackground)
                .frame(width: 8, height: 8)
            )
        }
        .buttonStyle(.plain)
        .offset(x: 5, y: -5)
        .help(overlayHelp)
      }

      if isDropTargeted {
        Circle()
          .stroke(Color.accentColor.opacity(0.75), lineWidth: 2)
          .frame(width: 28, height: 28)
      }
    }
    .frame(width: 24, height: 24)
  }
}

private struct InlineAreaFavoriteEmptyDropTarget: View {
  let onTap: () -> Void
  let onDropPayload: (AnnotateColorDragPayload) -> Void

  @State private var isTargeted = false

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: isTargeted ? "arrow.down" : "plus")
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(isTargeted ? .accentColor : .secondary)
        .frame(width: 24, height: 24)
        .background(Circle().fill(isTargeted ? Color.accentColor.opacity(0.1) : InlineAreaChrome.itemBackground.opacity(0.75)))
        .overlay(
          Circle()
            .stroke(
              isTargeted ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.35),
              style: StrokeStyle(lineWidth: 1, dash: [3, 2])
            )
        )

      Text(L10n.Common.dragColorsHere)
        .font(Typography.labelSmall)
        .lineLimit(1)
    }
    .foregroundColor(isTargeted ? .accentColor : .secondary)
    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    .contentShape(Rectangle())
    .help(L10n.Common.custom)
    .accessibilityLabel(L10n.Common.custom)
    .onTapGesture(perform: onTap)
    .accessibilityAddTraits(.isButton)
    .onDrop(of: AnnotateColorDragPayload.supportedContentTypes, isTargeted: $isTargeted) { providers in
      AnnotateColorDragPayload.load(from: providers) { payload in
        guard let payload else { return }
        onDropPayload(payload)
      }
    }
  }
}

private struct InlineAreaFavoriteDropSlot: View {
  let onTap: () -> Void
  let onDropPayload: (AnnotateColorDragPayload) -> Void

  @State private var isTargeted = false

  var body: some View {
    Image(systemName: isTargeted ? "arrow.down" : "plus")
      .font(.system(size: 9, weight: .semibold))
      .foregroundColor(isTargeted ? .accentColor : .secondary)
      .frame(width: 22, height: 22)
      .background(Circle().fill(InlineAreaChrome.itemBackground.opacity(0.75)))
      .overlay(
        Circle()
          .stroke(
            isTargeted ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.35),
            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
          )
      )
      .frame(width: 24, height: 24)
      .help(L10n.Common.custom)
      .contentShape(Circle())
      .onTapGesture(perform: onTap)
      .accessibilityLabel(L10n.Common.custom)
      .accessibilityAddTraits(.isButton)
      .onDrop(of: AnnotateColorDragPayload.supportedContentTypes, isTargeted: $isTargeted) { providers in
        AnnotateColorDragPayload.load(from: providers) { payload in
          guard let payload else { return }
          onDropPayload(payload)
        }
      }
  }
}

private struct InlineAreaColorSwatch: View {
  let color: Color
  let isSelected: Bool
  let size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(AnnotateColorPaletteStore.isClear(color) ? Color.clear : color)
        .frame(width: size, height: size)
        .overlay(
          Circle()
            .strokeBorder(
              isSelected ? Color.accentColor : Color.primary.opacity(0.32),
              lineWidth: isSelected ? 2 : 1
            )
        )

      if AnnotateColorPaletteStore.isClear(color) {
        Image(systemName: "slash.circle")
          .font(.system(size: max(9, size * 0.5), weight: .semibold))
          .foregroundColor(InlineAreaChrome.secondaryText)
      }
    }
  }
}
private struct InlineAreaSegmentedPicker<Item: Identifiable & Equatable>: View {
  let title: String
  let items: [Item]
  @Binding var selection: Item
  let icon: (Item) -> String
  var isFlipped: ((Item) -> Bool)? = nil
  let tooltip: KeyPath<Item, String>

  var body: some View {
    InlineAreaPropertyGroup(title: title) {
      HStack(spacing: 4) {
        ForEach(items) { item in
          Button {
            selection = item
          } label: {
            Image(systemName: icon(item))
              .font(.system(size: 12, weight: .medium))
              .scaleEffect(x: 1, y: isFlipped?(item) == true ? -1 : 1)
              .foregroundColor(selection == item ? InlineAreaChrome.itemSelectedForeground : InlineAreaChrome.secondaryText)
              .frame(width: 25, height: InlineAreaChrome.propertyControlHeight)
              .background(
                RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous)
                  .fill(selection == item ? InlineAreaChrome.itemSelectedBackground : InlineAreaChrome.itemBackground)
              )
              .overlay(
                RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous)
                  .stroke(selection == item ? InlineAreaChrome.itemSelectedBorder : InlineAreaChrome.itemBorder, lineWidth: 1)
              )
          }
          .buttonStyle(.plain)
          .help(item[keyPath: tooltip])
        }
      }
    }
  }
}


private struct InlineAreaArrowBendControl: View {
  @Binding var bendDirection: ArrowBendDirection

  var body: some View {
    InlineAreaPropertyGroup(title: L10n.AnnotateUI.arrowBend) {
      Button {
        bendDirection = bendDirection.toggled
      } label: {
        Image(systemName: bendDirection.icon)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(bendDirection == .alternate ? InlineAreaChrome.itemSelectedForeground : InlineAreaChrome.secondaryText)
          .frame(width: 25, height: InlineAreaChrome.propertyControlHeight)
          .background(
            RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous)
              .fill(bendDirection == .alternate ? InlineAreaChrome.itemSelectedBackground : InlineAreaChrome.itemBackground)
          )
          .overlay(
            RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous)
              .stroke(bendDirection == .alternate ? InlineAreaChrome.itemSelectedBorder : InlineAreaChrome.itemBorder, lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
      .help("\(L10n.AnnotateUI.flipArrowBend): \(bendDirection.displayName)")
      .accessibilityLabel(L10n.AnnotateUI.flipArrowBend)
    }
  }
}

private struct InlineAreaSliderControl: View {
  let title: String
  let icon: String
  @Binding var value: CGFloat
  let range: ClosedRange<CGFloat>
  let step: CGFloat
  let displayText: String
  let onEditingChanged: (Bool) -> Void

  var body: some View {
    InlineAreaPropertyGroup(title: title) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(InlineAreaChrome.secondaryText)

        Slider(
          value: $value.stepped(by: step, in: range),
          in: range,
          onEditingChanged: onEditingChanged
        )
        .frame(width: 58)
        .controlSize(.small)

        Text(displayText)
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(InlineAreaChrome.secondaryText)
          .lineLimit(1)
          .monospacedDigit()
          .frame(width: 34, alignment: .trailing)
      }
    }
  }
}

private struct InlineAreaTextFieldControl: View {
  let title: String
  @Binding var text: String

  var body: some View {
    InlineAreaPropertyGroup(title: title) {
      TextField("", text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(InlineAreaChrome.primaryText)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(width: 112, height: InlineAreaChrome.propertyControlHeight)
        .background(
          RoundedRectangle(cornerRadius: InlineAreaChrome.controlCornerRadius, style: .continuous)
            .fill(InlineAreaChrome.itemBackground)
        )
    }
  }
}

private struct InlineAreaPropertyGroup<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(InlineAreaChrome.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .fixedSize(horizontal: true, vertical: false)

      content
    }
  }
}

private struct InlineAreaActionRail: View {
  @ObservedObject var session: InlineAreaAnnotateSession

  var body: some View {
    VStack(spacing: InlineAreaToolbarMetrics.actionRailSpacing) {
      InlineAreaIconButton(icon: "pin", tooltip: L10n.PreferencesQuickAccess.pinToScreenAction) {
        Task { await session.finishAndPin() }
      }

      InlineAreaIconButton(icon: "xmark", tooltip: L10n.Common.cancel) {
        session.cancel()
      }

      InlineAreaIconButton(
        icon: "checkmark",
        tooltip: L10n.Common.withShortcut(L10n.Common.done, "⌘S"),
        isProminent: true
      ) {
        Task { await session.finish() }
      }

      InlineAreaRailDivider()
        .padding(.vertical, InlineAreaToolbarMetrics.actionRailDividerVerticalPadding)

      InlineAreaIconButton(
        icon: "doc.on.doc",
        tooltip: L10n.Common.withShortcut(L10n.AnnotateUI.copyToClipboard, "⌘C")
      ) {
        session.copyCurrentImage()
      }
    }
    .padding(InlineAreaToolbarMetrics.actionRailPadding)
    .inlineAreaPanelChrome()
  }
}

private struct InlineAreaRailDivider: View {
  var body: some View {
    Rectangle()
      .fill(InlineAreaChrome.divider)
      .frame(
        width: InlineAreaToolbarMetrics.actionRailDividerWidth,
        height: InlineAreaToolbarMetrics.actionRailDividerHeight
      )
  }
}
