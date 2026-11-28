//
//  VideoEditorTimelineSnapGuideView.swift
//  Snapzy
//
//  Full-height magnetic alignment guide rendered over the timeline while a segment
//  or clip handle locks onto a snap target.
//

import AVFoundation
import SwiftUI

struct VideoEditorTimelineSnapGuideView: View {
  @ObservedObject var snapGuide: VideoEditorTimelineSnapGuideState
  let duration: CMTime
  let timelineWidth: CGFloat
  let totalHeight: CGFloat

  private static let capSize: CGFloat = 7

  var body: some View {
    if let activeTarget = snapGuide.activeTarget,
       let guideX = xPosition(for: activeTarget.time) {
      VStack(spacing: 0) {
        SnapGuideDiamond()
          .fill(guideColor(for: activeTarget.kind))
          .frame(width: Self.capSize, height: Self.capSize)

        Rectangle()
          .fill(
            LinearGradient(
              colors: [
                guideColor(for: activeTarget.kind),
                guideColor(for: activeTarget.kind).opacity(0.65),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(width: 1.5, height: max(0, totalHeight - Self.capSize))
      }
      .shadow(color: guideColor(for: activeTarget.kind).opacity(0.55), radius: 3, x: 0, y: 0)
      .offset(x: guideX - Self.capSize / 2)
      .transition(.opacity)
      .animation(.easeOut(duration: 0.10), value: activeTarget)
      .allowsHitTesting(false)
    }
  }

  private func xPosition(for time: TimeInterval) -> CGFloat? {
    let durationSeconds = CMTimeGetSeconds(duration)
    guard durationSeconds > 0, timelineWidth > 0, time.isFinite else { return nil }
    let progress = max(0, min(time / durationSeconds, 1))
    return CGFloat(progress) * timelineWidth
  }

  private func guideColor(for kind: VideoEditorTimelineSnapper.TargetKind) -> Color {
    switch kind {
    case .playhead:
      Color.red.opacity(0.92)
    case .clipBoundary, .timelineBoundary:
      Color.yellow.opacity(0.95)
    case .zoomEdge, .speedEdge, .captionEdge, .cameraEdge, .textEdge:
      Color.accentColor
    }
  }
}

private struct SnapGuideDiamond: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
    path.closeSubpath()
    return path
  }
}
