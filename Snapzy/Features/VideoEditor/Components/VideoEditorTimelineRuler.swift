//
//  VideoEditorTimelineRuler.swift
//  Snapzy
//
//  Time ruler lane for the timeline container: adaptive second ticks and
//  labels hanging from the container's top edge so the user can read — and
//  scrub to — the second they want to edit.
//

import AVFoundation
import SwiftUI

/// Time ruler rendered at the top-leading edge of the timeline container.
///
/// Draws a measuring-tape lane with no boxed background of its own: ticks hang
/// from the container's top edge, a labeled major tick every N seconds (N adapts
/// to the available pixel density so labels never collide), minor ticks halfway
/// between majors, and quarter ticks when space allows — so the ruler reads as
/// the container wrapping the whole timeline group.
struct TimelineRulerView: View {
  let duration: CMTime
  let timelineWidth: CGFloat

  /// Lane height, shared with the timeline container so the playhead spans it exactly.
  static let height: CGFloat = 20

  private static let majorTickHeight: CGFloat = 8
  private static let minorTickHeight: CGFloat = 5
  private static let quarterTickHeight: CGFloat = 3.5
  private static let labelCenterY: CGFloat = 15

  /// Minimum pixel spacing between labeled major ticks.
  private static let minMajorSpacing: CGFloat = 44
  private static let minMinorSpacing: CGFloat = 7
  private static let minQuarterSpacing: CGFloat = 5
  /// Keeps centered labels fully inside the lane at both edges.
  private static let minLabelHalfWidth: CGFloat = 12
  /// Rough half-width per character of an 8pt medium monospaced-digit label.
  private static let labelHalfWidthPerCharacter: CGFloat = 2.3

  private static let majorSteps: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
  private static let majorTickColor = Color.primary.opacity(0.30)
  private static let minorTickColor = Color.primary.opacity(0.16)
  private static let quarterTickColor = Color.primary.opacity(0.10)

  var body: some View {
    Canvas { context, size in
      drawRuler(in: context, size: size)
    }
    .frame(height: Self.height)
  }

  // MARK: - Ticks

  private func drawRuler(in context: GraphicsContext, size: CGSize) {
    let durationSeconds = max(0, CMTimeGetSeconds(duration))
    guard durationSeconds > 0, timelineWidth > 0, size.width > 0 else { return }

    let pixelsPerSecond = timelineWidth / durationSeconds
    let majorStep = Self.majorSteps.first { $0 * pixelsPerSecond >= Self.minMajorSpacing } ?? Self.majorSteps.last!
    // Past the step table, keep the lane tick-only instead of overlapping labels.
    let labelsVisible = majorStep * pixelsPerSecond >= Self.minMajorSpacing
    let minorStep = majorStep / 2
    let quarterStep = majorStep / 4
    let minorSpacing = minorStep * pixelsPerSecond
    let quarterSpacing = quarterStep * pixelsPerSecond

    let quarterCount = max(0, Int((durationSeconds / quarterStep).rounded(.up)))
    for quarterIndex in 0 ... quarterCount {
      let time = TimeInterval(quarterIndex) * quarterStep
      guard time <= durationSeconds + 1e-6 else { break }

      let x = CGFloat(time / durationSeconds) * timelineWidth
      switch quarterIndex % 4 {
      case 0:
        drawMajorTick(
          in: context,
          x: x,
          size: size,
          seconds: time,
          usesHourFormat: durationSeconds >= 3600,
          labelsVisible: labelsVisible
        )
      case 2 where minorSpacing >= Self.minMinorSpacing:
        drawTick(in: context, x: x, size: size, height: Self.minorTickHeight, color: Self.minorTickColor)
      default:
        if quarterSpacing >= Self.minQuarterSpacing {
          drawTick(in: context, x: x, size: size, height: Self.quarterTickHeight, color: Self.quarterTickColor)
        }
      }
    }
  }

  private func drawMajorTick(
    in context: GraphicsContext,
    x: CGFloat,
    size: CGSize,
    seconds: TimeInterval,
    usesHourFormat: Bool,
    labelsVisible: Bool
  ) {
    drawTick(in: context, x: x, size: size, height: Self.majorTickHeight, color: Self.majorTickColor)
    if labelsVisible {
      drawLabel(
        in: context,
        x: x,
        size: size,
        text: Self.label(for: seconds, usesHourFormat: usesHourFormat)
      )
    }
  }

  private func drawTick(in context: GraphicsContext, x: CGFloat, size: CGSize, height: CGFloat, color: Color) {
    var tick = Path()
    // Ticks hang flush from the container's top edge; clamp so a tick landing
    // exactly on the trailing edge stays visible.
    tick.addRect(CGRect(x: min(x, size.width - 1), y: 0, width: 1, height: height))
    context.fill(tick, with: .color(color))
  }

  private func drawLabel(in context: GraphicsContext, x: CGFloat, size: CGSize, text: String) {
    let halfWidth = max(Self.minLabelHalfWidth, CGFloat(text.count) * Self.labelHalfWidthPerCharacter)
    guard size.width >= halfWidth * 2 else { return }
    let centerX = max(halfWidth, min(x, size.width - halfWidth))
    let label = Text(text)
      .font(.system(size: 8, weight: .medium).monospacedDigit())
      .foregroundColor(.secondary)
    context.draw(label, at: CGPoint(x: centerX, y: Self.labelCenterY), anchor: .center)
  }

  private static func label(for seconds: TimeInterval, usesHourFormat: Bool) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if usesHourFormat {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: 12) {
    TimelineRulerView(
      duration: CMTime(seconds: 35, preferredTimescale: 600),
      timelineWidth: 400
    )
    TimelineRulerView(
      duration: CMTime(seconds: 90, preferredTimescale: 600),
      timelineWidth: 400
    )
    TimelineRulerView(
      duration: CMTime(seconds: 630, preferredTimescale: 600),
      timelineWidth: 400
    )
    TimelineRulerView(
      duration: CMTime(seconds: 5400, preferredTimescale: 600),
      timelineWidth: 400
    )
  }
  .padding()
  .background(Color(NSColor.windowBackgroundColor))
}
