//
//  OCRLinkDetector.swift
//  Snapzy
//
//  Detects openable web links inside OCR-captured text so the capture flow can
//  offer to open them. Detection is passive: nothing is opened without an
//  explicit user action on the prompt.
//

import Foundation

nonisolated enum OCRLinkDetector {
  /// Upper bound on links surfaced in the post-capture prompt; keeps the
  /// prompt compact when a capture contains a wall of URLs.
  static let maxDetectedLinks = 3

  /// Returns unique web links (http/https, including bare domains promoted by
  /// NSDataDetector) found in `text`, in order of appearance.
  static func detectWebLinks(in text: String, limit: Int = maxDetectedLinks) -> [URL] {
    guard
      limit > 0,
      !text.isEmpty,
      let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else {
      return []
    }

    let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
    var seenKeys = Set<String>()
    var links: [URL] = []

    detector.enumerateMatches(in: text, options: [], range: fullRange) { match, _, stop in
      guard
        let url = match?.url,
        let webURL = webURL(from: url),
        seenKeys.insert(dedupeKey(for: webURL)).inserted
      else {
        return
      }

      links.append(webURL)
      if links.count >= limit {
        stop.pointee = true
      }
    }

    return links
  }

  /// Compact representation for UI display: scheme stripped, no trailing slash.
  static func displayString(for url: URL) -> String {
    var text = url.absoluteString
    for prefix in ["https://", "http://"] where text.lowercased().hasPrefix(prefix) {
      text.removeFirst(prefix.count)
      break
    }
    if text.hasSuffix("/") {
      text.removeLast()
    }
    return text
  }

  private static func webURL(from url: URL) -> URL? {
    guard
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let host = url.host, !host.isEmpty
    else {
      return nil
    }
    return url
  }

  /// Scheme and host are case-insensitive; path, query, and fragment are not.
  private static func dedupeKey(for url: URL) -> String {
    var key = url.absoluteString
    if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.scheme = components.scheme?.lowercased()
      components.host = components.host?.lowercased()
      key = components.url?.absoluteString ?? key
    }
    if key.hasSuffix("/") {
      key.removeLast()
    }
    return key
  }
}
