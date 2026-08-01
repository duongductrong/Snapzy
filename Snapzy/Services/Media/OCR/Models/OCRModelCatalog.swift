//
//  OCRModelCatalog.swift
//  Snapzy
//
//  Static catalog of downloadable PP-OCRv6 models.
//

import Foundation

/// Downloadable OCR models: official PaddleOCR HuggingFace FP32 ONNX artifacts
/// (det + rec) plus the character dictionary from the PaddleOCR repository.
///
/// Installed model directories contain `det.onnx`, `rec.onnx` and `dict.txt`.
enum OCRModelCatalog {
  static let all: [OCRModelDefinition] = [tiny, small, medium]

  static func definition(for id: String) -> OCRModelDefinition? {
    all.first { $0.id == id }
  }

  // MARK: - PP-OCRv6 Tiny

  private static let tiny = OCRModelDefinition(
    id: "ppocrv6-tiny",
    displayName: "PP-OCRv6 Tiny",
    parameterCountLabel: "1.5M",
    fp32SizeLabel: "6–8 MB",
    int8SizeLabel: "2–4 MB",
    files: [
      OCRModelFile(
        name: "det.onnx",
        url: URL(string: "https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_det_onnx/resolve/main/inference.onnx")!,
        expectedBytes: 1_780_590,
        sha256: "193bab7a04fca699a6c82e6abb5b81bdb28177f0abd4062552b04908dafb19f8"
      ),
      OCRModelFile(
        name: "rec.onnx",
        url: URL(string: "https://huggingface.co/PaddlePaddle/PP-OCRv6_tiny_rec_onnx/resolve/main/inference.onnx")!,
        expectedBytes: 4_462_639,
        sha256: "9ef676d6ed3c88256a2d92c640c44f25b0c40947e111b14b8be8f594091563e6"
      ),
      OCRModelFile(
        name: "dict.txt",
        url: URL(string: "https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/ppocr/utils/dict/ppocrv6_tiny_dict.txt")!,
        expectedBytes: nil,
        sha256: nil
      ),
    ]
  )

  // MARK: - PP-OCRv6 Small

  private static let small = OCRModelDefinition(
    id: "ppocrv6-small",
    displayName: "PP-OCRv6 Small",
    parameterCountLabel: "7.7M",
    fp32SizeLabel: "31–40 MB",
    int8SizeLabel: "8–15 MB",
    files: [
      OCRModelFile(
        name: "det.onnx",
        url: URL(string: "https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx/resolve/main/inference.onnx")!,
        expectedBytes: 9_880_512,
        sha256: "d73e0058b7a8086bbd57f3d10b8bcd4ff95363f67e06e2762b5e814fe9c9410e"
      ),
      OCRModelFile(
        name: "rec.onnx",
        url: URL(string: "https://huggingface.co/PaddlePaddle/PP-OCRv6_small_rec_onnx/resolve/main/inference.onnx")!,
        expectedBytes: 21_159_378,
        sha256: "5435fd747c9e0efe15a96d0b378d5bd157e9492ed8fd80edf08f30d02fa24634"
      ),
      OCRModelFile(
        name: "dict.txt",
        url: URL(string: "https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/ppocr/utils/dict/ppocrv6_dict.txt")!,
        expectedBytes: nil,
        sha256: nil
      ),
    ]
  )

  // MARK: - PP-OCRv6 Medium

  private static let medium = OCRModelDefinition(
    id: "ppocrv6-medium",
    displayName: "PP-OCRv6 Medium",
    parameterCountLabel: "34.5M",
    fp32SizeLabel: "138–160 MB",
    int8SizeLabel: "35–55 MB",
    files: [
      OCRModelFile(
        name: "det.onnx",
        url: URL(string: "https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_det_onnx/resolve/main/inference.onnx")!,
        expectedBytes: 62_032_837,
        sha256: "eb13b44b25bb36f89528b68720af8a61d9cf381176107f465db1757b65d086e1"
      ),
      OCRModelFile(
        name: "rec.onnx",
        url: URL(string: "https://huggingface.co/PaddlePaddle/PP-OCRv6_medium_rec_onnx/resolve/main/inference.onnx")!,
        expectedBytes: 76_554_979,
        sha256: "9c09abf0957f7968c7586464b7397b84ad2387a0497a351af40e9acc71b673ba"
      ),
      OCRModelFile(
        name: "dict.txt",
        url: URL(string: "https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/ppocr/utils/dict/ppocrv6_dict.txt")!,
        expectedBytes: nil,
        sha256: nil
      ),
    ]
  )
}
