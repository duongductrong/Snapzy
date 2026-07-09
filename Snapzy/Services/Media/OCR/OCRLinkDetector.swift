//
//  OCRLinkDetector.swift
//  Snapzy
//
//  Detects when OCR-captured text is exactly one openable web link so the
//  capture flow can offer to open it. Detection is passive: nothing is opened
//  without an explicit user action on the prompt.
//

import Foundation

nonisolated enum OCRLinkDetector {
  /// Returns the web link (http/https, including bare domains promoted by
  /// NSDataDetector) when the trimmed `text` consists of nothing but that
  /// link. Text that merely contains a URL among other content returns nil.
  static func exclusiveWebLink(in text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmed.isEmpty,
      let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else {
      return nil
    }

    let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
    let matches = detector.matches(in: trimmed, options: [], range: fullRange)
    guard
      matches.count == 1,
      let match = matches.first,
      match.range == fullRange,
      let url = match.url
    else {
      return nil
    }

    return webURL(from: url)
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
}
