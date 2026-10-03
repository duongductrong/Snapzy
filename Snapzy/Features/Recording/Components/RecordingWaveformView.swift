//
//  RecordingWaveformView.swift
//  Snapzy
//
//  Living waveform rendered behind the recording status bar. The wave does NOT travel
//  horizontally — it stays in place and reacts to the live audio level (0...1) by
//  bouncing its amplitude. Instead of pulsing as one uniform beat, the surface is built
//  from several fixed control points that each react independently: every point has its
//  own amplitude weight and its own phase-offset bob, so the wave feels alive and
//  flexible. All motion scales with the audio level, so silence stays near-flat (no
//  decorative animation) while real sound makes the independent points come alive.
//  Frozen flat when inactive (paused / not recording). Pure-render Canvas — no @State
//  mutation, ~30fps cap to protect recording performance.
//

import SwiftUI

struct RecordingWaveformView: View {
  /// Smoothed audio level in `0...1` from `RecordingAudioLevelMeter`.
  let level: Float
  /// When false (paused / not recording), the wave flattens and stops travelling.
  var isActive: Bool = true

  @Environment(\.colorScheme) private var colorScheme

  /// Moderate span so the wave stays an ambient glow behind the controls —
  /// loud speech swells clearly but peaks don't reach the top edge. The lively
  /// feel comes from the meter's sensitivity, not from a tall amplitude.
  private let maxAmplitudeFraction: CGFloat = 0.45
  /// Resting line sits low-ish so the wave rises upward from a calm baseline.
  private let baselineFraction: CGFloat = 0.72
  /// Very faint residual amplitude while recording: silence stays calm and near
  /// flat (a barely-living glow, not a frozen line) so the wave visibly *rises*
  /// the moment real sound arrives — a clear "audio is being captured" cue.
  private let idleAmplitude: CGFloat = 0.02
  /// Independently-reacting control points across the wave. More points → finer, more
  /// flexible surface; each one bobs on its own phase so the wave never moves in unison.
  private let nodeCount = 9

  var body: some View {
    // The timer only drives each node's phase-offset bob — the wave stays put, it does
    // not travel. Because every node's motion scales with `level`, silence reads as
    // near-flat and only live sound brings the independent points to life. Paused → flat.
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
      Canvas { context, size in
        let t = timeline.date.timeIntervalSinceReferenceDate
        // While active, never drop below the idle ripple; paused → fully flat.
        let amp = isActive ? max(CGFloat(level), idleAmplitude) : 0
        let path = wavePath(in: size, time: t, amplitude: amp)
        let baseline = size.height * baselineFraction
        context.fill(
          path,
          with: .linearGradient(
            waveGradient,
            startPoint: CGPoint(x: 0, y: baseline - size.height * maxAmplitudeFraction),
            endPoint: CGPoint(x: 0, y: size.height)
          )
        )
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  // MARK: - Geometry

  private func wavePath(in size: CGSize, time: Double, amplitude: CGFloat) -> Path {
    let baseline = size.height * baselineFraction
    let peak = size.height * maxAmplitudeFraction
    let t = CGFloat(time)

    // Resolve each fixed node to a height that bobs on its own weight, speed and phase,
    // so no two points peak at the same instant → a living, non-uniform surface.
    var points: [CGPoint] = []
    points.reserveCapacity(nodeCount)
    for i in 0 ..< nodeCount {
      let f = CGFloat(i)
      let xNorm = nodeCount > 1 ? f / CGFloat(nodeCount - 1) : 0
      let envelope = 0.35 + 0.65 * sin(xNorm * .pi)      // natural arch; edges stay lively
      let weight = 0.6 + 0.4 * abs(sin(f * 1.3 + 0.6))   // per-node amplitude 0.6…1.0
      let speed = 1.4 + 0.7 * (0.5 + 0.5 * sin(f * 2.1)) // per-node bob rate 1.4…2.1
      let phase = f * 1.7                                // spread timing offsets per node
      let wobble = 0.62 + 0.38 * sin(t * speed + phase)  // independent bob, 0.24…1.0
      let h = amplitude * envelope * weight * wobble
      points.append(CGPoint(x: xNorm * size.width, y: baseline - h * peak))
    }

    var path = Path()
    path.move(to: points[0])
    addSmoothCurve(through: points, to: &path) // Catmull-Rom spline through the nodes

    // Close down to the bottom for a filled glow.
    path.addLine(to: CGPoint(x: size.width, y: size.height))
    path.addLine(to: CGPoint(x: 0, y: size.height))
    path.closeSubpath()
    return path
  }

  /// Append a smooth Catmull-Rom spline (expressed as cubic Béziers) through `points`,
  /// so the independently-bobbing nodes read as one flexible wave rather than a polyline.
  private func addSmoothCurve(through points: [CGPoint], to path: inout Path) {
    guard points.count > 1 else { return }
    for i in 0 ..< points.count - 1 {
      let p0 = points[max(i - 1, 0)]
      let p1 = points[i]
      let p2 = points[i + 1]
      let p3 = points[min(i + 2, points.count - 1)]
      let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
      let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
      path.addCurve(to: p2, control1: c1, control2: c2)
    }
  }

  // MARK: - Theming

  private var waveGradient: Gradient {
    colorScheme == .dark
      ? Gradient(colors: [Color.white.opacity(0.20), Color.white.opacity(0.02)])
      : Gradient(colors: [Color.accentColor.opacity(0.24), Color.accentColor.opacity(0.04)])
  }
}

#if DEBUG
  private struct RecordingWaveformPreview: View {
    @State private var level: Double = 0.5
    @State private var isActive = true

    var body: some View {
      VStack(spacing: 16) {
        ForEach([ColorScheme.light, ColorScheme.dark], id: \.self) { scheme in
          RecordingWaveformView(level: Float(level), isActive: isActive)
            .frame(width: 340, height: 36)
            .background(scheme == .dark ? Color.black : Color.white)
            .overlay(Text("00:12  ●  Stop").font(.system(size: 13)))
            .cornerRadius(Radius.card)
            .environment(\.colorScheme, scheme)
        }
        Slider(value: $level, in: 0 ... 1)
        Toggle("Active", isOn: $isActive)
      }
      .padding()
      .frame(width: 380)
    }
  }

  #Preview {
    RecordingWaveformPreview()
  }
#endif
