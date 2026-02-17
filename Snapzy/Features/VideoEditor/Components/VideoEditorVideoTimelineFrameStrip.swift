//
//  VideoTimelineFrameStrip.swift
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
          Text("Extracting frames...")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
      } else {
        // Frame thumbnails
        HStack(spacing: 0) {
          ForEach(0..<thumbnails.count, id: \.self) { index in
            Image(nsImage: thumbnails[index])
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width / CGFloat(thumbnails.count))
              .clipped()
          }
        }
      }
    }
    .frame(height: 50)
    .cornerRadius(4)
    .clipped()
  }
}
