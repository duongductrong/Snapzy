//
//  CaptureSubjectPreviewCapture.swift
//  Snapzy
//
//  One-shot crop of the live display used as the locked Capture Subject preview.
//  The controller briefly hides its shareable overlay panels around this capture.
//

import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol CaptureSubjectPreviewCapturing: AnyObject {
  func capturePreview(of rect: CGRect) -> CaptureSubjectPreviewFrame?
}

struct CaptureSubjectPreviewFrame {
  let rect: CGRect
  let image: CGImage
  let displayID: CGDirectDisplayID
}

@MainActor
final class CaptureSubjectPreviewCapturer: CaptureSubjectPreviewCapturing {
  func capturePreview(of rect: CGRect) -> CaptureSubjectPreviewFrame? {
    let integral = rect.integral
    guard integral.width >= 1, integral.height >= 1 else { return nil }
    guard let screen = Self.primaryScreen(intersecting: integral),
          let displayID = screen.displayID else { return nil }
    guard let image = CGDisplayCreateImage(displayID) else { return nil }

    let snapshot = FrozenDisplaySnapshot(
      displayID: displayID,
      screenFrame: screen.frame,
      scaleFactor: screen.backingScaleFactor,
      colorSpaceName: image.colorSpace?.name,
      image: image
    )
    let selection = AreaSelectionResult(
      target: .rect(integral),
      displayID: displayID,
      mode: .screenshot
    )

    do {
      let cropped = try FrozenAreaCaptureSession.cropImage(
        snapshots: [displayID: snapshot],
        for: selection
      )
      return CaptureSubjectPreviewFrame(
        rect: cropped.screenRect,
        image: cropped.image,
        displayID: displayID
      )
    } catch {
      DiagnosticLogger.shared.log(
        .warning,
        .capture,
        "Capture subject preview crop failed",
        context: ["error": error.localizedDescription]
      )
      return nil
    }
  }

  private static func primaryScreen(intersecting rect: CGRect) -> NSScreen? {
    NSScreen.screens
      .map { (screen: $0, area: intersectionArea($0.frame, rect)) }
      .filter { $0.area > 0 }
      .max { $0.area < $1.area }?
      .screen
      ?? NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
  }
}

private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
  let intersection = a.intersection(b)
  guard !intersection.isNull, !intersection.isInfinite else { return 0 }
  return max(0, intersection.width) * max(0, intersection.height)
}
