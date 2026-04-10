//
//  ScrollingCapturePreviewRenderer.swift
//  Snapzy
//
//  Layer-backed preview surface for scrolling capture frames.
//

import AppKit
import QuartzCore
import SwiftUI

enum ScrollingCapturePreviewScaling {
  case fit
  case fillBottom
}

struct ScrollingCapturePreviewRenderer: NSViewRepresentable {
  let image: CGImage
  let scaling: ScrollingCapturePreviewScaling

  func makeNSView(context: Context) -> ScrollingCapturePreviewImageView {
    let view = ScrollingCapturePreviewImageView()
    view.update(image: image, scaling: scaling)
    return view
  }

  func updateNSView(_ nsView: ScrollingCapturePreviewImageView, context: Context) {
    nsView.update(image: image, scaling: scaling)
  }
}

final class ScrollingCapturePreviewImageView: NSView {
  private let contentLayer = CALayer()
  private var currentImageSize: CGSize = .zero
  private var currentScaling: ScrollingCapturePreviewScaling = .fit

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    wantsLayer = true
    layer = CALayer()
    layer?.masksToBounds = true
    layer?.backgroundColor = NSColor.clear.cgColor

    contentLayer.contentsGravity = .resize
    contentLayer.masksToBounds = true
    contentLayer.minificationFilter = .trilinear
    contentLayer.magnificationFilter = .trilinear
    layer?.addSublayer(contentLayer)
    updateContentsScale()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    updateContentFrame()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateContentsScale()
    updateContentFrame()
  }

  func update(image: CGImage, scaling: ScrollingCapturePreviewScaling) {
    currentImageSize = CGSize(width: image.width, height: image.height)
    currentScaling = scaling
    contentLayer.contents = image
    updateContentsScale()
    updateContentFrame()
  }

  private func updateContentFrame() {
    let bounds = self.bounds
    guard bounds.width > 0, bounds.height > 0 else {
      contentLayer.frame = .zero
      return
    }

    guard currentImageSize.width > 0, currentImageSize.height > 0 else {
      contentLayer.frame = bounds
      return
    }

    let widthScale = bounds.width / currentImageSize.width
    let heightScale = bounds.height / currentImageSize.height
    let scale: CGFloat

    switch currentScaling {
    case .fit:
      scale = min(widthScale, heightScale)
    case .fillBottom:
      scale = max(widthScale, heightScale)
    }

    let scaledSize = CGSize(
      width: currentImageSize.width * scale,
      height: currentImageSize.height * scale
    )

    let originX = (bounds.width - scaledSize.width) / 2
    let originY: CGFloat
    switch currentScaling {
    case .fit:
      originY = (bounds.height - scaledSize.height) / 2
    case .fillBottom:
      originY = 0
    }

    contentLayer.frame = CGRect(origin: CGPoint(x: originX, y: originY), size: scaledSize)
  }

  private func updateContentsScale() {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    layer?.contentsScale = scale
    contentLayer.contentsScale = scale
  }
}
