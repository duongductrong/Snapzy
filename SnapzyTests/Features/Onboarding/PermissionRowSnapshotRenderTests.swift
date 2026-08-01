//
//  PermissionRowSnapshotRenderTests.swift
//  SnapzyTests
//
//  Renders PermissionRow states to PNGs for manual visual inspection.
//  Opt-in via SNAPZY_RENDER_PERMISSION_ROWS=1 — this writes files, it asserts nothing.
//

import SwiftUI
import XCTest
@testable import Snapzy

final class PermissionRowSnapshotRenderTests: XCTestCase {

  @MainActor
  func testRenderPermissionRowStates() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SNAPZY_RENDER_PERMISSION_ROWS"] == "1",
      "Set SNAPZY_RENDER_PERMISSION_ROWS=1 to write permission row snapshots"
    )

    let content = VStack(spacing: 12) {
      PermissionRow(
        icon: "rectangle.dashed.badge.record",
        title: "Screen Recording",
        description: "Required for screenshots and recordings",
        status: .needsAction(buttonTitle: "Grant Access"),
        isRequired: true,
        onGrant: {}
      )
      PermissionRow(
        icon: "mic.fill",
        title: "Microphone",
        description: "Optional for voice recording",
        status: .granted,
        isRequired: false,
        onGrant: {}
      )
      PermissionRow(
        icon: "bell.badge.fill",
        title: "Notifications",
        description: "Optional for OCR results and capture alerts",
        status: .blocked(label: "Turned Off", buttonTitle: "Open Settings"),
        isRequired: false,
        onGrant: {}
      )
    }
    .padding(24)
    .frame(width: 480)
    .background(Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1)))
    .environmentObject(OnboardingLocalizationController())
    .preferredColorScheme(.dark)

    let renderer = ImageRenderer(content: content)
    renderer.scale = 2

    let image = try XCTUnwrap(renderer.nsImage, "ImageRenderer produced no image")
    let tiff = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

    let url = URL(fileURLWithPath: "/tmp/snapzy-permission-rows.png")
    try png.write(to: url)
    print("Wrote permission row snapshot to \(url.path)")
  }
}
