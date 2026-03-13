//
//  QuickAccessCardView.swift
//  Snapzy
//
//  Single quick access card with swipe-to-dismiss and drag-to-external-app
//  Direction-based gesture handling: swipe toward edge = dismiss, drag away = external app
//

import AppKit
import SwiftUI

/// Gesture mode for direction-based handling
private enum GestureMode {
  case undetermined
  case swipeToDismiss
  case dragToApp
}

/// Displays a single item preview with hover-activated actions and swipe gestures
struct QuickAccessCardView: View {
  let item: QuickAccessItem
  let manager: QuickAccessManager
  var onHover: ((Bool) -> Void)? = nil

  @ObservedObject private var preferencesManager = PreferencesManager.shared
  @State private var isHovering = false
  @State private var isDragging = false
  @State private var isDismissing = false
  @State private var dragRemovalTask: Task<Void, Never>?
  @State private var gestureMode: GestureMode = .undetermined
  @State private var swipeOffset: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  private let cornerRadius: CGFloat = 16
  /// Minimum movement to determine direction (30px threshold for drag activation)
  private let directionThreshold: CGFloat = 30

  /// Dismiss direction based on panel position
  /// Right side panel: swipe right to dismiss (+1)
  /// Left side panel: swipe left to dismiss (-1)
  private var dismissDirection: CGFloat {
    manager.position.isLeftSide ? -1 : 1
  }

  var body: some View {
    ZStack(alignment: .center) {
      // Thumbnail with blur effect on hover
      Image(nsImage: item.thumbnail)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: QuickAccessLayout.cardWidth, height: QuickAccessLayout.cardHeight)
        .clipped()
        .blur(radius: isHovering ? 2 : 0)
        .cornerRadius(cornerRadius)

      // Duration badge (videos only, bottom-right)
      if let duration = item.formattedDuration {
        durationBadge(duration)
      }

      // Processing progress overlay
      if item.processingState != .idle {
        QuickAccessProgressView(state: item.processingState)
          .transition(.opacity)
      }

      // Hover overlay with staggered buttons
      if isHovering && item.processingState == .idle {
        hoverOverlay
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95)))
      }

      // Corner buttons (only visible on hover)
      if isHovering && item.processingState == .idle {
        cornerButtons
      }
    }
    .frame(width: QuickAccessLayout.cardWidth, height: QuickAccessLayout.cardHeight)
    .background(
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.black.opacity(0.1))
    )
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
    .opacity(cardOpacity)
    .offset(x: reduceMotion ? 0 : swipeOffset)
    .rotationEffect(.degrees(reduceMotion ? 0 : Double(swipeOffset) * 0.03))
    .onHover { hovering in
      withAnimation(QuickAccessAnimations.hoverOverlay) {
        isHovering = hovering
      }
      onHover?(hovering)

      // Pause/resume countdown on hover if enabled
      if manager.pauseCountdownOnHover {
        if hovering {
          manager.pauseCountdown(for: item.id)
        } else {
          manager.resumeCountdown(for: item.id)
        }
      }
    }
    .onTapGesture(count: 2) {
      handleDoubleClick()
    }
    // Use high-priority gesture for direction detection
    .gesture(directionAwareGesture)
    .onDisappear {
      dragRemovalTask?.cancel()
    }
    .animation(QuickAccessAnimations.hoverOverlay, value: isHovering)
  }

  // MARK: - Computed Properties

  private var cardOpacity: Double {
    if isDragging { return 0.6 }
    if isDismissing { return 0 }
    if reduceMotion { return 1.0 }
    return 1.0 - Double(abs(swipeOffset)) / 200.0
  }

  // MARK: - Gestures

  /// Check if translation is toward dismiss direction (toward screen edge)
  private func isDismissDirection(_ translation: CGFloat) -> Bool {
    // Right panel: positive translation (swipe right) dismisses
    // Left panel: negative translation (swipe left) dismisses
    return (translation * dismissDirection) > 0
  }

  /// Direction-aware gesture that decides between swipe-dismiss and drag-to-app
  private var directionAwareGesture: some Gesture {
    DragGesture(minimumDistance: 5)
      .onChanged { value in
        guard !reduceMotion else { return }

        let translation = value.translation.width

        // Determine mode once after passing threshold
        if gestureMode == .undetermined && abs(translation) > directionThreshold {
          if isDismissDirection(translation) {
            gestureMode = .swipeToDismiss
          } else {
            gestureMode = .dragToApp
            // Trigger drag-to-app
            if manager.dragDropEnabled {
              startDragToApp()
            }
          }
        }

        // Only update swipe offset if in swipe mode
        if gestureMode == .swipeToDismiss {
          swipeOffset = translation
        }
      }
      .onEnded { value in
        defer {
          // Reset state
          gestureMode = .undetermined
          swipeOffset = 0
        }

        guard !reduceMotion else { return }

        let translation = value.translation.width
        let velocity = value.velocity.width
        let threshold: CGFloat = 80
        let velocityThreshold: CGFloat = 300

        // Handle swipe-to-dismiss
        if gestureMode == .swipeToDismiss {
          if abs(translation) > threshold || abs(velocity) > velocityThreshold {
            isDismissing = true
            QuickAccessSound.dismiss.play(reduceMotion: reduceMotion)
            manager.removeScreenshot(id: item.id)
          } else {
            // Snap back
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
              swipeOffset = 0
            }
          }
        }
        // dragToApp mode is handled separately
      }
  }

  /// Start drag-to-app session using NSDraggingSession
  private func startDragToApp() {
    guard !isDragging else { return }
    isDragging = true

    // Find the window and start a proper drag session
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }),
          let contentView = window.contentView,
          let currentEvent = NSApp.currentEvent else {
      isDragging = false
      return
    }

    let sourceAccess = SandboxFileAccessManager.shared.beginAccessingURL(item.url)

    let dragSource = DragSource(
      dragID: UUID(),
      sourceAccess: sourceAccess,
      onEnded: { [weak manager, itemId = item.id] success in
        Task { @MainActor in
          if success {
            // Only remove card from UI — don't delete the file.
            // Temp files stay on disk for the receiving app to read
            // and get cleaned up on next launch via cleanupOrphanedFiles().
            manager?.dismissCard(id: itemId)
          }
        }
      }
    )
    QuickAccessDragRegistry.retain(dragSource, for: dragSource.dragID)
    // Use concrete file URL payload so browser chat drop zones receive a real file.
    let fileURLDragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)

    // Create drag image from thumbnail
    let imageSize = NSSize(width: 100, height: 62)
    let dragImage = NSImage(size: imageSize)
    dragImage.lockFocus()
    item.thumbnail.draw(
      in: NSRect(origin: .zero, size: imageSize),
      from: .zero,
      operation: .sourceOver,
      fraction: 0.8
    )
    dragImage.unlockFocus()

    // Set drag frame centered on mouse
    let mouseLocation = currentEvent.locationInWindow
    fileURLDragItem.setDraggingFrame(
      NSRect(
        x: mouseLocation.x - imageSize.width / 2,
        y: mouseLocation.y - imageSize.height / 2,
        width: imageSize.width,
        height: imageSize.height
      ),
      contents: dragImage
    )
    // Start the drag session
    let dragSession = contentView.beginDraggingSession(
      with: [fileURLDragItem],
      event: currentEvent,
      source: dragSource
    )
    print("[QuickAccessDrag] Started drag for \(item.url.lastPathComponent)")
    dragSession.animatesToStartingPositionsOnCancelOrFail = true

    // Reset dragging state after a delay
    dragRemovalTask?.cancel()
    dragRemovalTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 500_000_000)
      guard !Task.isCancelled else { return }
      isDragging = false
    }
  }

  // MARK: - Actions

  private func handleDoubleClick() {
    if item.isVideo {
      openVideoEditor()
    } else {
      openAnnotation()
    }
  }

  private func openAnnotation() {
    AnnotateManager.shared.openAnnotation(for: item)
  }

  private func openVideoEditor() {
    Task { @MainActor in
      VideoEditorManager.shared.openEditor(for: item)
    }
  }

  // MARK: - Subviews

  private func durationBadge(_ duration: String) -> some View {
    VStack {
      Spacer()
      HStack {
        Spacer()
        Text(duration)
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
          .foregroundColor(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.black.opacity(0.7))
          )
          .padding(6)
      }
    }
  }

  private var hoverOverlay: some View {
    let captureType: CaptureType = item.isVideo ? .recording : .screenshot
    let showCopy = preferencesManager.isActionEnabled(.copyFile, for: captureType)
    let showSaveToggle = preferencesManager.isActionEnabled(.save, for: captureType)
    let isTempFile = TempCaptureManager.shared.isTempFile(item.url)
    // Always show save button for temp files (it's the only way to persist them)
    let showSave = showSaveToggle || isTempFile

    return ZStack {
      // Dimming overlay
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.black.opacity(0.4))

      // Action buttons with stagger effect (only show enabled actions)
      VStack(spacing: 8) {
        if showCopy {
          staggeredButton(label: "Copy", delay: 0) {
            QuickAccessSound.copy.play(reduceMotion: reduceMotion)
            manager.copyToClipboard(id: item.id)
          }
        }

        if showSave {
          staggeredButton(
            label: isTempFile ? "Save" : "Open",
            delay: showCopy ? 1 : 0
          ) {
            QuickAccessSound.save.play(reduceMotion: reduceMotion)
            if isTempFile {
              manager.saveItem(id: item.id)
            } else {
              manager.openInFinder(id: item.id)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func staggeredButton(label: String, delay: Int, action: @escaping () -> Void) -> some View {
    QuickAccessTextButton(label: label, action: action)
      .transition(buttonTransition(delay: delay))
  }

  private func buttonTransition(delay: Int) -> AnyTransition {
    if reduceMotion {
      return .opacity
    }
    let stagger = Double(delay) * QuickAccessAnimations.buttonStaggerDelay
    return .scale(scale: 0.6)
      .combined(with: .opacity)
      .animation(QuickAccessAnimations.buttonReveal.delay(stagger))
  }

  private var cornerButtons: some View {
    let captureType: CaptureType = item.isVideo ? .recording : .screenshot
    let isSaveEnabled = preferencesManager.isActionEnabled(.save, for: captureType)

    return ZStack {
      // Dismiss button (top-right)
      VStack {
        HStack {
          Spacer()
          QuickAccessIconButton(icon: "xmark") {
            isDismissing = true
            QuickAccessSound.dismiss.play(reduceMotion: reduceMotion)
            manager.removeScreenshot(id: item.id)
          }
          .transition(cornerButtonTransition(delay: 2))
          .padding(6)
        }
        Spacer()
      }

      // Delete button (top-left) — hidden when "Save" after-capture action is disabled
      if isSaveEnabled {
        VStack {
          HStack {
            QuickAccessIconButton(
              icon: "trash",
              action: {
                isDismissing = true
                manager.deleteItem(id: item.id)
              },
              helpText: "Delete"
            )
            .transition(cornerButtonTransition(delay: 3))
            .padding(6)
            Spacer()
          }
          Spacer()
        }
      }

      // Edit button (bottom-left)
      VStack {
        Spacer()
        HStack {
          QuickAccessIconButton(
            icon: "pencil",
            action: handleDoubleClick,
            helpText: item.isVideo ? "Edit Video" : "Annotate"
          )
          .transition(cornerButtonTransition(delay: 4))
          .padding(6)
          Spacer()
        }
      }
    }
  }

  private func cornerButtonTransition(delay: Int) -> AnyTransition {
    if reduceMotion {
      return .opacity
    }
    let stagger = Double(delay) * QuickAccessAnimations.buttonStaggerDelay
    return .scale(scale: 0.5)
      .combined(with: .opacity)
      .animation(QuickAccessAnimations.buttonReveal.delay(stagger))
  }

  /// Creates drag preview for the card
  private var dragPreview: some View {
    Image(nsImage: item.thumbnail)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(width: QuickAccessLayout.cardWidth * 0.8, height: QuickAccessLayout.cardHeight * 0.8)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
  }
}

// MARK: - NSDraggingSource for Drag-to-App

/// Drag source handler for NSDraggingSession.
private final class DragSource: NSObject, NSDraggingSource {
  let dragID: UUID
  private var sourceAccess: SandboxFileAccessManager.ScopedAccess?
  private let onEnded: (Bool) -> Void

  init(
    dragID: UUID,
    sourceAccess: SandboxFileAccessManager.ScopedAccess,
    onEnded: @escaping (Bool) -> Void
  ) {
    self.dragID = dragID
    self.sourceAccess = sourceAccess
    self.onEnded = onEnded
    super.init()
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    return context == .outsideApplication ? .copy : .copy
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    sourceAccess?.stop()
    sourceAccess = nil
    QuickAccessDragRegistry.release(for: dragID)
    print("[QuickAccessDrag] Drag ended with operation rawValue=\(operation.rawValue)")
    onEnded(operation != [])
  }

  deinit {
    sourceAccess?.stop()
    sourceAccess = nil
  }
}

private enum QuickAccessDragRegistry {
  private static let lock = NSLock()
  private static var activeSources: [UUID: DragSource] = [:]

  static func retain(_ source: DragSource, for id: UUID) {
    lock.lock()
    activeSources[id] = source
    lock.unlock()
  }

  static func release(for id: UUID) {
    lock.lock()
    activeSources[id] = nil
    lock.unlock()
  }
}

// MARK: - QuickAccessItem Drag Support

extension QuickAccessItem {
  /// Creates NSItemProvider for drag & drop to external apps
  func dragItemProvider() -> NSItemProvider {
    let fileURL = self.url
    let provider = NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
    provider.suggestedName = fileURL.lastPathComponent
    return provider
  }
}

// MARK: - Conditional View Extension

extension View {
  /// Conditionally applies a transformation to the view
  @ViewBuilder
  func `if`<Transform: View>(
    _ condition: Bool,
    transform: (Self) -> Transform
  ) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
