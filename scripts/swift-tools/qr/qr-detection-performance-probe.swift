//
//  qr-detection-performance-probe.swift
//  Snapzy
//
//  Local Vision QR detector timing probe for OCR capture latency checks.
//
//  Run from repository root with:
//  ./scripts/run-qr-detection-performance-probe.sh
//

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import Foundation
import Vision

private struct ProbeSummary {
  let name: String
  let samples: [Double]
  let failures: Int
  let firstErrorDescription: String?

  var sortedSamples: [Double] {
    samples.sorted()
  }

  var average: Double {
    guard !samples.isEmpty else { return 0 }
    return samples.reduce(0, +) / Double(samples.count)
  }

  func percentile(_ value: Double) -> Double {
    let sorted = sortedSamples
    guard !sorted.isEmpty else { return 0 }
    let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * value))
    return sorted[index]
  }

  func printReport() {
    if samples.isEmpty {
      let errorSuffix = firstErrorDescription.map { ", firstError=\($0)" } ?? ""
      print("\(name): no successful samples, failures=\(failures)\(errorSuffix)")
      return
    }

    print(String(
      format: "%@: n=%d failures=%d avg=%.2fms median=%.2fms p95=%.2fms min=%.2fms max=%.2fms",
      name,
      samples.count,
      failures,
      average,
      percentile(0.5),
      percentile(0.95),
      sortedSamples.first ?? 0,
      sortedSamples.last ?? 0
    ))
  }
}

private enum ProbeComputeMode {
  case systemDefault
  case cpu

  var label: String {
    switch self {
    case .systemDefault: return "default"
    case .cpu: return "cpu"
    }
  }
}

@main
struct QRDetectionPerformanceProbe {
  static func main() {
    guard let blankImage = makeCanvas() else {
      print("Unable to create blank probe image")
      return
    }

    runProbe(name: "QR blank 1440x900", image: blankImage, computeMode: .systemDefault).printReport()
    runProbe(name: "QR blank 1440x900", image: blankImage, computeMode: .cpu).printReport()

    if let qrImage = makeCanvas(withQRCodePayload: "https://snapzy.app/security-check") {
      runProbe(name: "QR payload 1440x900", image: qrImage, computeMode: .systemDefault).printReport()
      runProbe(name: "QR payload 1440x900", image: qrImage, computeMode: .cpu).printReport()
    } else {
      print("QR payload 1440x900: unable to create QR probe image")
    }
  }

  private static func runProbe(
    name: String,
    image: CGImage,
    computeMode: ProbeComputeMode,
    iterations: Int = 31
  ) -> ProbeSummary {
    var samples: [Double] = []
    var failures = 0
    var firstErrorDescription: String?

    for index in 0..<iterations {
      let request = VNDetectBarcodesRequest()
      request.symbologies = [.qr]
      if computeMode == .cpu {
        configureCPUComputeDevice(for: request)
      }

      let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
      let start = CFAbsoluteTimeGetCurrent()

      do {
        try handler.perform([request])
        let milliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if index > 0 {
          samples.append(milliseconds)
        }
      } catch {
        failures += 1
        firstErrorDescription = firstErrorDescription ?? error.localizedDescription
      }
    }

    return ProbeSummary(
      name: "\(name) [\(computeMode.label)]",
      samples: samples,
      failures: failures,
      firstErrorDescription: firstErrorDescription
    )
  }

  private static func configureCPUComputeDevice(for request: VNRequest) {
    guard #available(macOS 14.0, *) else { return }

    let cpuDevice = MLComputeDevice.allComputeDevices.first { device in
      if case .cpu = device {
        return true
      }
      return false
    }

    request.setComputeDevice(cpuDevice, for: .main)
  }

  private static func makeCanvas(withQRCodePayload payload: String? = nil) -> CGImage? {
    let width = 1440
    let height = 900
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    if let payload, let qrCode = makeQRCode(payload) {
      let side = min(width, height) / 3
      let rect = CGRect(
        x: (width - side) / 2,
        y: (height - side) / 2,
        width: side,
        height: side
      )
      context.interpolationQuality = .none
      context.draw(qrCode, in: rect)
    }

    return context.makeImage()
  }

  private static func makeQRCode(_ payload: String) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(payload.utf8)
    filter.correctionLevel = "M"

    guard let outputImage = filter.outputImage else { return nil }

    let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    let context = CIContext(options: [.cacheIntermediates: false])
    return context.createCGImage(scaledImage, from: scaledImage.extent)
  }
}
