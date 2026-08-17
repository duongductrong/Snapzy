import AppKit
import Foundation
import SnapzyPluginAPI

/// `snapzy.ocr` — reuses the existing `OCRProvider` / Vision path. Local
/// Vision only; the plugin gets text-with-boxes without touching pixels it
/// has not explicitly read itself.
///
/// Coordinate space: Vision returns *normalized, bottom-left* boxes. This
/// service converts once, here, into the image's logical point space — and,
/// when the plugin passes the document's `coordinateSize`, into exactly the
/// space the document projection and `DocumentEdit` live in, so placed items
/// line up with zero coordinate math in plugin code.
final class PluginOCRService {
  func recognize(_ request: PluginOCRRequest) async throws -> PluginOCRResult {
    guard let source = CGImageSourceCreateWithData(request.image as CFData, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw PluginServiceError(code: "decodeFailed", message: "The image could not be decoded.")
    }

    let contentType: OCRContentType
    switch request.contentType {
    case "denseDocument": contentType = .denseDocument
    case "code": contentType = .code
    default: contentType = .interfaceText
    }

    let ocrRequest = OCRRequest(
      image: cgImage,
      preferredLanguageIdentifier: request.language,
      contentType: contentType
    )
    let result = try await VisionOCRProvider().recognize(ocrRequest)

    let pixelSize = SnapzySize(width: Double(cgImage.width), height: Double(cgImage.height))
    let targetSize = request.coordinateSize ?? pixelSize

    let lines = result.lines.map { line -> PluginOCRLine in
      let box = Self.imageRect(
        fromVisionBoundingBox: line.boundingBox,
        pixelSize: pixelSize,
        targetSize: targetSize
      )
      return PluginOCRLine(
        text: line.text,
        box: box,
        confidence: Double(line.confidence)
      )
    }

    return PluginOCRResult(lines: lines, text: result.text)
  }

  /// Vision's normalized bottom-left rect → logical point space (top-left
  /// origin), scaled into `targetSize` when the plugin asked for a specific
  /// coordinate space. Mirrors `AnnotateSensitiveRedactionService`'s
  /// conversion so both paths agree exactly.
  static func imageRect(
    fromVisionBoundingBox boundingBox: CGRect,
    pixelSize: SnapzySize,
    targetSize: SnapzySize
  ) -> SnapzyRect {
    let x = boundingBox.minX * pixelSize.width
    let y = (1 - boundingBox.maxY) * pixelSize.height
    let width = boundingBox.width * pixelSize.width
    let height = boundingBox.height * pixelSize.height
    let scaleX = targetSize.width / max(pixelSize.width, 1)
    let scaleY = targetSize.height / max(pixelSize.height, 1)
    return SnapzyRect(x: x * scaleX, y: y * scaleY, width: width * scaleX, height: height * scaleY)
      .standardized
  }
}
