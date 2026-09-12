//
//  LiquidGlassSnapshotRenderTests.swift
//  SnapzyTests
//
//  Renders side-by-side snapshots of macOS 26+ vs macOS 13–15 Liquid Glass comparisons.
//

import AppKit
import SwiftUI
import XCTest
@testable import Snapzy

final class LiquidGlassSnapshotRenderTests: XCTestCase {

  @MainActor
  func testRenderLiquidGlassComparisonSnapshots() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["SNAPZY_RENDER_LIQUID_GLASS"] == "1"
        || ProcessInfo.processInfo.environment["TEST_RUNNER_SNAPZY_RENDER_LIQUID_GLASS"] == "1",
      "Set TEST_RUNNER_SNAPZY_RENDER_LIQUID_GLASS=1 to render Liquid Glass comparison snapshots"
    )

    // Render 1: Bright Desktop (critical for showcasing substrate contrast)
    try renderSnapshot(
      wallpaper: .brightDesktop,
      colorScheme: .light,
      filename: "liquid-glass-comparison-bright.png"
    )

    // Render 2: Dark Ambient Desktop
    try renderSnapshot(
      wallpaper: .darkAmbient,
      colorScheme: .dark,
      filename: "liquid-glass-comparison-dark.png"
    )
  }

  @MainActor
  private func renderSnapshot(wallpaper: PlaygroundWallpaper, colorScheme: ColorScheme, filename: String) throws {
    let comparisonView = ZStack {
      wallpaper.backgroundView
        .ignoresSafeArea()

      VStack(spacing: 20) {
        // Header
        VStack(spacing: 4) {
          Text("Snapzy Liquid Glass Architecture Comparison")
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(colorScheme == .dark ? .white : .black)
          Text(wallpaper == .brightDesktop ? "Nền Sáng (Bright Desktop Wallpaper) — Thử thách chống loang màu (Anti-Washout)" : "Nền Tối (Dark Ambient Wallpaper)")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
        }
        .padding(.top, 16)

        HStack(alignment: .top, spacing: 24) {
          // Column 1: macOS 26+ Native
          VStack(spacing: 14) {
            HStack {
              Text("macOS 26+ (Apple Liquid Glass)")
                .font(.system(size: 14, weight: .bold))
              Text("Official .glassEffect()")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.18))
                .foregroundColor(.blue)
                .clipShape(Capsule())
            }

            comparisonCard(isLegacy: false)
          }
          .environment(\.liquidGlassRenderMode, .native)
          .frame(width: 420)

          // Column 2: macOS 13–15 Fallback
          VStack(spacing: 14) {
            HStack {
              Text("macOS 13–15 (Fallback Composite)")
                .font(.system(size: 14, weight: .bold))
              Text("4-Layer Optical Model")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.18))
                .foregroundColor(.orange)
                .clipShape(Capsule())
            }

            comparisonCard(isLegacy: true)
          }
          .environment(\.liquidGlassRenderMode, .legacy)
          .frame(width: 420)
        }
        .padding(16)
      }
      .padding(20)
    }
    .frame(width: 960, height: 600)
    .preferredColorScheme(colorScheme)

    let renderer = ImageRenderer(content: comparisonView)
    renderer.scale = 2.0

    let image = try XCTUnwrap(renderer.nsImage, "ImageRenderer failed to produce image")
    let tiff = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

    let tmpURL = URL(fileURLWithPath: "/tmp/\(filename)")
    try png.write(to: tmpURL)
    print("Wrote snapshot to \(tmpURL.path)")

    let artifactDir = URL(fileURLWithPath: "/Users/duongductrong/.gemini/antigravity-cli/brain/0aee416b-ae63-4ce3-842b-8ca66058d930")
    if FileManager.default.fileExists(atPath: artifactDir.path) {
      let destURL = artifactDir.appendingPathComponent(filename)
      try png.write(to: destURL)
      print("Copied snapshot to artifact dir: \(destURL.path)")
    }
  }

  @MainActor
  @ViewBuilder
  private func comparisonCard(isLegacy: Bool) -> some View {
    VStack(spacing: 16) {
      // 1. Sliding Segmented Control
      LiquidGlassSegmentedControl(items: ["Capture", "Record", "OCR"], selection: .constant("Capture")) { item in
        Text(item)
      }

      // 2. Buttons
      HStack(spacing: 8) {
        LiquidGlassActionButton(
          title: "Lưu",
          icon: "square.and.arrow.down",
          trailingKey: "⌘S",
          emphasis: .primary,
          capsule: true
        ) {}

        LiquidGlassActionButton(
          title: "Sao chép",
          trailingKey: "⌘C",
          emphasis: .secondary,
          capsule: true
        ) {}

        LiquidGlassActionButton(
          title: "Xóa",
          icon: "trash",
          emphasis: .destructive,
          capsule: true
        ) {}
      }

      // 3. Card Surface
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Image(systemName: isLegacy ? "slider.horizontal.3" : "apple.logo")
            .font(.system(size: 13, weight: .semibold))
          Text(isLegacy ? "4-Layer Optical Fallback" : "Native Apple Glass")
            .font(.system(size: 13, weight: .semibold))
          Spacer()
          Text(isLegacy ? "0.5pt Hairline" : "Metal Shader")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }

        Text(isLegacy
             ? "Tầng 1 (Substrate 0.28) ngăn chặn tình trạng chữ trắng bị chìm mất khi nền sáng. Tầng 4 (Specular 0.5pt) mô phỏng viền vát bắt sáng."
             : "Khúc xạ nền màn hình thời gian thực thông qua Metal shader của macOS 26+. Tự động lấy mẫu màu sắc từ nội dung phía dưới.")
          .font(.system(size: 11.5))
          .lineSpacing(2)
          .foregroundColor(LiquidGlassTokens.inkBody)
      }
      .padding(14)
      .liquidGlass(
        shape: RoundedRectangle(cornerRadius: LiquidGlassTokens.cardRadius, style: .continuous),
        substrate: LiquidGlassTokens.baseDarkness,
        tint: 0.04,
        withRimLighting: true
      )

      // 4. Action Bar
      LiquidGlassActionBar(
        cancelTitle: "Bỏ qua",
        confirmTitle: "Tiếp tục",
        confirmKey: "↩",
        isConfirmEnabled: true,
        isBusy: false,
        onCancel: {},
        onConfirm: {}
      )
    }
    .padding(16)
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.black.opacity(0.12))
    }
  }
}
