//
//  ScrollingCapturePreviewView.swift
//  Snapzy
//
//  SwiftUI content for the scrolling capture preview rail.
//

import SwiftUI

struct ScrollingCapturePreviewView: View {
  @ObservedObject var model: ScrollingCaptureSessionModel

  private var isShowingLivePreview: Bool {
    model.phase == .capturing && model.isUsingLivePreview && model.livePreviewImage != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text("Preview")
          .font(.system(size: 12, weight: .semibold))

        if isShowingLivePreview {
          Text("Live")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
              Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.9))
            )
        }
      }

      Group {
        if let previewImage = model.activePreviewImage {
          GeometryReader { geometry in
            ScrollingCapturePreviewRenderer(
              image: previewImage,
              scaling: isShowingLivePreview || model.acceptedFrameCount <= 1 ? .fit : .fillBottom
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

      Text(model.previewCaption)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
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
