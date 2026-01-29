//
//  QuickAccessCardView.swift
//  ClaudeShot
//
//  Single quick access card with swipe-to-dismiss and staggered button reveals
//  CleanShot X inspired animations
//

import SwiftUI
import UniformTypeIdentifiers

/// Displays a single item preview with hover-activated actions and swipe gestures
struct QuickAccessCardView: View {
  let item: QuickAccessItem
  let manager: QuickAccessManager
  var onHover: ((Bool) -> Void)? = nil

  @State private var isHovering = false
  @State private var isDragging = false
  @State private var isDismissing = false
  @State private var dragRemovalTask: Task<Void, Never>?
  @GestureState private var swipeOffset: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  private let cornerRadius: CGFloat = 16

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
    .opacity(cardOpacity)
    .offset(x: reduceMotion ? 0 : swipeOffset)
    .rotationEffect(.degrees(reduceMotion ? 0 : Double(swipeOffset) * 0.03))
    .onHover { hovering in
      withAnimation(QuickAccessAnimations.hoverOverlay) {
        isHovering = hovering
      }
      onHover?(hovering)
    }
    .onTapGesture(count: 2) {
      handleDoubleClick()
    }
    .gesture(swipeGesture)
    .if(manager.dragDropEnabled) { view in
      view.onDrag {
        isDragging = true
        dragRemovalTask?.cancel()
        dragRemovalTask = Task { @MainActor in
          try? await Task.sleep(nanoseconds: 500_000_000)
          guard !Task.isCancelled else { return }
          manager.removeScreenshot(id: item.id)
        }
        return item.dragItemProvider()
      } preview: {
        dragPreview
      }
    }
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

  private var swipeGesture: some Gesture {
    DragGesture()
      .updating($swipeOffset) { value, state, _ in
        guard !isDragging, !reduceMotion else { return }
        state = value.translation.width
      }
      .onEnded { value in
        guard !isDragging else { return }
        let threshold: CGFloat = 80
        let velocityThreshold: CGFloat = 300

        if abs(value.translation.width) > threshold || abs(value.velocity.width) > velocityThreshold {
          isDismissing = true
          QuickAccessSound.dismiss.play(reduceMotion: reduceMotion)
          withAnimation(QuickAccessAnimations.cardSwipeDismiss) {
            manager.removeScreenshot(id: item.id)
          }
        }
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
    Task { @MainActor in
      AnnotateManager.shared.openAnnotation(for: item)
    }
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
    ZStack {
      // Dimming overlay
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.black.opacity(0.4))

      // Action buttons with stagger effect
      VStack(spacing: 8) {
        staggeredButton(label: "Copy", delay: 0) {
          QuickAccessSound.copy.play(reduceMotion: reduceMotion)
          manager.copyToClipboard(id: item.id)
        }

        staggeredButton(label: "Save", delay: 1) {
          QuickAccessSound.save.play(reduceMotion: reduceMotion)
          manager.openInFinder(id: item.id)
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
    ZStack {
      // Dismiss button (top-right)
      VStack {
        HStack {
          Spacer()
          QuickAccessIconButton(icon: "xmark") {
            manager.removeScreenshot(id: item.id)
          }
          .transition(cornerButtonTransition(delay: 2))
          .padding(6)
        }
        Spacer()
      }

      // Delete button (top-left)
      VStack {
        HStack {
          QuickAccessIconButton(
            icon: "trash",
            action: {
              QuickAccessSound.delete.play(reduceMotion: reduceMotion)
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
