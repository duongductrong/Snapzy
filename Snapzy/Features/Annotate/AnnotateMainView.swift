//
//  AnnotateMainView.swift
//  Snapzy
//
//  Main container view for annotation window
//

import SwiftUI

/// Main container for annotation window layout
struct AnnotateMainView: View {
  @StateObject var state: AnnotateState
  let eventRouter: AnnotateWindowEventRouter
  @ObservedObject private var themeManager = ThemeManager.shared
  private let quickPropertiesBarHeight: CGFloat = 48

  var body: some View {
    VStack(spacing: 0) {
      // Hide toolbar in preview mode
      if state.editorMode != .preview {
        AnnotateToolbarView(state: state)
          .padding(.top, 0) // Add top padding for traffic lights

        Divider()
          .background(Color(nsColor: .separatorColor))

        AnnotateQuickPropertiesBar(state: state)
          .frame(height: quickPropertiesBarHeight)

        Divider()
          .background(Color(nsColor: .separatorColor))
      }

      HStack(spacing: 0) {
        // Hide sidebar in preview mode
        if state.showSidebar && state.editorMode != .preview {
          AnnotateSidebarView(state: state)
            .equatable()
            .frame(width: 240)
            .transition(.move(edge: .leading))

          Divider()
            .background(Color.white.opacity(0.1))
        }

        AnnotateCanvasView(state: state, eventRouter: eventRouter)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(Rectangle()) // Constrain hit-test area to frame bounds
          .clipped() // Prevent canvas content from overlapping toolbar/bottombar
      }

      Divider()
        .background(Color(nsColor: .separatorColor))

      AnnotateBottomBarView(state: state, eventRouter: eventRouter)
    }
    .preferredColorScheme(themeManager.systemAppearance)
    .ignoresSafeArea(.all, edges: .top) // Extend background behind title bar
    .animation(.easeInOut(duration: 0.14), value: state.showsQuickPropertiesBar)
  }
}
