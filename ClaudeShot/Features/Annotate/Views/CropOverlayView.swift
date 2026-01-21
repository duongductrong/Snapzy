//
//  CropOverlayView.swift
//  ClaudeShot
//
//  Crop overlay with dimming, border, and resize handles
//

import SwiftUI

/// Overlay view for crop tool showing crop region and handles
struct CropOverlayView: View {
  @ObservedObject var state: AnnotateState
  let scale: CGFloat
  let imageSize: CGSize

  private let handleSize: CGFloat = 10
  private let handleHitArea: CGFloat = 20

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        if let cropRect = state.cropRect {
          let scaledCrop = scaledCropRect(cropRect)

          // Dim overlay outside crop region
          CropDimOverlay(
            cropRect: scaledCrop,
            containerSize: geometry.size
          )
          .allowsHitTesting(false)

          // Crop border
          Rectangle()
            .stroke(Color.primary, lineWidth: 2)
            .frame(width: scaledCrop.width, height: scaledCrop.height)
            .position(x: scaledCrop.midX, y: scaledCrop.midY)
            .allowsHitTesting(false)

          // Dashed inner border
          Rectangle()
            .stroke(Color.secondary.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(width: scaledCrop.width, height: scaledCrop.height)
            .position(x: scaledCrop.midX, y: scaledCrop.midY)
            .allowsHitTesting(false)

          // Corner handles
          ForEach(CropHandle.corners, id: \.self) { handle in
            CropHandleView(handle: handle)
              .position(handlePosition(for: handle, in: scaledCrop))
              .allowsHitTesting(false)
          }

          // Edge handles
          ForEach(CropHandle.edges, id: \.self) { handle in
            CropHandleView(handle: handle)
              .position(handlePosition(for: handle, in: scaledCrop))
              .allowsHitTesting(false)
          }
        }
      }
    }
    .allowsHitTesting(false)
  }

  private func scaledCropRect(_ rect: CGRect) -> CGRect {
    // Convert from bottom-left origin (image coords) to top-left origin (SwiftUI coords)
    CGRect(
      x: rect.origin.x * scale,
      y: (imageSize.height - rect.origin.y - rect.height) * scale,
      width: rect.width * scale,
      height: rect.height * scale
    )
  }

  private func handlePosition(for handle: CropHandle, in rect: CGRect) -> CGPoint {
    switch handle {
    case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
    case .top: return CGPoint(x: rect.midX, y: rect.minY)
    case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
    case .left: return CGPoint(x: rect.minX, y: rect.midY)
    case .right: return CGPoint(x: rect.maxX, y: rect.midY)
    case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
    case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
    case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
    case .body: return CGPoint(x: rect.midX, y: rect.midY)
    }
  }
}

// MARK: - Crop Handle Enum

enum CropHandle: String, CaseIterable {
  case topLeft, top, topRight
  case left, right
  case bottomLeft, bottom, bottomRight
  case body

  static var corners: [CropHandle] {
    [.topLeft, .topRight, .bottomLeft, .bottomRight]
  }

  static var edges: [CropHandle] {
    [.top, .bottom, .left, .right]
  }
}

// MARK: - Crop Dim Overlay

struct CropDimOverlay: View {
  let cropRect: CGRect
  let containerSize: CGSize
  private let dimColor = Color.black.opacity(0.5)

  var body: some View {
    ZStack {
      // Top region
      dimColor
        .frame(width: containerSize.width, height: max(0, cropRect.minY))
        .position(x: containerSize.width / 2, y: cropRect.minY / 2)

      // Bottom region
      dimColor
        .frame(width: containerSize.width, height: max(0, containerSize.height - cropRect.maxY))
        .position(x: containerSize.width / 2, y: (containerSize.height + cropRect.maxY) / 2)

      // Left region (between top and bottom)
      dimColor
        .frame(width: max(0, cropRect.minX), height: cropRect.height)
        .position(x: cropRect.minX / 2, y: cropRect.midY)

      // Right region (between top and bottom)
      dimColor
        .frame(width: max(0, containerSize.width - cropRect.maxX), height: cropRect.height)
        .position(x: (containerSize.width + cropRect.maxX) / 2, y: cropRect.midY)
    }
  }
}

// MARK: - Crop Handle View

struct CropHandleView: View {
  let handle: CropHandle
  private let size: CGFloat = 10

  var body: some View {
    ZStack {
      // White fill
      RoundedRectangle(cornerRadius: 2)
        .fill(Color(nsColor: .controlBackgroundColor))
        .frame(width: size, height: size)

      // Blue border
      RoundedRectangle(cornerRadius: 2)
        .stroke(Color.blue, lineWidth: 1.5)
        .frame(width: size, height: size)
    }
    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
  }
}
