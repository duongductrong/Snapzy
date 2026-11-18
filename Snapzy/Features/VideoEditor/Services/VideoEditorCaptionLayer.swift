//
//  VideoEditorCaptionLayer.swift
//  Snapzy
//
//  Canvas-space Studio layer burning captions into the export, on top of the camera.
//  Lays the caption out against the video rect the compositor passes, with the same
//  CoreText layout the preview uses.
//

import CoreImage
import Foundation

nonisolated struct VideoEditorCaptionLayer: VideoEditorStudioLayer, @unchecked Sendable {
  let resolver: VideoEditorCaptionResolver
  let mapping: VideoEditorSourceTimeMapping
  let sequenceMap: TimelineSequenceMap
  private let cache = VideoEditorCaptionImageCache()

  init(captions: VideoEditorCaptions, mapping: VideoEditorSourceTimeMapping, sequenceMap: TimelineSequenceMap) {
    resolver = VideoEditorCaptionResolver(captions: captions)
    self.mapping = mapping
    self.sequenceMap = sequenceMap
  }

  var space: VideoEditorStudioLayerSpace { .canvas }
  var isActive: Bool { resolver.settings.isEnabled && !resolver.segments.isEmpty }

  func composite(onto image: CIImage, context: VideoEditorStudioLayerContext) -> CIImage {
    guard let sourceTime = mapping.sourceTime(output: context.outputTime) else { return image }
    let rate = sequenceMap.rate(atSequence: sequenceMap.toSequence(context.outputTime))
    guard let segment = resolver.segment(atSource: sourceTime, rate: rate) else { return image }
    let videoRect = context.videoRect
    guard let entry = cache.entry(text: segment.text, settings: resolver.settings, videoSize: videoRect.size) else {
      return image
    }
    // Layout frames are top-left within the video rect; Core Image is bottom-up.
    let topLeft = entry.layout.frame(in: CGRect(origin: .zero, size: videoRect.size), settings: resolver.settings)
    let origin = CGPoint(x: videoRect.minX + topLeft.minX, y: videoRect.maxY - topLeft.maxY)
    let caption = CIImage(cgImage: entry.image)
      .transformed(by: CGAffineTransform(translationX: origin.x.rounded(), y: origin.y.rounded()))
    return caption.composited(over: image)
  }
}
