//
//  QuickAccessCardView.swift
//  ZapShot
//
//  Single quick access card (screenshot or video) with hover interactions
//

import SwiftUI
import UniformTypeIdentifiers

/// Displays a single item preview with hover-activated actions
struct QuickAccessCardView: View {
  let item: QuickAccessItem
  let manager: QuickAccessManager

  @State private var isHovering = false

  private let cardWidth: CGFloat = 180
  private let cardHeight: CGFloat = 112.5
  private let cornerRadius: CGFloat = 10

  var body: some View {
    ZStack(alignment: .center) {
      // Thumbnail with blur effect on hover
      Image(nsImage: item.thumbnail)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: cardWidth, height: cardHeight)
        .clipped()
        .blur(radius: isHovering ? 2 : 0)
        .cornerRadius(cornerRadius)

      // Duration badge (videos only, bottom-right)
      if let duration = item.formattedDuration {
        durationBadge(duration)
      }

      // Hover overlay with buttons
      if isHovering {
        hoverOverlay
          .transition(.opacity.combined(with: .scale(scale: 0.95)))
      }

      // Dismiss button (top-right, only visible on hover)
      if isHovering {
        dismissButton
          .transition(.opacity)
      }

      // Edit button (bottom-left, only visible on hover)
      if isHovering {
        editButton
          .transition(.opacity)
      }

      // Delete button (top-left, only visible on hover)
      if isHovering {
        deleteButton
          .transition(.opacity)
      }
    }
    .frame(width: cardWidth, height: cardHeight)
    .background(
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(Color.black.opacity(0.1))
    )
    .overlay(
      RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.2)) {
        isHovering = hovering
      }
    }
    .onTapGesture(count: 2) {
      handleDoubleClick()
    }
    .if(manager.dragDropEnabled) { view in
      view.onDrag {
        item.dragItemProvider()
      } preview: {
        dragPreview
      }
    }
  }

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

      // Action buttons (vertical, centered) - Copy and Save only
      VStack(spacing: 8) {
        QuickAccessTextButton(label: "Copy") {
          manager.copyToClipboard(id: item.id)
        }

        QuickAccessTextButton(label: "Save") {
          manager.openInFinder(id: item.id)
        }
      }
    }
  }

  private var dismissButton: some View {
    VStack {
      HStack {
        Spacer()
        Button(action: { manager.removeScreenshot(id: item.id) }) {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(
              Circle()
                .fill(Color.black.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
        .padding(6)
      }
      Spacer()
    }
  }

  private var editButton: some View {
    VStack {
      Spacer()
      HStack {
        Button(action: handleDoubleClick) {
          Image(systemName: "pencil")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(
              Circle()
                .fill(Color.black.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
        .padding(6)
        .help(item.isVideo ? "Edit Video" : "Annotate")
        Spacer()
      }
    }
  }

  private var deleteButton: some View {
    VStack {
      HStack {
        Button(action: { manager.deleteItem(id: item.id) }) {
          Image(systemName: "trash")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(
              Circle()
                .fill(Color.black.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("Delete")
        Spacer()
      }
      Spacer()
    }
  }

  /// Creates drag preview for the card
  private var dragPreview: some View {
    Image(nsImage: item.thumbnail)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(width: cardWidth * 0.8, height: cardHeight * 0.8)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
  }
}

// MARK: - QuickAccessItem Drag Support

extension QuickAccessItem {
  /// Creates NSItemProvider for drag & drop to external apps
  func dragItemProvider() -> NSItemProvider {
    // Capture URL value before creating provider to ensure thread safety
    let fileURL = self.url

    // Use NSItemProvider with the file URL directly - simplest and most reliable approach
    let provider = NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()

    // Set suggested name for the dragged file
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
