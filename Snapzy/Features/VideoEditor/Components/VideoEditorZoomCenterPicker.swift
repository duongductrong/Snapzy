//
//  VideoEditorZoomCenterPicker.swift
//  Snapzy
//
//  Mini preview with draggable crosshair for selecting zoom center point
//

import SwiftUI

/// Draggable crosshair for selecting zoom focus point
struct ZoomCenterPicker: View {
  @Binding var center: CGPoint
  let previewImage: NSImage?
  var onEditingChanged: (Bool) -> Void = { _ in }
  var onCenterChanged: (CGPoint) -> Void = { _ in }

  private let pickerSize: CGFloat = 120
  private let crosshairSize: CGFloat = 24

  @State private var isDragging = false

  var body: some View {
    ZStack {
      // Background preview or placeholder
      if let image = previewImage {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: pickerSize, height: pickerSize * 9 / 16)
          .clipped()
      } else {
        Rectangle()
          .fill(Color.gray.opacity(0.3))
          .frame(width: pickerSize, height: pickerSize * 9 / 16)
      }

      // Zoom region indicator
      zoomRegionOverlay

      // Crosshair
      crosshairView
        .position(
          x: center.x * pickerSize,
          y: center.y * (pickerSize * 9 / 16)
        )
    }
    .frame(width: pickerSize, height: pickerSize * 9 / 16)
    .cornerRadius(Radius.tile)
    .overlay(
      Radius.rect(Radius.tile)
        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
    )
    .contentShape(Rectangle())
    .accessibilityIdentifier("video-editor.zoom-center")
    .gesture(dragGesture)
    .onDisappear {
      if isDragging { onEditingChanged(false) }
    }
  }

  // MARK: - Subviews

  private var zoomRegionOverlay: some View {
    let regionWidth = pickerSize * 0.4
    let regionHeight = (pickerSize * 9 / 16) * 0.4

    return Rectangle()
      .strokeBorder(ZoomColors.primary.opacity(0.6), lineWidth: 1.5)
      .background(ZoomColors.primary.opacity(0.15))
      .frame(width: regionWidth, height: regionHeight)
      .position(
        x: center.x * pickerSize,
        y: center.y * (pickerSize * 9 / 16)
      )
  }

  private var crosshairView: some View {
    ZStack {
      // Outer circle
      Circle()
        .strokeBorder(Color.white, lineWidth: 2)
        .frame(width: crosshairSize, height: crosshairSize)
        .shadow(color: .black.opacity(0.5), radius: 2)

      // Center dot
      Circle()
        .fill(Color.white)
        .frame(width: 4, height: 4)

      // Crosshair lines
      Path { path in
        // Horizontal
        path.move(to: CGPoint(x: -crosshairSize / 2, y: 0))
        path.addLine(to: CGPoint(x: -4, y: 0))
        path.move(to: CGPoint(x: 4, y: 0))
        path.addLine(to: CGPoint(x: crosshairSize / 2, y: 0))
        // Vertical
        path.move(to: CGPoint(x: 0, y: -crosshairSize / 2))
        path.addLine(to: CGPoint(x: 0, y: -4))
        path.move(to: CGPoint(x: 0, y: 4))
        path.addLine(to: CGPoint(x: 0, y: crosshairSize / 2))
      }
      .stroke(Color.white, lineWidth: 1.5)
      .shadow(color: .black.opacity(0.5), radius: 1)
    }
    .scaleEffect(isDragging ? 1.1 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isDragging)
  }

  // MARK: - Gesture

  private func updateCenter(at location: CGPoint) {
    let point = CGPoint(x: max(0.05, min(location.x / pickerSize, 0.95)),
                        y: max(0.05, min(location.y / (pickerSize * 9 / 16), 0.95)))
    guard point != center else { return }
    center = point
    onCenterChanged(point)
  }

  private var dragGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if !isDragging { onEditingChanged(true) }
        isDragging = true
        updateCenter(at: value.location)
      }
      .onEnded { value in
        updateCenter(at: value.location)
        isDragging = false
        onEditingChanged(false)
      }
  }
}

// MARK: - Preview

#Preview {
  ZoomCenterPicker(
    center: .constant(CGPoint(x: 0.5, y: 0.5)),
    previewImage: nil
  )
  .padding()
  .background(Color.black)
}
