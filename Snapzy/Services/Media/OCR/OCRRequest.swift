//
//  OCRRequest.swift
//  Snapzy
//
//  Shared OCR request metadata for engine routing and benchmarking.
//

import CoreGraphics

enum OCRContentType: String {
  case interfaceText
  case denseDocument
  case code
}

struct OCRRequest {
  let image: CGImage
  let preferredLanguageIdentifier: String?
  let contentType: OCRContentType

  init(
    image: CGImage,
    preferredLanguageIdentifier: String? = nil,
    contentType: OCRContentType = .interfaceText
  ) {
    self.image = image
    self.preferredLanguageIdentifier = preferredLanguageIdentifier
    self.contentType = contentType
  }
}
