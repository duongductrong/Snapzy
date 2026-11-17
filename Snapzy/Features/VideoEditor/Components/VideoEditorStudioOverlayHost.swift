//
//  VideoEditorStudioOverlayHost.swift
//  Snapzy
//
//  Preview hosts for Studio layers. Mirrors the compositor's z-order:
//  - `.source` sits INSIDE the zoom-transformed video container, so whatever it draws
//    is scaled/offset with the screen (cursor, click effects — phase 2).
//  - `.canvas` sits OUTSIDE it, over the whole padded composite, so it is never zoomed
//    (camera — phase 4, captions — phase 5).
//  Layers resolve their state from the same pure resolvers the export compositor uses.
//

import SwiftUI

struct VideoEditorStudioOverlayHost: View {
  let space: VideoEditorStudioLayerSpace
  /// Size of the coordinate space the layers draw into: the displayed video rect for
  /// `.source`, the composite (video + padding) for `.canvas`.
  let size: CGSize

  var body: some View {
    ZStack(alignment: .topLeading) {
      switch space {
      case .source:
        sourceSpaceLayers
      case .canvas:
        canvasSpaceLayers
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// Phase 2 adds the cursor + click effect views here.
  @ViewBuilder
  private var sourceSpaceLayers: some View {
    EmptyView()
  }

  /// Phase 4 adds the camera view, phase 5 the caption view (on top) here.
  @ViewBuilder
  private var canvasSpaceLayers: some View {
    EmptyView()
  }
}
