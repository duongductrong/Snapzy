//
//  CloudShareService.swift
//  Snapzy
//
//  Upload-and-share used by the Quick Access card and automations: scoped file
//  access, upload, cleanup of a replaced object, and link formatting.
//

import AppKit
import Foundation

@MainActor
final class CloudShareService {
  static let shared = CloudShareService()

  var isConfigured: Bool {
    CloudManager.shared.isConfigured
  }

  /// Uploads `fileURL` under a fresh key (a new URL sidesteps CDN caches). When
  /// `replacingKey` is set, that older object is deleted in the background.
  func upload(fileURL: URL, replacingKey oldKey: String? = nil) async throws -> CloudUploadResult {
    let fileAccess = SandboxFileAccessManager.shared.beginAccessingURL(fileURL)
    defer { fileAccess.stop() }

    let result = try await CloudManager.shared.upload(fileURL: fileURL)

    if let oldKey {
      Task.detached(priority: .utility) {
        do {
          try await CloudManager.shared.deleteByKey(key: oldKey)
        } catch {
          DiagnosticLogger.shared.logError(.cloud, error, "Replaced cloud object cleanup failed")
        }
      }
    }
    return result
  }

  /// Clipboard text for an uploaded file.
  nonisolated static func linkText(
    for publicURL: URL,
    fileURL: URL,
    format: AutomationLinkFormat,
    isImage: Bool = true
  ) -> String {
    let link = publicURL.absoluteString
    switch format {
    case .url:
      return link
    case .markdown:
      let alt = fileURL.deletingPathExtension().lastPathComponent
        .replacingOccurrences(of: "[", with: "\\[")
        .replacingOccurrences(of: "]", with: "\\]")
      let needsAngleBrackets = link.contains(" ") || link.contains("(") || link.contains(")")
      let target = needsAngleBrackets ? "<\(link)>" : link
      // Videos are not inline images in Markdown; link them instead.
      return isImage ? "![\(alt)](\(target))" : "[\(alt)](\(target))"
    }
  }

  /// Writes `text` as the only pasteboard item and returns the new change count.
  @discardableResult
  func copyToPasteboard(_ text: String) -> Int {
    ClipboardHelper.copyText(text)
  }
}
