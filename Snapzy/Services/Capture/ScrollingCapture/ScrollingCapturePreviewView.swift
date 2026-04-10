//
//  ScrollingCapturePreviewView.swift
//  Snapzy
//
//  SwiftUI content for the scrolling capture preview rail.
//

import SwiftUI

struct ScrollingCapturePreviewView: View {
  @ObservedObject var model: ScrollingCaptureSessionModel

  private var badgeColor: Color {
    switch model.previewTruthState {
    case .committedOnly:
      return .secondary.opacity(0.9)
    case .liveSynced:
      return .green.opacity(0.9)
    case .liveAhead:
      return .orange.opacity(0.95)
    case .pausedRecovery:
      return .yellow.opacity(0.9)
    case .finalizing, .saving:
      return .blue.opacity(0.9)
    case .ready:
      return .clear
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text("Preview")
          .font(.system(size: 12, weight: .semibold))

        if let badgeLabel = model.previewTruthState.badgeLabel {
          Text(badgeLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
              Capsule(style: .continuous)
                .fill(badgeColor)
            )
        }
      }

      Group {
        if let previewImage = model.activePreviewImage {
          GeometryReader { geometry in
            ScrollingCapturePreviewRenderer(
              image: previewImage,
              scaling: model.isShowingLiveViewport || model.acceptedFrameCount <= 1 ? .fit : .fillBottom
            )
              .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .center
              )
              .clipped()
          }
        } else {
          VStack(spacing: 8) {
            Image(systemName: "photo")
              .font(.system(size: 22, weight: .medium))
              .foregroundStyle(.secondary)
            Text("Start Capture to lock the first frame.")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(width: 220, height: 160)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.black.opacity(0.08))
      )

      VStack(alignment: .leading, spacing: 4) {
        Text(model.previewCaption)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if model.phase != .ready {
          Text(model.previewTruthDescription)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(12)
    .frame(width: 244)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(Color.white.opacity(0.12))
    )
  }
}
