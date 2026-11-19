//
//  VideoEditorStudioRecipe.swift
//  Snapzy
//
//  Immutable snapshot of the Studio layers (cursor, camera, captions) carried into the
//  export compositor. Each layer resolves its state from OUTPUT time through a pure
//  resolver, so preview and export can share it.
//

import CoreImage
import CoreMedia
import CoreVideo
import Foundation

/// Where a Studio layer is composited relative to zoom and background.
nonisolated enum VideoEditorStudioLayerSpace: Sendable {
  /// Before the zoom crop: the layer moves and scales with the screen (cursor, clicks).
  case source
  /// After canvas/background: the layer is never zoomed (camera, captions).
  case canvas
}

/// Extra source tracks a layer reads from the composition (e.g. the camera sidecar).
nonisolated enum VideoEditorStudioAuxiliaryTrack: String, Sendable, Hashable, CaseIterable {
  case camera
}

/// Per-frame inputs handed to a Studio layer by the compositor.
nonisolated struct VideoEditorStudioLayerContext {
  /// Composition (output) time of the frame being rendered, in seconds.
  let outputTime: TimeInterval
  /// Extent of the image the layer draws on: source frame size for `.source`,
  /// padded canvas size for `.canvas`.
  let extent: CGRect
  /// Decoded frames of auxiliary tracks present at this time, keyed by role.
  let auxiliaryFrames: [VideoEditorStudioAuxiliaryTrack: CVPixelBuffer]
  /// Where the (zoomed) video frame sits inside `extent`, Core Image coordinates.
  /// Equals `extent` for `.source` layers and when there is no padding.
  let videoRect: CGRect

  init(
    outputTime: TimeInterval,
    extent: CGRect,
    auxiliaryFrames: [VideoEditorStudioAuxiliaryTrack: CVPixelBuffer],
    videoRect: CGRect? = nil
  ) {
    self.outputTime = outputTime
    self.extent = extent
    self.auxiliaryFrames = auxiliaryFrames
    self.videoRect = videoRect ?? extent
  }
}

/// A Studio layer the export compositor can draw. Implementations must be pure value
/// snapshots: the compositor calls them from its own queue.
nonisolated protocol VideoEditorStudioLayer: Sendable {
  var space: VideoEditorStudioLayerSpace { get }
  /// False when the layer is configured but contributes nothing (hidden, empty data).
  var isActive: Bool { get }
  /// Auxiliary tracks this layer needs decoded, if any.
  var auxiliaryTracks: Set<VideoEditorStudioAuxiliaryTrack> { get }
  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage
}

nonisolated extension VideoEditorStudioLayer {
  var auxiliaryTracks: Set<VideoEditorStudioAuxiliaryTrack> { [] }
}

/// Sendable recipe for all Studio layers of one export. Empty until later phases add
/// cursor (phase 2), camera (phase 4) and caption (phase 5) layers.
nonisolated struct VideoEditorStudioRecipe: Sendable {
  static let empty = VideoEditorStudioRecipe(layers: [])

  /// Layers in z-order within their space (first drawn first).
  let layers: [any VideoEditorStudioLayer]

  init(layers: [any VideoEditorStudioLayer]) {
    self.layers = layers
  }

  var activeLayers: [any VideoEditorStudioLayer] { layers.filter(\.isActive) }

  /// True when at least one layer draws something; gates the compositor export path
  /// and disables the compositor pass-through shortcut.
  var hasActiveLayers: Bool { layers.contains { $0.isActive } }

  func activeLayers(in space: VideoEditorStudioLayerSpace) -> [any VideoEditorStudioLayer] {
    layers.filter { $0.isActive && $0.space == space }
  }

  var requiredAuxiliaryTracks: Set<VideoEditorStudioAuxiliaryTrack> {
    activeLayers.reduce(into: Set()) { $0.formUnion($1.auxiliaryTracks) }
  }

  /// Draws every active layer of `space` onto `image`, in order.
  func composite(
    _ image: CIImage,
    space: VideoEditorStudioLayerSpace,
    outputTime: TimeInterval,
    auxiliaryFrames: [VideoEditorStudioAuxiliaryTrack: CVPixelBuffer],
    videoRect: CGRect? = nil
  ) -> CIImage {
    let spaceLayers = activeLayers(in: space)
    guard !spaceLayers.isEmpty else { return image }
    let context = VideoEditorStudioLayerContext(
      outputTime: outputTime,
      extent: image.extent,
      auxiliaryFrames: auxiliaryFrames,
      videoRect: videoRect
    )
    return spaceLayers.reduce(image) { partial, layer in
      layer.composite(onto: partial, context: context)
    }
  }
}
