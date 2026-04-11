//
//  ScrollingCaptureHUDView.swift
//  Snapzy
//
//  SwiftUI content for the scrolling capture control HUD.
//

import SwiftUI

struct ScrollingCaptureHUDView: View {
  @ObservedObject var model: ScrollingCaptureSessionModel
  let onStart: () -> Void
  let onDone: () -> Void
  let onCancel: () -> Void

  private var capturedSummary: String {
    let count = model.acceptedFrameCount
    return "\(count) section\(count == 1 ? "" : "s") captured"
  }

  private var headerSummary: String {
    guard model.acceptedFrameCount > 0 else { return model.selectionSummary }
    return "\(model.selectionSummary) • \(capturedSummary)"
  }

  var body: some View {
    HStack(spacing: 10) {
      // MARK: - Left: Title + summary
      VStack(alignment: .leading, spacing: 1) {
        Text("Scrolling Capture")
          .font(.system(size: 12, weight: .semibold))
        Text(headerSummary)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      // MARK: - Divider
      Divider()
        .frame(height: 18)
        .opacity(0.3)

      // MARK: - Action buttons
      if model.phase == .ready {
        Button("Cancel", action: onCancel)
          .buttonStyle(.bordered)
          .controlSize(.small)

        Button("Start Capture", action: onStart)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(!model.canStartCapture)
      } else {
        Button("Cancel", action: onCancel)
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(!model.canCancelSession)

        Button("Done", action: onDone)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(!model.canFinishCapture)
      }
    }
    .padding(12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.white.opacity(0.12))
    )
  }
}
