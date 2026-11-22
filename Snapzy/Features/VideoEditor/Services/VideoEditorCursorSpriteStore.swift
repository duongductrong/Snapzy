//
//  VideoEditorCursorSpriteStore.swift
//  Snapzy
//
//  Loads a Studio recording's captured cursor PNGs once (plus the arrow fallback) and
//  hands them to the preview (CGImage) and the export/flatten layer (CIImage).
//

import AppKit
import CoreImage

nonisolated struct VideoEditorCursorSpriteImage: @unchecked Sendable {
  let cgImage: CGImage
  let hotspot: CGPoint
  let pointSize: CGSize

  var sprite: VideoEditorCursorSprite {
    VideoEditorCursorSprite(image: CIImage(cgImage: cgImage), hotspot: hotspot, pointSize: pointSize)
  }
}

@MainActor
struct VideoEditorCursorSpriteStore {
  static let empty = VideoEditorCursorSpriteStore(images: [:], arrow: nil)

  let images: [Int: VideoEditorCursorSpriteImage]
  let arrow: VideoEditorCursorSpriteImage?

  static func load(capture: RecordingCursorCapture?) -> VideoEditorCursorSpriteStore {
    guard let capture else { return .empty }
    var images: [Int: VideoEditorCursorSpriteImage] = [:]
    if let folder = capture.imagesFolderName,
       let folderURL = try? RecordingMetadataStore.sidecarURL(named: folder, kind: .cursorImages) {
      for image in capture.images {
        let url = folderURL.appendingPathComponent(image.fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { continue }
        images[image.id] = VideoEditorCursorSpriteImage(cgImage: cgImage, hotspot: image.hotspot, pointSize: image.pointSize)
      }
    }
    return VideoEditorCursorSpriteStore(images: images, arrow: arrowImage())
  }

  func sprite(for imageID: Int?) -> VideoEditorCursorSpriteImage? {
    imageID.flatMap { images[$0] } ?? arrow
  }

  func makeLayer(
    metadata: RecordingMetadata,
    settings: VideoEditorCursorSettings,
    mapping: VideoEditorSourceTimeMapping,
    motionBlur: VideoEditorMotionBlurSettings = .disabled
  ) -> VideoEditorCursorLayer? {
    guard let capture = metadata.cursorCapture, !metadata.isCursorBaked else { return nil }
    return VideoEditorCursorLayer(
      resolver: VideoEditorCursorResolver(samples: metadata.mouseSamples, capture: capture, settings: settings),
      mapping: mapping,
      captureSize: metadata.captureSize,
      sprites: images.mapValues(\.sprite),
      arrow: arrow?.sprite,
      motionBlur: motionBlur
    )
  }

  private static func arrowImage() -> VideoEditorCursorSpriteImage? {
    let arrow = NSCursor.arrow
    let size = arrow.image.size
    var rect = CGRect(origin: .zero, size: CGSize(width: size.width * 2, height: size.height * 2))
    guard let cgImage = arrow.image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
    return VideoEditorCursorSpriteImage(cgImage: cgImage, hotspot: arrow.hotSpot, pointSize: size)
  }
}
