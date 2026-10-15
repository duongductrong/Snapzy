//
//  AnnotateCutOutOverlayView.swift
//  Snapzy
//
//  Cut out overlay: highlights the drawn/persisted strip, dims nothing inside
//  it (Snagit-style "this band goes away"), and shows the strip's size badge.
//

import SwiftUI

/// Overlay for the cut out tool while a strip is being drawn/persisted.
struct CutOutOverlayView: View {
  @ObservedObject var state: AnnotateState
  let scale: CGFloat
  let canvasBounds: CGRect

  var body: some View {
    ZStack {
      if let strip = state.cutOutPreviewStrip {
        let scaled = scaledStrip(strip)

        stripSurface(scaled: scaled)
        stripBorder(scaled: scaled)
        sizeBadge(scaled: scaled)
      } else {
        Text(L10n.AnnotateUI.cutOutHint)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.white.opacity(0.75))
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Capsule().fill(Color.black.opacity(0.7)))
          .position(x: canvasDisplaySize.width / 2, y: canvasDisplaySize.height - 18)
          .allowsHitTesting(false)
      }
    }
    .allowsHitTesting(false)
  }

  private var canvasDisplaySize: CGSize {
    CGSize(width: canvasBounds.width * scale, height: canvasBounds.height * scale)
  }

  @ViewBuilder
  private func stripSurface(scaled: CGRect) -> some View {
    if state.cutOutMode == .insert {
      // Ghost hatch for space being added (stays empty in the result).
      Rectangle()
        .fill(Color.white.opacity(0.12))
        .frame(width: scaled.width, height: scaled.height)
        .position(x: scaled.midX, y: scaled.midY)
        .overlay(
          Image(systemName: "plus")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
        )
    } else {
      // Transparent interior keeps the "this is removed" affordance: the
      // halves on both sides will join here.
      Rectangle()
        .fill(Color.clear)
        .frame(width: scaled.width, height: scaled.height)
        .position(x: scaled.midX, y: scaled.midY)
        .overlay(
          Image(systemName: "scissors")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white.opacity(0.9))
        )
    }
  }

  private func stripBorder(scaled: CGRect) -> some View {
    Rectangle()
      .stroke(Color.yellow, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
      .frame(width: scaled.width, height: scaled.height)
      .position(x: scaled.midX, y: scaled.midY)
      .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
  }

  @ViewBuilder
  private func sizeBadge(scaled: CGRect) -> some View {
    let badgeText = state.cutOutMode == .remove
      ? String(format: L10n.AnnotateUI.cutOutRemoveBadge, formatStripLength())
      : String(format: L10n.AnnotateUI.cutOutInsertBadge, formatStripLength())

    Text(badgeText)
      .font(.system(size: 11, weight: .regular, design: .monospaced))
      .foregroundColor(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Capsule().fill(Color.black.opacity(0.75)))
      .position(badgePosition(scaled: scaled))
      .allowsHitTesting(false)
  }

  private func formatStripLength() -> String {
    let length = state.cutOutOrientation == .horizontal
      ? state.cutOutPreviewStrip?.height ?? 0
      : state.cutOutPreviewStrip?.width ?? 0
    return "\(Int(length)) px"
  }

  private func badgePosition(scaled: CGRect) -> CGPoint {
    let preferredX = scaled.maxX + 14
    if preferredX < canvasDisplaySize.width - 40 {
      return CGPoint(x: preferredX, y: scaled.midY)
    }
    return CGPoint(x: scaled.midX, y: scaled.minY - 14)
  }

  /// Bottom-left origin (image space) → top-left origin (SwiftUI space).
  private func scaledStrip(_ rect: CGRect) -> CGRect {
    CGRect(
      x: (rect.origin.x - canvasBounds.minX) * scale,
      y: (canvasBounds.maxY - rect.origin.y - rect.height) * scale,
      width: rect.width * scale,
      height: rect.height * scale
    )
  }
}
