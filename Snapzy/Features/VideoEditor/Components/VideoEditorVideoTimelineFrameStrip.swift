//
//  VideoEditorVideoTimelineFrameStrip.swift
//  Snapzy
//
//  Horizontal strip of video frame thumbnails
//

import SwiftUI

/// Displays extracted frame thumbnails in a horizontal strip
struct VideoTimelineFrameStrip: View {
  let thumbnails: [NSImage]
  let isLoading: Bool

  var body: some View {
    GeometryReader { geometry in
      if isLoading || thumbnails.isEmpty {
        // Loading state
        HStack {
          Spacer()
          ProgressView()
            .scaleEffect(0.8)
          Text(L10n.VideoEditorTimeline.extractingFrames)
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
      } else {
        // Frame thumbnails — one cell per extraction slot; the image fits
        // inside its cell (never scaled to fill, which crops the frame) so the
        // whole frame stays visible at every zoom level.
        HStack(spacing: 0) {
          ForEach(0 ..< thumbnails.count, id: \.self) { index in
            Image(nsImage: thumbnails[index])
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(
                width: geometry.size.width / CGFloat(thumbnails.count),
                height: geometry.size.height
              )
          }
        }
      }
    }
    .frame(maxHeight: .infinity)
    .clipShape(Radius.rect(Radius.tile))
    .overlay(
      // Same hairline rim the recessed lane wells use, so the content track
      // and the effect tracks read as one timeline family.
      Radius.rect(Radius.tile)
        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
    )
    .clipped()
  }
}
