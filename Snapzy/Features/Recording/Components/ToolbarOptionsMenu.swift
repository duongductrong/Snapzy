//
//  ToolbarOptionsMenu.swift
//  Snapzy
//
//  Options dropdown menu for recording toolbar with format, quality, and audio settings
//

import SwiftUI

struct ToolbarOptionsMenu: View {
  @Binding var selectedFormat: VideoFormat
  @Binding var selectedQuality: VideoQuality
  @Binding var captureAudio: Bool

  @State private var isHovered = false

  var body: some View {
    Menu {
      // Format section
      Section("Format") {
        ForEach(VideoFormat.allCases, id: \.self) { format in
          Button {
            selectedFormat = format
          } label: {
            HStack {
              Text(format.displayName)
              if selectedFormat == format {
                Spacer()
                Image(systemName: "checkmark")
              }
            }
          }
        }
      }

      Divider()

      // Quality section
      Section("Quality") {
        ForEach(VideoQuality.allCases, id: \.self) { quality in
          Button {
            selectedQuality = quality
          } label: {
            HStack {
              Text(quality.displayName)
              if selectedQuality == quality {
                Spacer()
                Image(systemName: "checkmark")
              }
            }
          }
        }
      }

      Divider()

      // Audio toggle
      Toggle("Capture Audio", isOn: $captureAudio)

    } label: {
      menuLabel
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .onHover { isHovered = $0 }
    .accessibilityLabel("Recording options")
    .accessibilityHint("Opens menu to change format, quality, and audio settings")
  }

  private var menuLabel: some View {
    HStack(spacing: 4) {
      Text("Options")
      Image(systemName: "chevron.down")
        .font(.system(size: 10, weight: .semibold))
    }
    .font(.system(size: 13, weight: .medium))
    .foregroundColor(.primary)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
        .fill(Color.primary.opacity(isHovered ? 0.1 : 0.05))
    )
    .animation(ToolbarConstants.hoverAnimation, value: isHovered)
  }
}

#Preview {
  ToolbarOptionsMenu(
    selectedFormat: .constant(.mov),
    selectedQuality: .constant(.high),
    captureAudio: .constant(true)
  )
  .padding()
  .background(.ultraThinMaterial)
  .clipShape(RoundedRectangle(cornerRadius: 14))
}
