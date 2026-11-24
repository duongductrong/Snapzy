//
//  AutomationCanvasTheme.swift
//  Snapzy
//
//  Colors of the canvas editor. Everything maps to AppKit semantic colors so the
//  canvas follows light/dark mode, the accent color and Increase Contrast the
//  way the rest of macOS does: the backdrop is the under-page gray Preview and
//  Pages draw behind documents, cards are control backgrounds with a hairline.
//

import AppKit
import SwiftUI

enum AutomationCanvasTheme {
  static let backdrop = Color(nsColor: .underPageBackgroundColor)
  static let card = Color(nsColor: .controlBackgroundColor)
  static let hairline = Color(nsColor: .separatorColor)
  static let link = Color(nsColor: .tertiaryLabelColor)
  static let gridDot = Color(nsColor: .quaternaryLabelColor)
  static let port = Color(nsColor: .secondaryLabelColor)
  static let shadow = Color.black.opacity(0.12)
  static let otherwise = Color(nsColor: .systemOrange)

  /// Spring used for every structural change (add, remove, link, tidy up).
  static let spring = Animation.spring(response: 0.32, dampingFraction: 0.9)
}
