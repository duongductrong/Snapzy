//
//  VideoEditorVideoPlayerSection.swift
//  Snapzy
//
//  NSViewRepresentable wrapper for AVPlayerView (pure, untouched hardware Retina video)
//  plus a zero-copy full-resolution Metal `MTKView` overlay (`MetalShutterPreviewView`)
//  that renders the exact physical shutter-angle motion blur kernel during active camera
//  transitions without ever rasterizing or pixelating the underlying AVPlayerView.
//

import AVFoundation
import AVKit
import CoreVideo
import Metal
import MetalKit
import QuartzCore
import SwiftUI

/// SwiftUI wrapper for AVPlayerView with custom controls disabled.
/// Kept completely free of `CALayer.filters` so macOS never drops video into low-res
/// offscreen rasterization when scaled during zoom transitions.
struct VideoPlayerSection: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context _: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.player = player
    view.controlsStyle = .none
    view.showsFullScreenToggleButton = false
    view.videoGravity = .resizeAspect
    return view
  }

  func updateNSView(_ view: AVPlayerView, context _: Context) {
    if view.player !== player {
      view.player = player
    }
  }
}

/// Full-Retina Metal overlay that reads native-resolution video frames from `AVPlayerItemVideoOutput`
/// via zero-copy `CVMetalTextureCache` and executes the same single-pass physical shutter-angle
/// compute shader used by export. Completely hidden (`isHidden = true`, 0% GPU cost) whenever
/// playback is paused or the camera is stationary.
struct MetalShutterPreviewView: NSViewRepresentable {
  let player: AVPlayer
  let shutterPlan: VideoEditorMotionBlurEngine.ShutterPlan
  let isPlaying: Bool

  final class Coordinator {
    let device: MTLDevice?
    let commandQueue: MTLCommandQueue?
    var textureCache: CVMetalTextureCache?
    let videoOutput: AVPlayerItemVideoOutput
    weak var attachedItem: AVPlayerItem?
    var lastPixelBuffer: CVPixelBuffer?
    var lastRenderedPlan: VideoEditorMotionBlurEngine.ShutterPlan = .inactive
    var lastFrameHostTime: CFTimeInterval = 0

    init() {
      let dev = MTLCreateSystemDefaultDevice()
      self.device = dev
      self.commandQueue = dev?.makeCommandQueue()
      if let dev {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)
        self.textureCache = cache
      }
      self.videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
      ])
      self.videoOutput.suppressesPlayerRendering = false
    }

    func attachIfNeeded(to item: AVPlayerItem?) {
      guard attachedItem !== item else { return }
      if let old = attachedItem {
        old.remove(videoOutput)
      }
      attachedItem = item
      lastPixelBuffer = nil
      if let item {
        item.add(videoOutput)
      }
    }

    func detach() {
      if let old = attachedItem {
        old.remove(videoOutput)
      }
      attachedItem = nil
      lastPixelBuffer = nil
      if let cache = textureCache {
        CVMetalTextureCacheFlush(cache, 0)
      }
    }

    deinit {
      detach()
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> MTKView {
    let view = MTKView(frame: .zero, device: context.coordinator.device)
    view.isPaused = true
    view.enableSetNeedsDisplay = false
    view.framebufferOnly = false
    view.autoResizeDrawable = true
    view.colorPixelFormat = .bgra8Unorm
    view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    view.layer?.isOpaque = false
    view.isHidden = true
    context.coordinator.attachIfNeeded(to: player.currentItem)
    return view
  }

  static func dismantleNSView(_ nsView: MTKView, coordinator: Coordinator) {
    nsView.isHidden = true
    coordinator.detach()
  }

  func updateNSView(_ view: MTKView, context: Context) {
    let coordinator = context.coordinator
    let currentItem = player.currentItem
    coordinator.attachIfNeeded(to: currentItem)

    guard isPlaying,
          shutterPlan.isActive,
          let currentItem,
          let device = coordinator.device,
          let commandQueue = coordinator.commandQueue,
          let textureCache = coordinator.textureCache,
          view.bounds.width > 1,
          view.bounds.height > 1
    else {
      if !view.isHidden {
        view.isHidden = true
      }
      coordinator.lastPixelBuffer = nil
      coordinator.lastRenderedPlan = .inactive
      return
    }

    // Grab the latest full-resolution native CVPixelBuffer (e.g. 3360×2100) for the current frame.
    let nowHost = CACurrentMediaTime()
    let hostItemTime = coordinator.videoOutput.itemTime(forHostTime: nowHost)
    var freshBuffer: CVPixelBuffer?
    if hostItemTime.isValid && !hostItemTime.isIndefinite {
      freshBuffer = coordinator.videoOutput.copyPixelBuffer(
        forItemTime: hostItemTime,
        itemTimeForDisplay: nil
      )
    }
    if freshBuffer == nil {
      let playerTime = currentItem.currentTime()
      if playerTime.isValid && !playerTime.isIndefinite {
        freshBuffer = coordinator.videoOutput.copyPixelBuffer(
          forItemTime: playerTime,
          itemTimeForDisplay: nil
        )
      }
    }

    if let freshBuffer {
      coordinator.lastPixelBuffer = freshBuffer
      coordinator.lastFrameHostTime = nowHost
    } else if nowHost - coordinator.lastFrameHostTime > 0.12 {
      // Stale buffer safety guard (e.g. seek stall): fall back cleanly to sharp AVPlayerView.
      coordinator.lastPixelBuffer = nil
    }

    guard let pixelBuffer = coordinator.lastPixelBuffer else {
      if !view.isHidden {
        view.isHidden = true
      }
      return
    }

    let srcW = CVPixelBufferGetWidth(pixelBuffer)
    let srcH = CVPixelBufferGetHeight(pixelBuffer)
    guard srcW > 1, srcH > 1 else {
      view.isHidden = true
      return
    }

    // Guard against rotated portrait tracks whose raw pixel buffer hasn't had preferredTransform applied.
    let srcAspect = Double(srcW) / Double(srcH)
    let viewAspect = Double(view.bounds.width) / Double(view.bounds.height)
    guard abs(srcAspect - viewAspect) <= 0.08 else {
      view.isHidden = true
      return
    }

    // Match the exact Retina backing scale so drawableSize is 100% native display pixels.
    let scale = max(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0, 1.0)
    let targetDrawableSize = CGSize(
      width: max(1, (view.bounds.width * scale).rounded()),
      height: max(1, (view.bounds.height * scale).rounded())
    )
    if view.drawableSize != targetDrawableSize {
      view.drawableSize = targetDrawableSize
    }

    // Match source/window colorspace so AVPlayerView <-> MTKView handoff has zero color shift.
    if let attachment = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey, nil),
       CFGetTypeID(attachment) == CGColorSpace.typeID {
      let cs = attachment as! CGColorSpace
      if view.colorspace != cs {
        view.colorspace = cs
      }
    } else if let winCS = view.window?.colorSpace?.cgColorSpace, view.colorspace != winCS {
      view.colorspace = winCS
    }

    var cvMetalTex: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault,
      textureCache,
      pixelBuffer,
      nil,
      .bgra8Unorm,
      srcW,
      srcH,
      0,
      &cvMetalTex
    )
    guard status == kCVReturnSuccess,
          let cvMetalTex,
          let sourceTexture = CVMetalTextureGetTexture(cvMetalTex),
          let drawable = view.currentDrawable,
          let commandBuffer = commandQueue.makeCommandBuffer(),
          let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      return
    }

    let ok = VideoEditorMotionBlurEngine.encodeShutterCompute(
      encoder: encoder,
      device: device,
      sourceTexture: sourceTexture,
      outputTexture: drawable.texture,
      taps: shutterPlan.taps,
      outOrigin: .zero,
      fullSize: SIMD2<Float>(Float(drawable.texture.width), Float(drawable.texture.height)),
      flipY: false
    )
    encoder.endEncoding()

    guard ok else {
      return
    }

    commandBuffer.present(drawable)
    commandBuffer.commit()
    coordinator.lastRenderedPlan = shutterPlan

    if view.isHidden {
      view.isHidden = false
    }
  }
}
