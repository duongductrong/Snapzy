//
//  AnnotateMainView.swift
//  ClaudeShot
//
//  Main container view for annotation window
//

import SwiftUI

/// Main container for annotation window layout
struct AnnotateMainView: View {
  @StateObject var state: AnnotateState
  @ObservedObject private var themeManager = ThemeManager.shared

  var body: some View {
    VStack(spacing: 0) {
      AnnotateToolbarView(state: state)

      Divider()
        .background(Color(nsColor: .separatorColor))

      HStack(spacing: 0) {
        if state.showSidebar {
          AnnotateSidebarView(state: state)
            .frame(width: 240)
            .transition(.move(edge: .leading))

          Divider()
            .background(Color.white.opacity(0.1))
        }

        AnnotateCanvasView(state: state)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      Divider()
        .background(Color(nsColor: .separatorColor))

      AnnotateBottomBarView(state: state)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .preferredColorScheme(themeManager.systemAppearance)
  }
}
