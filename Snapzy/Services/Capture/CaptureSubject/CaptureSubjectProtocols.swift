//
//  CaptureSubjectProtocols.swift
//  Snapzy
//
//  Protocol seams that let CaptureSubjectController be unit-tested without a
//  real screenshot or Vision cutout.
//

import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol CaptureSubjectCapturePerforming: AnyObject {
  func captureSubject(preview: CaptureSubjectSnappedPreview) async
}

@MainActor
protocol CaptureSubjectOverlayWindowProviding: AnyObject {
  var displayID: CGDirectDisplayID? { get }
  var frame: CGRect { get }
  var currentPreviewRect: CGRect? { get }
  var currentDragRect: CGRect? { get }
  var isCameraHovered: Bool { get }
  var eventDelegate: CaptureSubjectOverlayWindowDelegate? { get set }
  func setFrame(_ frameRect: NSRect, display flag: Bool)
  func orderFrontRegardless()
  func orderOut(_ sender: Any?)
  func close()
  func makeKey()
  func makeFirstResponder(_ responder: NSResponder?) -> Bool
  func updateBounds(_ screenFrame: CGRect)
  func updatePreview(_ preview: CaptureSubjectSnappedPreview?)
  func updateDragRect(_ rect: CGRect?)
  func setPointer(_ point: CGPoint?)
}

@MainActor
protocol CaptureSubjectOverlayWindowDelegate: AnyObject {
  func captureSubjectOverlayWindow(_ window: CaptureSubjectOverlayWindowProviding, mouseMovedAt point: CGPoint)
  func captureSubjectOverlayWindow(_ window: CaptureSubjectOverlayWindowProviding, mouseDownAt point: CGPoint)
  func captureSubjectOverlayWindow(_ window: CaptureSubjectOverlayWindowProviding, mouseDraggedAt point: CGPoint)
  func captureSubjectOverlayWindow(_ window: CaptureSubjectOverlayWindowProviding, mouseUpAt point: CGPoint)
  func captureSubjectOverlayWindowDidCancel(_ window: CaptureSubjectOverlayWindowProviding)
  func captureSubjectOverlayWindowDidRequestCapture(_ window: CaptureSubjectOverlayWindowProviding)
}
