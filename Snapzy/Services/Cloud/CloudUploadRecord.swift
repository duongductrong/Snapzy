//
//  CloudUploadRecord.swift
//  Snapzy
//
//  Model for persisted cloud upload history entries
//

import Foundation

/// Record of a file uploaded to cloud storage, persisted locally
struct CloudUploadRecord: Identifiable, Codable, Equatable {
  let id: UUID
  let fileName: String
  let publicURL: URL
  let key: String
  let fileSize: Int64
  let uploadedAt: Date
  let providerType: CloudProviderType
  let expireTime: CloudExpireTime
  /// MIME type of the uploaded file (e.g. "image/png"). Optional for backward compatibility.
  let contentType: String?

  /// Human-readable file size
  var formattedFileSize: String {
    ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
  }

  /// Whether this upload has expired based on its expire time
  var isExpired: Bool {
    guard let seconds = expireTime.seconds else { return false }
    return Date().timeIntervalSince(uploadedAt) > TimeInterval(seconds)
  }

  /// Formatted upload date
  var formattedDate: String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: uploadedAt)
  }

  /// Whether the uploaded file is an image type
  var isImageType: Bool {
    if let ct = contentType {
      return ct.hasPrefix("image/")
    }
    // Fallback: infer from file extension
    let ext = (fileName as NSString).pathExtension.lowercased()
    return ["png", "jpg", "jpeg", "webp", "gif", "tiff", "tif", "bmp"].contains(ext)
  }

  /// Local thumbnail URL in App Support, if the thumbnail file exists
  var thumbnailURL: URL? {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let thumbURL = appSupport
      .appendingPathComponent("Snapzy", isDirectory: true)
      .appendingPathComponent("thumbnails", isDirectory: true)
      .appendingPathComponent("\(id.uuidString).jpg")
    return FileManager.default.fileExists(atPath: thumbURL.path) ? thumbURL : nil
  }
}
