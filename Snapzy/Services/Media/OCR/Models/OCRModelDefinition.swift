//
//  OCRModelDefinition.swift
//  Snapzy
//
//  Static description of a downloadable OCR model and its files.
//

import Foundation

/// A single file belonging to a downloadable OCR model.
struct OCRModelFile: Equatable {
  /// File name on disk inside the model install directory (e.g. `det.onnx`).
  let name: String
  /// Remote location the file is downloaded from.
  let url: URL
  /// Expected download size in bytes; `nil` when unknown (skips size checks).
  let expectedBytes: Int64?
  /// Lowercase hex SHA256 digest; `nil` when no checksum is published.
  let sha256: String?
}

/// A downloadable OCR model entry from the catalog.
struct OCRModelDefinition: Equatable {
  /// Stable catalog identifier (e.g. `ppocrv6-tiny`); used on disk and in prefs.
  let id: String
  /// Human-readable model name shown in Settings.
  let displayName: String
  /// Parameter count label (e.g. `1.5M`).
  let parameterCountLabel: String
  /// FP32 size range label (e.g. `6–8 MB`).
  let fp32SizeLabel: String
  /// INT8 size range label (e.g. `2–4 MB`); labels only, INT8 not published.
  let int8SizeLabel: String
  /// Files to download, verified and installed in order.
  let files: [OCRModelFile]

  /// Sum of known file sizes; files without `expectedBytes` count as zero.
  var totalDownloadBytes: Int64 {
    files.reduce(0) { $0 + ($1.expectedBytes ?? 0) }
  }
}
