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
  /// Editor state for layers that need it (`nil` in previews/tests).
  var state: VideoEditorState?
  /// `.canvas` only: where the video sits inside `size`, top-left coordinates.
  var videoRect: CGRect?

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

  /// Cursor + click effects (phase 2).
  @ViewBuilder
  private var sourceSpaceLayers: some View {
    if let state {
      VideoEditorCursorOverlayView(state: state, size: size)
    }
  }

  /// Camera, then captions on top (same order as the export recipe).
  @ViewBuilder
  private var canvasSpaceLayers: some View {
    if let state {
      let rect = videoRect ?? CGRect(origin: .zero, size: size)
      VideoEditorCameraOverlayView(state: state, videoRect: rect)
      VideoEditorCaptionOverlayView(state: state, videoRect: rect)
    }
  }
}
