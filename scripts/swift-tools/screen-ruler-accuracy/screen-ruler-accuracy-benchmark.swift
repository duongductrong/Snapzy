//
//  screen-ruler-accuracy-benchmark.swift
//  Snapzy
//
//  Deterministic accuracy benchmark for the Screen Ruler engine (edge spans and box snapping).
//  Run from repository root:
//  ./scripts/run-screen-ruler-accuracy-benchmark.sh [--strict] [--output report.md]
//
//  A probe passes when every measured edge/length is within 1 device pixel of the expected
//  geometry — the best an integer-pixel ruler can do on anti-aliased edges.
//

import CoreGraphics
import Darwin
import Foundation

@main
private enum ScreenRulerAccuracyBenchmark {
  static let scales: [CGFloat] = [1, 2]
  static let defaultTolerance = ScreenRulerEdgeScanner.defaultTolerance
  static let sweep = [0, 2, 3, 4, 6, 8, 10, 12, 16, 24, 32]
  /// Minimum pass rate at the default tolerance for `--strict`.
  static let strictPassRate = 0.95

  static func main() {
    let arguments = ProcessInfo.processInfo.arguments
    let strict = arguments.contains("--strict")
    let outputPath = arguments.firstIndex(of: "--output").flatMap { index in
      arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
    }

    var rasters: [(RulerScene, CGFloat, ScreenRulerRaster)] = []
    for scene in corpus() {
      for scale in scales {
        let image = RulerSceneRenderer.render(scene, scale: scale)
        rasters.append((scene, scale, ScreenRulerRaster(image: image)!))
      }
    }

    func results(at tolerance: Int) -> [RulerProbeResult] {
      rasters.flatMap { RulerSceneRenderer.evaluate($0.0, scale: $0.1, raster: $0.2, tolerance: tolerance) }
    }

    let main = results(at: defaultTolerance)
    let sweepRows = sweep.map { tolerance in (tolerance, results(at: tolerance)) }
    let report = makeReport(main: main, sweep: sweepRows)
    print(report)
    if let outputPath {
      try? report.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    if strict, passRate(main) < strictPassRate {
      exit(1)
    }
  }

  // MARK: - Corpus

  // swiftlint:disable:next function_body_length
  static func corpus() -> [RulerScene] {
    let canvas = CGSize(width: 400, height: 300)
    var scenes: [RulerScene] = []

    let crisp = CGRect(x: 40, y: 40, width: 120, height: 60)
    scenes.append(RulerScene(
      name: "crisp-rect", category: "baseline", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xFFFFFF))
        fill(c, crisp, rgb(0x3478F6))
      },
      probes: { _ in [
        .span("inside", at: CGPoint(x: 100, y: 70), axis: .both, width: 120, height: 60),
        .span("gap left", at: CGPoint(x: 20, y: 70), axis: .horizontal, width: 40, height: nil),
        .span("gap below", at: CGPoint(x: 100, y: 200), axis: .vertical, width: nil, height: 200),
        .box("snap", drag: CGRect(x: 25, y: 25, width: 145, height: 85), expected: crisp),
      ] }
    ))

    let fractional = CGRect(x: 40.25, y: 40.75, width: 120.5, height: 60.25)
    scenes.append(RulerScene(
      name: "fractional-rect", category: "anti-aliased edges", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xFFFFFF))
        fill(c, fractional, rgb(0x3478F6))
      },
      probes: { _ in [
        .span("inside", at: CGPoint(x: 100, y: 70), axis: .both, width: 120.5, height: 60.25),
        .span("gap left", at: CGPoint(x: 20, y: 70), axis: .horizontal, width: 40.25, height: nil),
        .box("snap", drag: CGRect(x: 25, y: 25, width: 145, height: 85), expected: fractional),
      ] }
    ))

    let card = CGRect(x: 50, y: 50, width: 200, height: 120)
    scenes.append(RulerScene(
      name: "rounded-card", category: "rounded corners", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xECECEC))
        fill(c, card, rgb(0xFFFFFF), radius: 10)
      },
      probes: { _ in [
        .span("inside", at: CGPoint(x: 150, y: 110), axis: .both, width: 200, height: 120),
        .box("snap", drag: CGRect(x: 35, y: 35, width: 230, height: 150), expected: card),
      ] }
    ))

    let field = CGRect(x: 60, y: 60, width: 160, height: 28)
    scenes.append(RulerScene(
      name: "hairline-field", category: "hairlines", size: canvas,
      draw: { c, scale in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xFFFFFF))
        strokeInside(c, field, rgb(0xC6C6C6), thickness: 1 / scale)
      },
      probes: { scale in [
        .span("inner size", at: CGPoint(x: 140, y: 74), axis: .both, width: 160 - 2 / scale, height: 28 - 2 / scale),
        .span("gap above", at: CGPoint(x: 140, y: 30), axis: .vertical, width: nil, height: 60),
        .box("snap", drag: CGRect(x: 45, y: 45, width: 195, height: 65), expected: field),
      ] }
    ))

    scenes.append(RulerScene(
      name: "subtle-separators", category: "low contrast", size: canvas,
      draw: { c, scale in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xECECEC))
        fill(c, CGRect(x: 0, y: 100, width: 400, height: 1 / scale), rgb(0xD9D9D9)) // Δ19
        fill(c, CGRect(x: 0, y: 200, width: 400, height: 1 / scale), rgb(0xE6E6E6)) // Δ6
      },
      probes: { scale in [
        .span("above Δ19 line", at: CGPoint(x: 200, y: 50), axis: .vertical, width: nil, height: 100),
        .span("between lines", at: CGPoint(x: 200, y: 150), axis: .vertical, width: nil, height: 100 - 1 / scale),
        .span("below Δ6 line", at: CGPoint(x: 200, y: 250), axis: .vertical, width: nil, height: 100 - 1 / scale),
      ] }
    ))

    let banner = CGRect(x: 100, y: 60, width: 200, height: 100)
    scenes.append(RulerScene(
      name: "gradient-window", category: "gradient background", size: canvas,
      draw: { c, _ in
        verticalGradient(c, CGRect(origin: .zero, size: canvas), top: 0xF6F6F6, bottom: 0xD8D8D8)
        fill(c, banner, rgb(0x3478F6))
      },
      probes: { _ in [
        .span("gap above", at: CGPoint(x: 200, y: 30), axis: .vertical, width: nil, height: 60),
        .span("gap below", at: CGPoint(x: 200, y: 230), axis: .vertical, width: nil, height: 140),
        .span("gap left", at: CGPoint(x: 50, y: 110), axis: .horizontal, width: 100, height: nil),
        .box("snap", drag: CGRect(x: 80, y: 40, width: 240, height: 140), expected: banner),
      ] }
    ))

    let shadowCard = CGRect(x: 80, y: 80, width: 160, height: 100)
    scenes.append(RulerScene(
      name: "shadow-card", category: "drop shadow", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xECECEC))
        c.saveGState()
        // y-down space: a positive offset height moves the shadow down on screen... in the
        // flipped CTM CoreGraphics applies the offset in base space, so use -4 to go down.
        c.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: rgb(0x000000, alpha: 0.25))
        fill(c, shadowCard, rgb(0xFFFFFF), radius: 8)
        c.restoreGState()
      },
      probes: { _ in [
        .span("inside", at: CGPoint(x: 160, y: 130), axis: .both, width: 160, height: 100),
        .span("gap left", at: CGPoint(x: 30, y: 130), axis: .horizontal, width: 80, height: nil),
        .span("gap below", at: CGPoint(x: 160, y: 250), axis: .vertical, width: nil, height: 120),
        .box("snap", drag: CGRect(x: 50, y: 50, width: 230, height: 170), expected: shadowCard),
      ] }
    ))

    let row = CGRect(x: 100, y: 100, width: 150, height: 80)
    for amplitude in [2, 5] {
      scenes.append(RulerScene(
        name: "material-noise-±\(amplitude)", category: "material noise", size: canvas, noiseAmplitude: amplitude,
        draw: { c, _ in
          fill(c, CGRect(origin: .zero, size: canvas), rgb(0xECECEC))
          fill(c, row, rgb(0xFFFFFF))
        },
        probes: { _ in [
          .span("inside", at: CGPoint(x: 175, y: 140), axis: .both, width: 150, height: 80),
          .span("gap left", at: CGPoint(x: 50, y: 140), axis: .horizontal, width: 100, height: nil),
          .box("snap", drag: CGRect(x: 80, y: 80, width: 200, height: 120), expected: row),
        ] }
      ))
    }

    let text = "Measure Screen 120"
    let baseline = CGPoint(x: 60, y: 150)
    let ink = textInkBounds(text, at: baseline, size: 15)
    scenes.append(RulerScene(
      name: "text-label", category: "text", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xFFFFFF))
        drawText(c, text, at: baseline, size: 15, color: rgb(0x1D1D1F))
      },
      probes: { _ in [
        .box("snap to ink", drag: CGRect(x: 40, y: 120, width: 280, height: 50), expected: ink),
        .span("gap left of text", at: CGPoint(x: 30, y: ink.midY), axis: .horizontal, width: ink.minX, height: nil),
      ] }
    ))

    let left = CGRect(x: 40, y: 100, width: 100, height: 32)
    let right = CGRect(x: 148, y: 100, width: 100, height: 32)
    scenes.append(RulerScene(
      name: "button-gap", category: "spacing", size: canvas,
      draw: { c, scale in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xECECEC))
        for button in [left, right] {
          fill(c, button, rgb(0xFFFFFF), radius: 6)
          strokeInside(c, button, rgb(0xD0D0D0), thickness: 1 / scale, radius: 6)
        }
      },
      probes: { scale in [
        .span("gap between", at: CGPoint(x: 144, y: 116), axis: .horizontal, width: 8, height: nil),
        .span("inner height", at: CGPoint(x: 90, y: 116), axis: .vertical, width: nil, height: 32 - 2 / scale),
        .box("snap both", drag: CGRect(x: 30, y: 90, width: 230, height: 55), expected: left.union(right)),
      ] }
    ))

    let panel = CGRect(x: 60, y: 60, width: 200, height: 120)
    let chip = CGRect(x: 100, y: 100, width: 80, height: 30)
    scenes.append(RulerScene(
      name: "dark-mode-panel", category: "low contrast", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0x1E1E1E))
        fill(c, panel, rgb(0x2A2A2A)) // Δ12 vs background
        fill(c, chip, rgb(0x262626)) // Δ4 vs panel
      },
      probes: { _ in [
        .span("panel inside", at: CGPoint(x: 80, y: 150), axis: .both, width: 200, height: 120),
        .span("chip Δ4 inside", at: CGPoint(x: 140, y: 115), axis: .both, width: 80, height: 30),
        .box("snap panel", drag: CGRect(x: 40, y: 40, width: 240, height: 160), expected: panel),
      ] }
    ))

    let selection = CGRect(x: 20, y: 100, width: 200, height: 28)
    scenes.append(RulerScene(
      name: "sidebar-selection", category: "rounded corners", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xF2F2F2))
        fill(c, selection, rgb(0x0A84FF), radius: 6)
        drawText(c, "Downloads", at: CGPoint(x: 44, y: 118), size: 13, color: rgb(0xFFFFFF))
      },
      probes: { _ in [
        .span("row height", at: CGPoint(x: 210, y: 114), axis: .vertical, width: nil, height: 28),
        .box("snap row", drag: CGRect(x: 10, y: 90, width: 230, height: 50), expected: selection),
      ] }
    ))

    scenes += holdoutCorpus()
    return scenes
  }

  /// Written before the 261107 engine rewrite was tuned and never used to tune it: the
  /// honest estimate of accuracy on UI the engine has not seen.
  // swiftlint:disable:next function_body_length
  static func holdoutCorpus() -> [RulerScene] {
    let canvas = CGSize(width: 400, height: 300)
    var scenes: [RulerScene] = []

    let darkCard = CGRect(x: 90, y: 70, width: 180, height: 110)
    scenes.append(RulerScene(
      name: "dark-shadow-card", category: "holdout: shadow", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0x1E1E1E))
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0x000000, alpha: 0.5))
        fill(c, darkCard, rgb(0x2C2C2C), radius: 10)
        c.restoreGState()
      },
      probes: { _ in [
        .span("inside", at: CGPoint(x: 180, y: 125), axis: .both, width: 180, height: 110),
        .span("gap left", at: CGPoint(x: 40, y: 125), axis: .horizontal, width: 90, height: nil),
        .span("gap below", at: CGPoint(x: 180, y: 250), axis: .vertical, width: nil, height: 120),
        .box("snap", drag: CGRect(x: 60, y: 40, width: 240, height: 180), expected: darkCard),
      ] }
    ))

    let redRect = CGRect(x: 70, y: 90, width: 130, height: 70)
    scenes.append(RulerScene(
      name: "colored-edge", category: "holdout: color", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0x34C759))
        fill(c, redRect, rgb(0xFF3B30))
      },
      probes: { _ in [
        .span("inside", at: CGPoint(x: 120, y: 120), axis: .both, width: 130, height: 70),
        .span("gap right", at: CGPoint(x: 300, y: 120), axis: .horizontal, width: 200, height: nil),
        .box("snap", drag: CGRect(x: 50, y: 70, width: 180, height: 110), expected: redRect),
      ] }
    ))

    scenes.append(RulerScene(
      name: "close-hairlines", category: "holdout: hairlines", size: canvas,
      draw: { c, scale in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xFFFFFF))
        fill(c, CGRect(x: 0, y: 100, width: 400, height: 1 / scale), rgb(0xC0C0C0))
        fill(c, CGRect(x: 0, y: 102, width: 400, height: 1 / scale), rgb(0xC0C0C0))
      },
      probes: { scale in [
        .span("between lines", at: CGPoint(x: 200, y: 101.5), axis: .vertical, width: nil, height: 2 - 1 / scale),
        .span("above", at: CGPoint(x: 200, y: 50), axis: .vertical, width: nil, height: 100),
      ] }
    ))

    let grayRect = CGRect(x: 120, y: 80, width: 140, height: 90)
    scenes.append(RulerScene(
      name: "noisy-low-contrast", category: "holdout: noise", size: canvas, noiseAmplitude: 3,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0x808080))
        fill(c, grayRect, rgb(0x8C8C8C)) // Δ12 under ±3 noise
      },
      probes: { _ in [
        .span("inside", at: CGPoint(x: 190, y: 125), axis: .both, width: 140, height: 90),
        .span("gap left", at: CGPoint(x: 60, y: 125), axis: .horizontal, width: 120, height: nil),
        .box("snap", drag: CGRect(x: 100, y: 60, width: 180, height: 130), expected: grayRect),
      ] }
    ))

    let smallText = "Preferences · General"
    let smallBaseline = CGPoint(x: 50, y: 200)
    let smallInk = textInkBounds(smallText, at: smallBaseline, size: 11)
    scenes.append(RulerScene(
      name: "small-text", category: "holdout: text", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xF5F5F5))
        drawText(c, smallText, at: smallBaseline, size: 11, color: rgb(0x3C3C43))
      },
      probes: { _ in [
        .box("snap to ink", drag: CGRect(x: 30, y: 180, width: 220, height: 35), expected: smallInk),
      ] }
    ))

    let gradientButton = CGRect(x: 120, y: 120, width: 120, height: 28)
    scenes.append(RulerScene(
      name: "gradient-button", category: "holdout: gradient", size: canvas,
      draw: { c, scale in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xECECEC))
        c.saveGState()
        c.addPath(CGPath(roundedRect: gradientButton, cornerWidth: 6, cornerHeight: 6, transform: nil))
        c.clip()
        verticalGradient(c, gradientButton, top: 0xFFFFFF, bottom: 0xF0F0F0)
        c.restoreGState()
        strokeInside(c, gradientButton, rgb(0xC8C8C8), thickness: 1 / scale, radius: 6)
      },
      probes: { scale in [
        .span("inner height", at: CGPoint(x: 180, y: 134), axis: .vertical, width: nil, height: 28 - 2 / scale),
        .box("snap", drag: CGRect(x: 100, y: 100, width: 160, height: 70), expected: gradientButton),
      ] }
    ))

    let wallpaperCard = CGRect(x: 110, y: 80, width: 180, height: 120)
    scenes.append(RulerScene(
      name: "wallpaper-card", category: "holdout: shadow", size: canvas,
      draw: { c, _ in
        let gradient = CGGradient(
          colorsSpace: RulerSceneRenderer.sRGB,
          colors: [rgb(0x3A6EA5), rgb(0xA55AA5)] as CFArray,
          locations: [0, 1]
        )!
        c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 400, y: 300), options: [])
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: rgb(0x000000, alpha: 0.35))
        fill(c, wallpaperCard, rgb(0xFFFFFF), radius: 12)
        c.restoreGState()
      },
      probes: { _ in [
        .span("gap left", at: CGPoint(x: 50, y: 140), axis: .horizontal, width: 110, height: nil),
        .box("snap", drag: CGRect(x: 80, y: 50, width: 240, height: 190), expected: wallpaperCard),
      ] }
    ))

    let tint = CGRect(x: 80, y: 80, width: 200, height: 100)
    scenes.append(RulerScene(
      name: "translucent-tint", category: "holdout: low contrast", size: canvas,
      draw: { c, _ in
        fill(c, CGRect(origin: .zero, size: canvas), rgb(0xFFFFFF))
        fill(c, tint, rgb(0x000000, alpha: 0.04), radius: 8) // ≈Δ10
      },
      probes: { _ in [
        .span("inside", at: CGPoint(x: 180, y: 130), axis: .both, width: 200, height: 100),
        .box("snap", drag: CGRect(x: 60, y: 60, width: 240, height: 140), expected: tint),
      ] }
    ))

    return scenes
  }

  // MARK: - Report

  static func passRate(_ results: [RulerProbeResult]) -> Double {
    results.isEmpty ? 0 : Double(results.filter(\.passed).count) / Double(results.count)
  }

  static func percent(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
  }

  static func number(_ value: Double) -> String {
    String(format: "%.2f", value)
  }

  static func summary(_ results: [RulerProbeResult]) -> String {
    let errors = results.map(\.errorPixels)
    let mean = errors.isEmpty ? 0 : errors.reduce(0, +) / Double(errors.count)
    let exact = results.filter { $0.errorPixels < 0.5 }.count
    return "\(results.filter(\.passed).count)/\(results.count) | \(percent(passRate(results))) | \(percent(results.isEmpty ? 0 : Double(exact) / Double(results.count))) | \(number(mean)) | \(number(errors.max() ?? 0))"
  }

  static func makeReport(main: [RulerProbeResult], sweep: [(Int, [RulerProbeResult])]) -> String {
    var lines: [String] = []
    lines.append("# Screen Ruler Accuracy Benchmark")
    lines.append("")
    lines.append("Tolerance \(defaultTolerance) (default), scales \(scales.map { "\(Int($0))×" }.joined(separator: ", ")). Pass = every edge within 1 device px.")
    lines.append("")
    lines.append("## Overall")
    lines.append("")
    lines.append("| Set | Passed | Pass rate | Exact (<0.5 px) | Mean err px | Max err px |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
    lines.append("| All probes | \(summary(main)) |")
    lines.append("| Spans (hover) | \(summary(main.filter(\.isSpan))) |")
    lines.append("| Boxes (drag snap) | \(summary(main.filter { !$0.isSpan })) |")
    lines.append("| Tuning set | \(summary(main.filter { !$0.category.hasPrefix("holdout") })) |")
    lines.append("| Held-out set | \(summary(main.filter { $0.category.hasPrefix("holdout") })) |")
    for scale in scales {
      lines.append("| \(Int(scale))× only | \(summary(main.filter { $0.scale == scale })) |")
    }
    lines.append("")
    lines.append("## By category")
    lines.append("")
    lines.append("| Category | Passed | Pass rate | Exact (<0.5 px) | Mean err px | Max err px |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: |")
    var categories: [String] = []
    for result in main where !categories.contains(result.category) {
      categories.append(result.category)
    }
    for category in categories {
      lines.append("| \(category) | \(summary(main.filter { $0.category == category })) |")
    }
    lines.append("")
    lines.append("## Tolerance sweep")
    lines.append("")
    lines.append("| Tolerance | Passed | Pass rate | Exact (<0.5 px) | Mean err px | Max err px |")
    lines.append("| ---: | ---: | ---: | ---: | ---: | ---: |")
    for (tolerance, results) in sweep {
      let marker = tolerance == defaultTolerance ? " (default)" : ""
      lines.append("| \(tolerance)\(marker) | \(summary(results)) |")
    }
    lines.append("")
    lines.append("## Probes (default tolerance)")
    lines.append("")
    lines.append("| Scene | Scale | Probe | Expected px | Measured px | Error px | Status |")
    lines.append("| --- | ---: | --- | ---: | ---: | ---: | --- |")
    for result in main {
      lines.append("| \(result.scene) | \(Int(result.scale))× | \(result.probe) | \(result.expected) | \(result.measured) | \(number(result.errorPixels)) | \(result.passed ? "pass" : "**fail**") |")
    }
    return lines.joined(separator: "\n")
  }
}
