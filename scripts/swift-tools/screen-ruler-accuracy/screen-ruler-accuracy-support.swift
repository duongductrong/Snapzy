//
//  screen-ruler-accuracy-support.swift
//  Snapzy
//
//  Scene rendering and probe evaluation for the Screen Ruler accuracy benchmark. Scenes are
//  drawn with CoreGraphics (anti-aliasing on, sRGB) at a given backing scale, so their geometry
//  is known exactly while their pixels look like real macOS UI: fractional edges, hairlines,
//  rounded corners, shadows, gradients, material noise and text.
//

import CoreGraphics
import CoreText
import Foundation

/// A measurement the user would make, with the answer a designer expects. Points, top-left origin.
enum RulerProbe {
  /// Hover at `at`; `width` / `height` are the expected gap or inner size (nil = not checked).
  case span(String, at: CGPoint, axis: ScreenRulerAxis, width: CGFloat?, height: CGFloat?)
  /// Drag `drag`; the box should snap to `expected`.
  case box(String, drag: CGRect, expected: CGRect)

  var label: String {
    switch self {
    case .span(let label, _, _, _, _), .box(let label, _, _): return label
    }
  }

  var isSpan: Bool {
    if case .span = self { return true }
    return false
  }
}

struct RulerScene {
  let name: String
  /// Which real-world condition the scene stands for.
  let category: String
  let size: CGSize
  /// Per-pixel noise amplitude (0–255) added after drawing, like vibrancy/material dithering.
  var noiseAmplitude: Int = 0
  /// Draws in points with a top-left origin. The context is already scaled; the scale is
  /// passed for one-device-pixel hairlines.
  let draw: (CGContext, CGFloat) -> Void
  /// Probes for a scale (hairline-relative answers depend on it).
  let probes: (CGFloat) -> [RulerProbe]
}

struct RulerProbeResult {
  let scene: String
  let category: String
  let scale: CGFloat
  let probe: String
  let isSpan: Bool
  let expected: String
  let measured: String
  /// Largest edge/length error in device pixels.
  let errorPixels: Double
  var passed: Bool { errorPixels <= 1.0 + 1e-9 }
}

enum RulerSceneRenderer {
  static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  static func render(_ scene: RulerScene, scale: CGFloat) -> CGImage {
    let width = Int((scene.size.width * scale).rounded())
    let height = Int((scene.size.height * scale).rounded())
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: sRGB,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    )!
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.saveGState()
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)
    scene.draw(context, scale)
    context.restoreGState()

    if scene.noiseAmplitude > 0, let data = context.data {
      let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
      var state: UInt64 = 0x9E37_79B9_7F4A_7C15
      for index in 0..<(width * height) {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let span = UInt64(scene.noiseAmplitude * 2 + 1)
        let offset = Int((state >> 33) % span) - scene.noiseAmplitude
        for channel in 0..<3 {
          let i = index * 4 + channel
          bytes[i] = UInt8(clamping: Int(bytes[i]) + offset)
        }
      }
    }
    return context.makeImage()!
  }

  static func evaluate(
    _ scene: RulerScene,
    scale: CGFloat,
    raster: ScreenRulerRaster,
    tolerance: Int
  ) -> [RulerProbeResult] {
    scene.probes(scale).map { probe in
      switch probe {
      case .span(let label, let point, let axis, let width, let height):
        let origin = ColorPickerPixel(x: Int(floor(point.x * scale)), y: Int(floor(point.y * scale)))
        let span = ScreenRulerEdgeScanner.span(in: raster, from: origin, axis: axis, tolerance: tolerance)
        var errors: [Double] = []
        var expected: [String] = []
        var measured: [String] = []
        if let width {
          let got = Double(span.width ?? 0)
          errors.append(abs(got - Double(width * scale)))
          expected.append(format(width * scale))
          measured.append(String(Int(got)))
        }
        if let height {
          let got = Double(span.height ?? 0)
          errors.append(abs(got - Double(height * scale)))
          expected.append(format(height * scale))
          measured.append(String(Int(got)))
        }
        return RulerProbeResult(
          scene: scene.name,
          category: scene.category,
          scale: scale,
          probe: label,
          isSpan: true,
          expected: expected.joined(separator: " × "),
          measured: measured.joined(separator: " × "),
          errorPixels: errors.max() ?? 0
        )
      case .box(let label, let drag, let expectedRect):
        let a = ColorPickerPixel(x: Int(floor(drag.minX * scale)), y: Int(floor(drag.minY * scale)))
        let b = ColorPickerPixel(x: Int(floor(drag.maxX * scale)), y: Int(floor(drag.maxY * scale)))
        let snapped = ScreenRulerEdgeScanner.snap(ScreenRulerPixelRect(corner: a, b), in: raster, tolerance: tolerance)
        // Continuous edges of the inclusive pixel rect.
        let got = [Double(snapped.minX), Double(snapped.minY), Double(snapped.maxX + 1), Double(snapped.maxY + 1)]
        let want = [expectedRect.minX, expectedRect.minY, expectedRect.maxX, expectedRect.maxY].map { Double($0 * scale) }
        let error = zip(got, want).map { abs($0 - $1) }.max() ?? 0
        return RulerProbeResult(
          scene: scene.name,
          category: scene.category,
          scale: scale,
          probe: label,
          isSpan: false,
          expected: "\(format(expectedRect.width * scale)) × \(format(expectedRect.height * scale))",
          measured: "\(snapped.width) × \(snapped.height)",
          errorPixels: error
        )
      }
    }
  }

  static func format(_ value: CGFloat) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }
}

// MARK: - Drawing helpers

func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha
  )
}

func fill(_ context: CGContext, _ rect: CGRect, _ color: CGColor, radius: CGFloat = 0) {
  context.setFillColor(color)
  if radius > 0 {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
  } else {
    context.fill(rect)
  }
}

/// A border `thickness` points wide drawn inside `rect` (the way AppKit insets hairlines).
func strokeInside(_ context: CGContext, _ rect: CGRect, _ color: CGColor, thickness: CGFloat, radius: CGFloat = 0) {
  let inset = rect.insetBy(dx: thickness / 2, dy: thickness / 2)
  context.setStrokeColor(color)
  context.setLineWidth(thickness)
  if radius > 0 {
    context.addPath(CGPath(roundedRect: inset, cornerWidth: radius - thickness / 2, cornerHeight: radius - thickness / 2, transform: nil))
    context.strokePath()
  } else {
    context.stroke(inset)
  }
}

func verticalGradient(_ context: CGContext, _ rect: CGRect, top: UInt32, bottom: UInt32) {
  let gradient = CGGradient(colorsSpace: RulerSceneRenderer.sRGB, colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
  context.saveGState()
  context.clip(to: rect)
  context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
  context.restoreGState()
}

/// Draws `text` with its baseline at `origin` (top-left space) and returns its ink bounds.
@discardableResult
func drawText(_ context: CGContext, _ text: String, at origin: CGPoint, size: CGFloat, color: CGColor) -> CGRect {
  let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
  let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
  let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes)!)
  context.saveGState()
  context.translateBy(x: origin.x, y: origin.y)
  context.scaleBy(x: 1, y: -1)
  context.textPosition = .zero
  let ink = CTLineGetImageBounds(line, context)
  CTLineDraw(line, context)
  context.restoreGState()
  return CGRect(x: origin.x + ink.minX, y: origin.y - ink.maxY, width: ink.width, height: ink.height)
}

/// Ink bounds of `text` as `drawText` would place it, without drawing.
func textInkBounds(_ text: String, at origin: CGPoint, size: CGFloat) -> CGRect {
  let context = CGContext(
    data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
    space: RulerSceneRenderer.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
  let attributes = [kCTFontAttributeName: font] as CFDictionary
  let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes)!)
  let ink = CTLineGetImageBounds(line, context)
  return CGRect(x: origin.x + ink.minX, y: origin.y - ink.maxY, width: ink.width, height: ink.height)
}
