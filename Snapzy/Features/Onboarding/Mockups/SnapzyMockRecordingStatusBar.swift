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
  @State private var hoveredButton: String? = nil
  @State private var isStopHovered = false

  private var formattedTime: String {
    let secs = max(0, min(elapsedSeconds, 59))
    return String(format: "00:00:%02d", secs)
  }

  var body: some View {
    HStack(spacing: 4) {
      // Drag handle icon
      Image(systemName: "line.3.horizontal")
        .font(.system(size: 9, weight: .bold))
        .foregroundColor(.primary.opacity(0.35))
        .frame(width: 16, height: 16)

      divider

      // Recording indicator + monospace timer
      HStack(spacing: 6) {
        Circle()
          .fill(Color.red)
          .frame(width: 7, height: 7)
          .opacity(indicatorOpacity)
          .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: indicatorOpacity)
          .onAppear { indicatorOpacity = 0.3 }

        Text(formattedTime)
          .font(.system(size: 11.5, weight: .medium, design: .monospaced))
          .foregroundColor(.primary)

        // Mini audio waveform
        HStack(spacing: 1.5) {
          ForEach(0..<3) { i in
            RoundedRectangle(cornerRadius: 1)
              .fill(Color.green.opacity(0.85))
              .frame(width: 2, height: CGFloat([6, 11, 8][(i + elapsedSeconds) % 3]))
              .animation(.easeInOut(duration: 0.3), value: elapsedSeconds)
          }
        }
        .frame(height: 12)
        .padding(.leading, 2)
      }
      .padding(.horizontal, 6)

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
          .foregroundColor(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 4.5)
          .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(isStopHovered ? Color.red.opacity(0.90) : Color.red)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
          )
      }
      .buttonStyle(.plain)
      .onHover { h in isStopHovered = h }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.30), radius: 18, y: 7)
    .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
  }

  private func actionButton(id: String, icon: String) -> some View {
    Image(systemName: icon)
      .font(.system(size: 10.5, weight: .medium))
      .foregroundColor(.primary.opacity(0.85))
      .frame(width: 22, height: 22)
      .background(
        RoundedRectangle(cornerRadius: 5)
          .fill(hoveredButton == id ? Color.primary.opacity(0.10) : Color.clear)
      )
      .onHover { h in hoveredButton = h ? id : nil }
  }

  private var divider: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.15))
      .frame(width: 1, height: 16)
      .padding(.horizontal, 2)
  }
}
