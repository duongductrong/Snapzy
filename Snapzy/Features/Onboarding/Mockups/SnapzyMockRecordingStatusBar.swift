//
//  SnapzyMockRecordingStatusBar.swift
//  Snapzy
//
//  Faithful replica of Snapzy's floating RecordingStatusBarView shown during active recording.
//  Layout: [≡] | [● 00:00:0X] | [⏸] [✏️] | [↺] | [🗑] | [Stop]
//

import SwiftUI

struct SnapzyMockRecordingStatusBar: View {
  let elapsedSeconds: Int
  let onStop: () -> Void

  @State private var indicatorOpacity: Double = 1.0
  @Environment(\.snapzyMockSceneIsLive) private var isSceneLive
  @State private var hoveredButton: String? = nil
  @State private var isStopHovered = false

  private var formattedTime: String {
    let secs = max(0, min(elapsedSeconds, 59))
    return String(format: "00:00:%02d", secs)
  }

  var body: some View {
    HStack(spacing: SnapzySpace.xs) {
      // Drag handle icon
      Image(systemName: "line.3.horizontal")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(SnapzyGlassInk.faint)
        .frame(width: 16, height: 16)

      divider

      // Recording indicator + monospace timer
      HStack(spacing: SnapzySpace.sm) {
        Circle()
          .fill(Color.red)
          .frame(width: 7, height: 7)
          .opacity(indicatorOpacity)
          .onAppear {
            if isSceneLive { startPulse() }
          }
          .onChange(of: isSceneLive) { isLive in
            if isLive {
              startPulse()
            } else {
              var transaction = Transaction()
              transaction.disablesAnimations = true
              withTransaction(transaction) { indicatorOpacity = 1.0 }
            }
          }

        Text(formattedTime)
          .font(.system(size: 11.5, weight: .medium, design: .monospaced))
          .foregroundStyle(SnapzyGlassInk.primary)

        // Mini audio waveform
        HStack(spacing: 1.5) {
          ForEach(0 ..< 3) { i in
            RoundedRectangle(cornerRadius: 1, style: .continuous)
              .fill(Color.green.opacity(0.85))
              .frame(width: 2, height: CGFloat([6, 11, 8][(i + elapsedSeconds) % 3]))
              .animation(SnapzyMotionPreferences.shared.spec(.hover).animation, value: elapsedSeconds)
          }
        }
        .frame(height: 12)
        .padding(.leading, 2)
      }
      .padding(.horizontal, SnapzySpace.sm)

      divider

      // Pause button
      actionButton(id: "pause", icon: "pause.fill")

      // Annotate button
      actionButton(id: "annotate", icon: "pencil.tip.crop.circle")

      divider

      // Restart button
      actionButton(id: "restart", icon: "arrow.counterclockwise")

      // Delete button
      actionButton(id: "delete", icon: "trash")

      divider

      // Stop button
      Button(action: onStop) {
        Text(L10n.Onboarding.mockStop)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(Color.white)
          .padding(.horizontal, SnapzySpace.lg)
          .padding(.vertical, 4.5)
          .background(
            Radius.rect(Radius.controlM)
              .fill(isStopHovered ? Color.red.opacity(0.90) : Color.red)
          )
          .overlay(
            Radius.rect(Radius.controlM)
              .strokeBorder(Color.white.opacity(0.25), lineWidth: SnapzySurfaceGlass.specularLineWidth)
          )
      }
      .buttonStyle(.plain)
      .onHover { h in isStopHovered = h }
    }
    .padding(.horizontal, SnapzySpace.md)
    .padding(.vertical, SnapzySpace.xs)
    .background {
      SnapzyGlassSurface(
        shape: Radius.rect(Radius.controlM),
        substrate: SnapzySurfaceGlass.baseDarkness,
        tint: 0.12
      )
    }
    .clipShape(Radius.rect(Radius.controlM))
    .shadow(color: SnapzyGlassShadow.controlColor, radius: SnapzyGlassShadow.controlRadius,
            y: SnapzyGlassShadow.controlY)
    .shadow(color: Color.black.opacity(0.12), radius: SnapzySpace.lg, y: 2)
  }

  private func actionButton(id: String, icon: String) -> some View {
    Image(systemName: icon)
      .font(.system(size: 10.5, weight: .medium))
      .foregroundStyle(SnapzyGlassInk.body)
      .frame(width: 22, height: 22)
      .background(
        Radius.rect(Radius.controlS)
          .fill(hoveredButton == id ? SnapzyGlassInk.fillHover : Color.clear)
      )
      .onHover { h in hoveredButton = h ? id : nil }
  }

  /// A steady red dot carries the same meaning; the pulse is the motion-rich variant.
  private func startPulse() {
    guard !SnapzyMotionPreferences.shared.reduceMotion else { return }
    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
      indicatorOpacity = 0.3
    }
  }

  private var divider: some View {
    Rectangle()
      .fill(SnapzyGlassInk.hairlineStrong)
      .frame(width: 1, height: 16)
      .padding(.horizontal, 2)
  }
}
