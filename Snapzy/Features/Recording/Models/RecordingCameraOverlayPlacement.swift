//
//  RecordingCameraOverlayPlacement.swift
//  Snapzy
//
//  Geometry for dragging and snapping the recording camera overlay.
//

import CoreGraphics

enum RecordingCameraOverlaySnapPoint: CaseIterable, Equatable {
  case topLeft
  case topCenter
  case topRight
  case rightCenter
  case bottomRight
  case bottomCenter
  case bottomLeft
  case leftCenter
}

enum RecordingCameraOverlayPlacement {
  nonisolated static let defaultEdgeInset: CGFloat = 24
  static let snapThreshold: CGFloat = 32

  static func resolvedOrigin(
    for proposedOrigin: CGPoint,
    recordingRect: CGRect,
    overlaySize: CGSize,
    edgeInset: CGFloat,
    threshold: CGFloat = Self.snapThreshold
  ) -> CGPoint {
    let bounds = originBounds(
      in: recordingRect,
      overlaySize: overlaySize,
      edgeInset: edgeInset
    )
    let clampedOrigin = clampedOrigin(proposedOrigin, within: bounds)

    guard let snapPoint = snapPoint(
      for: clampedOrigin,
      recordingRect: recordingRect,
      overlaySize: overlaySize,
      edgeInset: edgeInset,
      threshold: threshold
    ) else {
      return clampedOrigin
    }

    return targetOrigin(for: snapPoint, in: bounds)
  }

  static func snapPoint(
    for proposedOrigin: CGPoint,
    recordingRect: CGRect,
    overlaySize: CGSize,
    edgeInset: CGFloat,
    threshold: CGFloat = Self.snapThreshold
  ) -> RecordingCameraOverlaySnapPoint? {
    let bounds = originBounds(
      in: recordingRect,
      overlaySize: overlaySize,
      edgeInset: edgeInset
    )
    let clampedOrigin = clampedOrigin(proposedOrigin, within: bounds)
    let threshold = max(0, threshold)

    var closestPoint: RecordingCameraOverlaySnapPoint?
    var closestDistance = CGFloat.greatestFiniteMagnitude

    for snapPoint in RecordingCameraOverlaySnapPoint.allCases {
      let target = targetOrigin(for: snapPoint, in: bounds)
      // A square threshold makes diagonal approaches as predictable as horizontal or vertical ones.
      let distance = max(
        abs(clampedOrigin.x - target.x),
        abs(clampedOrigin.y - target.y)
      )

      guard distance <= threshold, distance < closestDistance else { continue }
      closestPoint = snapPoint
      closestDistance = distance
    }

    return closestPoint
  }

  static func targetOrigin(
    for snapPoint: RecordingCameraOverlaySnapPoint,
    recordingRect: CGRect,
    overlaySize: CGSize,
    edgeInset: CGFloat
  ) -> CGPoint {
    targetOrigin(
      for: snapPoint,
      in: originBounds(
        in: recordingRect,
        overlaySize: overlaySize,
        edgeInset: edgeInset
      )
    )
  }

  static func originBounds(
    in recordingRect: CGRect,
    overlaySize: CGSize,
    edgeInset: CGFloat
  ) -> CGRect {
    let horizontalInset = min(
      max(0, edgeInset),
      max(0, (recordingRect.width - overlaySize.width) / 2)
    )
    let verticalInset = min(
      max(0, edgeInset),
      max(0, (recordingRect.height - overlaySize.height) / 2)
    )
    let minX = recordingRect.minX + horizontalInset
    let minY = recordingRect.minY + verticalInset
    let maxX = max(minX, recordingRect.maxX - horizontalInset - overlaySize.width)
    let maxY = max(minY, recordingRect.maxY - verticalInset - overlaySize.height)

    return CGRect(
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY
    )
  }

  private static func targetOrigin(
    for snapPoint: RecordingCameraOverlaySnapPoint,
    in bounds: CGRect
  ) -> CGPoint {
    switch snapPoint {
    case .topLeft:
      CGPoint(x: bounds.minX, y: bounds.maxY)
    case .topCenter:
      CGPoint(x: bounds.midX, y: bounds.maxY)
    case .topRight:
      CGPoint(x: bounds.maxX, y: bounds.maxY)
    case .rightCenter:
      CGPoint(x: bounds.maxX, y: bounds.midY)
    case .bottomRight:
      CGPoint(x: bounds.maxX, y: bounds.minY)
    case .bottomCenter:
      CGPoint(x: bounds.midX, y: bounds.minY)
    case .bottomLeft:
      CGPoint(x: bounds.minX, y: bounds.minY)
    case .leftCenter:
      CGPoint(x: bounds.minX, y: bounds.midY)
    }
  }

  static func resizedOrigin(
    currentFrame: CGRect,
    newSize: CGSize,
    recordingRect: CGRect,
    edgeInset: CGFloat = defaultEdgeInset
  ) -> CGPoint {
    if let currentSnap = snapPoint(
      for: currentFrame.origin,
      recordingRect: recordingRect,
      overlaySize: currentFrame.size,
      edgeInset: edgeInset
    ) {
      return targetOrigin(
        for: currentSnap,
        recordingRect: recordingRect,
        overlaySize: newSize,
        edgeInset: edgeInset
      )
    }

    let centerOrigin = CGPoint(
      x: currentFrame.midX - newSize.width / 2,
      y: currentFrame.midY - newSize.height / 2
    )
    return resolvedOrigin(
      for: centerOrigin,
      recordingRect: recordingRect,
      overlaySize: newSize,
      edgeInset: edgeInset
    )
  }

  private static func clampedOrigin(_ origin: CGPoint, within bounds: CGRect) -> CGPoint {
    CGPoint(
      x: min(max(origin.x, bounds.minX), bounds.maxX),
      y: min(max(origin.y, bounds.minY), bounds.maxY)
    )
  }
}
