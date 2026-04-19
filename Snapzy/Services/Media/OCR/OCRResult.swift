//
//  OCRResult.swift
//  Snapzy
//
//  Normalized OCR output shared by runtime and benchmark code.
//

import CoreGraphics

enum OCREngine: String {
  case vision
}

struct OCRTextLine {
  let text: String
  let confidence: Float
  let boundingBox: CGRect
}

struct OCRResult {
  let engine: OCREngine
  let profileID: String
  let text: String
  let lines: [OCRTextLine]
  let averageConfidence: Float
}
