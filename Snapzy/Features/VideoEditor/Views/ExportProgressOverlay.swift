//
//  ExportProgressOverlay.swift
//  Snapzy
//
//  Modal overlay showing export progress with progress bar
//

import SwiftUI

/// Modal overlay displayed during video export
struct ExportProgressOverlay: View {
  @ObservedObject var state: VideoEditorState

  var body: some View {
    ZStack {
      // Dimmed background
      Color.black.opacity(0.6)
        .ignoresSafeArea()

      // Progress card
      VStack(spacing: 16) {
        // Icon
        Image(systemName: "film")
          .font(.system(size: 32))
          .foregroundColor(ZoomColors.primary)
          .symbolEffect(.pulse, options: .repeating)

        // Title
        Text("Exporting Video")
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.primary)

        // Progress bar
        VStack(spacing: 8) {
          GeometryReader { geometry in
            ZStack(alignment: .leading) {
              // Background track
              RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 8)

              // Progress fill
              RoundedRectangle(cornerRadius: 4)
                .fill(
                  LinearGradient(
                    colors: [ZoomColors.primary, ZoomColors.primaryDark],
                    startPoint: .leading,
                    endPoint: .trailing
                  )
                )
                .frame(width: max(0, geometry.size.width * CGFloat(state.exportProgress)), height: 8)
                .animation(.easeInOut(duration: 0.2), value: state.exportProgress)
            }
          }
          .frame(height: 8)

          // Percentage
          Text("\(Int(state.exportProgress * 100))%")
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
        }

        // Status message
        Text(state.exportStatusMessage)
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }
      .padding(24)
      .frame(width: 280)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color(NSColor.windowBackgroundColor))
          .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
      )
    }
    .transition(.opacity)
  }
}

// MARK: - Preview

#Preview {
  ExportProgressOverlay(
    state: {
      let state = VideoEditorState(url: URL(fileURLWithPath: "/tmp/test.mov"))
      state.isExporting = true
      state.exportProgress = 0.65
      state.exportStatusMessage = "Processing zoom effects..."
      return state
    }()
  )
}
