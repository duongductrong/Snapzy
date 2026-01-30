//
//  QuickAccessProgressView.swift
//  Snapzy
//
//  Processing progress indicator for quick access cards
//  Shows indeterminate/determinate progress, success, and failure states
//

import SwiftUI

/// Displays processing progress overlay on quick access cards
struct QuickAccessProgressView: View {
  let state: QuickAccessProcessingState
  @Environment(\.accessibilityReduceMotion) var reduceMotion

  private let ringSize: CGFloat = 40
  private let lineWidth: CGFloat = 3

  var body: some View {
    ZStack {
      // Dimming background
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.black.opacity(0.5))

      // Progress indicator
      progressContent
    }
  }

  @ViewBuilder
  private var progressContent: some View {
    switch state {
    case .idle:
      EmptyView()

    case .processing(let progress):
      if let progress = progress {
        determinateRing(progress: progress)
      } else {
        indeterminateRing
      }

    case .complete:
      successCheckmark

    case .failed:
      failureIcon
    }
  }

  // MARK: - Indeterminate Progress

  private var indeterminateRing: some View {
    ZStack {
      // Track
      Circle()
        .stroke(Color.white.opacity(0.3), lineWidth: lineWidth)
        .frame(width: ringSize, height: ringSize)

      // Spinning arc
      if reduceMotion {
        // Static arc for reduced motion
        Circle()
          .trim(from: 0, to: 0.25)
          .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .frame(width: ringSize, height: ringSize)
          .rotationEffect(.degrees(-90))
      } else {
        SpinningArc(lineWidth: lineWidth)
          .frame(width: ringSize, height: ringSize)
      }
    }
  }

  // MARK: - Determinate Progress

  private func determinateRing(progress: Double) -> some View {
    ZStack {
      // Track
      Circle()
        .stroke(Color.white.opacity(0.3), lineWidth: lineWidth)
        .frame(width: ringSize, height: ringSize)

      // Progress arc
      Circle()
        .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
        .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .frame(width: ringSize, height: ringSize)
        .rotationEffect(.degrees(-90))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: progress)
    }
  }

  // MARK: - Success State

  private var successCheckmark: some View {
    ZStack {
      Circle()
        .fill(Color.green)
        .frame(width: ringSize, height: ringSize)

      if reduceMotion {
        Image(systemName: "checkmark")
          .font(.system(size: 20, weight: .bold))
          .foregroundColor(.white)
      } else {
        AnimatedCheckmark()
          .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          .frame(width: 20, height: 20)
      }
    }
    .transition(.scale.combined(with: .opacity))
  }

  // MARK: - Failure State

  private var failureIcon: some View {
    ZStack {
      Circle()
        .fill(Color.red)
        .frame(width: ringSize, height: ringSize)

      Image(systemName: "xmark")
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.white)
    }
    .transition(.scale.combined(with: .opacity))
  }
}

// MARK: - Spinning Arc (Indeterminate)

private struct SpinningArc: View {
  let lineWidth: CGFloat
  @State private var rotation: Double = 0

  var body: some View {
    Circle()
      .trim(from: 0, to: 0.7)
      .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
      .rotationEffect(.degrees(rotation))
      .onAppear {
        withAnimation(QuickAccessAnimations.progressRotation) {
          rotation = 360
        }
      }
  }
}

// MARK: - Animated Checkmark

private struct AnimatedCheckmark: Shape {
  var progress: CGFloat = 1

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()

    let start = CGPoint(x: rect.minX, y: rect.midY)
    let mid = CGPoint(x: rect.width * 0.4, y: rect.maxY)
    let end = CGPoint(x: rect.maxX, y: rect.minY)

    let totalLength = distance(start, mid) + distance(mid, end)
    let currentLength = totalLength * progress

    path.move(to: start)

    let firstSegmentLength = distance(start, mid)
    if currentLength <= firstSegmentLength {
      let t = currentLength / firstSegmentLength
      let point = interpolate(start, mid, t: t)
      path.addLine(to: point)
    } else {
      path.addLine(to: mid)
      let remaining = currentLength - firstSegmentLength
      let secondSegmentLength = distance(mid, end)
      let t = min(remaining / secondSegmentLength, 1)
      let point = interpolate(mid, end, t: t)
      path.addLine(to: point)
    }

    return path
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    sqrt(pow(b.x - a.x, 2) + pow(b.y - a.y, 2))
  }

  private func interpolate(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
  }
}

// MARK: - Animated Checkmark Container

private struct AnimatedCheckmarkView: View {
  @State private var progress: CGFloat = 0

  var body: some View {
    AnimatedCheckmark(progress: progress)
      .onAppear {
        withAnimation(QuickAccessAnimations.checkmarkDraw) {
          progress = 1
        }
      }
  }
}
