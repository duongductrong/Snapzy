//
//  QuickAccessPinWindowState.swift
//  Snapzy
//
//  Observable state for independent pinned screenshot windows.
//

import AppKit
import Combine
import Foundation

@MainActor
final class QuickAccessPinWindowState: ObservableObject {
  let id: UUID

  @Published private(set) var url: URL
  @Published private(set) var image: NSImage
  @Published private(set) var thumbnail: NSImage
  @Published var isLocked = false
  @Published var isMouseInside = false
  @Published private(set) var zoomFactor: CGFloat = 1
  @Published private(set) var panOffset: CGPoint = .zero
  @Published private(set) var zoomMode: QuickAccessPinZoomMode

  private(set) var baseSize: CGSize
  var onWindowResize: ((CGSize, CGPoint) -> Void)?

  static let minimumZoomFactor: CGFloat = 0.4
  static let maximumZoomFactor: CGFloat = 8

  static func windowFollowsImageDisplaySize(baseSize: CGSize, zoomFactor: CGFloat) -> CGSize {
    let factor = min(max(zoomFactor, minimumZoomFactor), maximumZoomFactor)
    let minimumSize = QuickAccessPinWindowSizing.minimumInteractiveSize
    return CGSize(
      width: max(baseSize.width * factor, minimumSize.width),
      height: max(baseSize.height * factor, minimumSize.height)
    )
  }

  init(id: UUID, url: URL, image: NSImage, thumbnail: NSImage, baseSize: CGSize, zoomMode: QuickAccessPinZoomMode = .defaultMode) {
    self.id = id
    self.url = url
    self.image = image
    self.thumbnail = thumbnail
    self.baseSize = baseSize
    self.zoomMode = zoomMode
  }

  var displaySize: CGSize {
    zoomMode == .windowFollowsImage
      ? Self.windowFollowsImageDisplaySize(baseSize: baseSize, zoomFactor: zoomFactor)
      : baseSize
  }

  var imageDisplaySize: CGSize {
    if zoomMode == .windowFollowsImage {
      let fittedSize = QuickAccessPinImageGeometry.fittedContentSize(
        imageSize: image.size,
        viewportSize: baseSize
      )
      return CGSize(width: fittedSize.width * zoomFactor, height: fittedSize.height * zoomFactor)
    }
    return QuickAccessPinImageGeometry.fixedViewportContentSize(
      imageSize: image.size,
      viewportSize: baseSize,
      zoomFactor: zoomFactor
    )
  }

  var zoomPercent: Int {
    Int((zoomFactor * 100).rounded())
  }

  var zoomMenuPercents: [Int] {
    var percents = [40, 50, 75, 100, 125, 150, 200, 400, 800].filter { percent in
      let factor = CGFloat(percent) / 100
      return factor >= Self.minimumZoomFactor - 0.001 && factor <= Self.maximumZoomFactor + 0.001
    }
    if !percents.contains(zoomPercent) {
      percents.append(zoomPercent)
      percents.sort()
    }
    return percents
  }

  func setZoomPercent(_ percent: Int) {
    updateZoomFactor(CGFloat(percent) / 100)
  }

  func resetZoom() {
    zoomFactor = 1
    panOffset = .zero
    if zoomMode == .windowFollowsImage { onWindowResize?(baseSize, CGPoint(x: 0.5, y: 0.5)) }
  }

  @discardableResult
  func setZoomMode(_ mode: QuickAccessPinZoomMode, baseSize: CGSize) -> Bool {
    guard zoomMode != mode else { return false }
    zoomMode = mode
    self.baseSize = baseSize
    zoomFactor = 1
    panOffset = .zero
    return true
  }

  func update(url: URL, image: NSImage, thumbnail: NSImage, baseSize: CGSize) -> CGSize {
    self.url = url
    self.image = image
    self.thumbnail = thumbnail
    return updateSizing(baseSize: baseSize)
  }

  func updateSizing(baseSize: CGSize) -> CGSize {
    self.baseSize = baseSize
    zoomFactor = clampedZoomFactor(zoomFactor)
    panOffset = clampedPanOffset(panOffset)
    return displaySize
  }

  func updateZoomFactor(_ factor: CGFloat) {
    guard factor.isFinite else { return }
    zoomFactor = clampedZoomFactor(factor)
    panOffset = clampedPanOffset(panOffset)
    if zoomMode == .windowFollowsImage {
      onWindowResize?(displaySize, CGPoint(x: 0.5, y: 0.5))
    }
  }

  func updateViewport(magnification: CGFloat, panOffset: CGPoint) {
    guard magnification.isFinite, panOffset.x.isFinite, panOffset.y.isFinite else { return }
    let clampedMagnification = clampedZoomFactor(magnification)
    if abs(zoomFactor - clampedMagnification) > 0.000_1 {
      zoomFactor = clampedMagnification
    }
    let newPanOffset = clampedPanOffset(panOffset)
    if abs(self.panOffset.x - newPanOffset.x) > 0.000_1
      || abs(self.panOffset.y - newPanOffset.y) > 0.000_1 {
      self.panOffset = newPanOffset
    }
  }

  private func clampedPanOffset(_ offset: CGPoint) -> CGPoint {
    guard zoomMode == .fixedViewport else { return .zero }
    return QuickAccessPinImageGeometry.clampedPanOffset(
      offset,
      viewportSize: baseSize,
      contentSize: imageDisplaySize
    )
  }

  func clampedZoomFactor(_ factor: CGFloat) -> CGFloat {
    min(max(factor, Self.minimumZoomFactor), Self.maximumZoomFactor)
  }
}
