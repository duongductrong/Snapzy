//
//  VideoEditorBottomBar.swift
//  Snapzy
//
//  Bottom bar for video editor with Cancel and Convert actions
//

import SwiftUI

/// Bottom bar for video editor with Cancel and Convert buttons
struct VideoEditorBottomBar: View {
  var onCancel: () -> Void
  var onConvert: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Divider()

      HStack {
        // Cancel button (left)
        Button("Cancel", action: onCancel)
          .buttonStyle(.bordered)

        Spacer()

        // Convert button (right) - always enabled
        Button("Convert", action: onConvert)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut("s", modifiers: [.command])
      }
      .padding(.horizontal, WindowSpacingConfiguration.default.toolbarHPadding)
      .padding(.vertical, 12)
    }
  }
}

// MARK: - Preview

#Preview {
  VideoEditorBottomBar(
    onCancel: {},
    onConvert: {}
  )
  .frame(width: 600)
  .background(Color(NSColor.windowBackgroundColor))
}
