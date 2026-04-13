//
//  ScrollingCapturePreviewView.swift
//  Snapzy
//
//  SwiftUI content for the scrolling capture preview rail.
//

import SwiftUI

enum ScrollingCapturePreviewLayout {
  static let panelWidth: CGFloat = 244
  static let previewWidth: CGFloat = 220
  static let minPreviewHeight: CGFloat = 160
  static let maxPreviewHeight: CGFloat = 420

  static func previewHeight(for image: CGImage?) -> CGFloat {
    guard let image, image.width > 0, image.height > 0 else {
      return minPreviewHeight
    }

    let scaledHeight = previewWidth * CGFloat(image.height) / CGFloat(image.width)
    return min(maxPreviewHeight, max(minPreviewHeight, scaledHeight))
  }
}

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
    let previewHeight = ScrollingCapturePreviewLayout.previewHeight(for: model.activePreviewImage)

    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text(L10n.Common.preview)
          .font(.system(size: 12, weight: .semibold))

        Text(model.previewTruthState.badgeLabel ?? "")
          .contentTransition(.numericText())
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            Capsule(style: .continuous)
              .fill(badgeColor)
          )
          .opacity(model.previewTruthState.badgeLabel != nil ? 1 : 0)
          .animation(.easeInOut(duration: 0.2), value: model.previewTruthState)
      }

      Group {
        if let previewImage = model.activePreviewImage {
          GeometryReader { geometry in
            ScrollingCapturePreviewRenderer(
              image: previewImage,
              scaling: .fit
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
            Text(L10n.ScrollingCapture.captionStartCaptureToLockFirstFrame + ".")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(width: ScrollingCapturePreviewLayout.previewWidth, height: previewHeight)
      .animation(.easeInOut(duration: 0.25), value: previewHeight)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.black.opacity(0.08))
      )

      Text(model.previewCaption)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(width: ScrollingCapturePreviewLayout.panelWidth)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(Color.white.opacity(0.12))
    )
  }
}
