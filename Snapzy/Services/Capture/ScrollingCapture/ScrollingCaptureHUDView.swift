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

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Scrolling Capture")
            .font(.system(size: 13, weight: .semibold))
          Text(model.selectionSummary)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }

        Spacer()

        if model.phase == .ready {
          Button("Start Capture", action: onStart)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
          Button("Cancel", action: onCancel)
            .buttonStyle(.bordered)
            .controlSize(.small)

          Button("Done", action: onDone)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.phase == .saving)
        }
      }

      HStack(spacing: 8) {
        Toggle("Auto-scroll", isOn: Binding(
          get: { model.autoScrollEnabled },
          set: {
            model.autoScrollEnabled = $0
            UserDefaults.standard.set($0, forKey: PreferencesKeys.scrollingCaptureAutoScrollEnabled)
          }
        ))
        .toggleStyle(.switch)
        .disabled(!model.autoScrollAvailable || model.phase != .ready)

        Text(model.autoScrollStatusText)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }

      if model.isAutoScrolling {
        Text("Auto-scroll running")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }

      if model.phase != .ready {
        Text(model.runtimeState.label)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
      }

      if model.acceptedFrameCount > 0 {
        Text("\(model.acceptedFrameCount) frame\(model.acceptedFrameCount == 1 ? "" : "s") stitched • \(model.stitchedPixelHeight) px")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }

      Text(model.statusText)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(width: 320)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.white.opacity(0.12))
    )
  }
}
