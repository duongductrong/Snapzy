import Foundation
import SnapzyPluginAPI

public enum OCRHelpers {
  /// Sorts OCR lines into reading order: top to bottom, then left to right.
  public static func inReadingOrder(_ lines: [PluginOCRLine]) -> [PluginOCRLine] {
    lines.sorted { a, b in
      let yThreshold = min(a.box.height, b.box.height) / 2.0
      if abs(a.box.y - b.box.y) > yThreshold {
        return a.box.y < b.box.y
      }
      return a.box.x < b.box.x
    }
  }
}

public func inReadingOrder(_ lines: [PluginOCRLine]) -> [PluginOCRLine] {
  OCRHelpers.inReadingOrder(lines)
}
