//
//  PPOCRImageTensor.swift
//  Snapzy
//
//  CGImage → resized, normalized NCHW float tensors for PP-OCR models.
//

import CoreGraphics
import Foundation

enum PPOCRImageTensor {
  /// Per-channel normalization applied after the 1/255 scale, in tensor
  /// channel order (BGR — both PP-OCR det and rec export with
  /// `DecodeImage: img_mode: BGR` in their inference.yml).
  struct ChannelNormalize {
    let mean: [Float]
    let std: [Float]

    static let detection = ChannelNormalize(mean: [0.485, 0.456, 0.406], std: [0.229, 0.224, 0.225])
    static let recognition = ChannelNormalize(mean: [0.5, 0.5, 0.5], std: [0.5, 0.5, 0.5])
  }

  /// Renders `image` into an sRGB RGBA8888 buffer at `size`, then converts to
  /// NCHW float32 in BGR order applying `normalize` per channel.
  static func makeNCHW(
    from image: CGImage,
    size: CGSize,
    normalize: ChannelNormalize
  ) -> [Float]? {
    let width = Int(size.width)
    let height = Int(size.height)
    guard let rgba = rgbaPixels(from: image, width: width, height: height) else { return nil }
    return nchwFloats(fromRGBA: rgba, width: width, height: height, normalize: normalize)
  }

  /// RGBA8888 pixel bytes (4 per pixel, row-major, top row first) rendered at
  /// the given size. Row 0 matches CGImage's top-left coordinate origin, so
  /// downstream box/crop math stays in image coordinates.
  static func rgbaPixels(from image: CGImage, width: Int, height: Int) -> [UInt8]? {
    guard width > 0, height > 0 else { return nil }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    let rendered = buffer.withUnsafeMutableBytes { pointer -> Bool in
      guard let baseAddress = pointer.baseAddress,
            let context = CGContext(
              data: baseAddress,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: width * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
      else { return false }
      // Captures can carry alpha (rounded window corners, transparent PNGs).
      // Premultiplying those onto the zeroed buffer would turn them black and
      // hand the model white-on-black text, so composite onto white first.
      context.setFillColor(gray: 1, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return rendered ? buffer : nil
  }

  /// NCHW float32 conversion: channel 0 = B, 1 = G, 2 = R to match the
  /// OpenCV-decoded input the models were trained/exported with.
  static func nchwFloats(
    fromRGBA rgba: [UInt8],
    width: Int,
    height: Int,
    normalize: ChannelNormalize
  ) -> [Float] {
    let pixelCount = width * height
    var tensor = [Float](repeating: 0, count: 3 * pixelCount)
    for pixel in 0..<pixelCount {
      let base = pixel * 4
      let bgr: [UInt8] = [rgba[base + 2], rgba[base + 1], rgba[base]]
      for channel in 0..<3 {
        let scaled = Float(bgr[channel]) / 255.0
        tensor[channel * pixelCount + pixel] = (scaled - normalize.mean[channel]) / normalize.std[channel]
      }
    }
    return tensor
  }
}
