//
//  AnnotateDropZoneView.swift
//  ClaudeShot
//
//  Drop zone overlay shown when no image is loaded
//

import SwiftUI

/// Drop zone view displayed when annotation canvas has no image
struct AnnotateDropZoneView: View {
  @Binding var isDragOver: Bool

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: 64))
        .foregroundColor(isDragOver ? .accentColor : .secondary)

      Text("Drop an image here")
        .font(.title2)
        .fontWeight(.medium)

      Text("or capture a screenshot to annotate")
        .font(.subheadline)
        .foregroundColor(.secondary)

      HStack(spacing: 8) {
        ForEach(["PNG", "JPG", "GIF", "HEIC"], id: \.self) { format in
          Text(format)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.2))
            .cornerRadius(4)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(
          style: StrokeStyle(lineWidth: 2, dash: [8, 4])
        )
        .foregroundColor(isDragOver ? .accentColor : .secondary.opacity(0.5))
        .padding(40)
    )
    .background(Color(nsColor: .textBackgroundColor))
    .animation(.easeInOut(duration: 0.2), value: isDragOver)
  }
}

#Preview {
  AnnotateDropZoneView(isDragOver: .constant(false))
    .frame(width: 600, height: 400)
}
