//
//  TooltipView.swift
//  Snapzy
//
//  Reusable .hint() View extension — shows a styled tooltip on hover.
//  Supports inline (hover the view) and icon variants (e.g. info circle).
//

import SwiftUI

// MARK: - Public API

enum HintIconStyle {
  case info

  var systemImage: String {
    switch self {
    case .info: return "info.circle.fill"
    }
  }
}

enum HintVariant {
  /// Tooltip appears when hovering the view itself
  case inline
  /// Appends a small icon next to the view; tooltip appears on icon hover
  case icon(HintIconStyle)
}

extension View {
  /// Adds a hint tooltip to the view.
  ///
  /// - Parameters:
  ///   - text: The tooltip message to display.
  ///   - variant: How the hint is displayed. Default is `.inline`.
  func hint(_ text: String, variant: HintVariant = .inline) -> some View {
    modifier(HintModifier(text: text, variant: variant))
  }
}

// MARK: - Modifier

private struct HintModifier: ViewModifier {
  let text: String
  let variant: HintVariant

  @State private var isHovering = false

  func body(content: Content) -> some View {
    switch variant {
    case .inline:
      content
        .onHover { hovering in isHovering = hovering }
        .popover(isPresented: $isHovering, arrowEdge: .bottom) {
          HintPopoverContent(text: text)
        }

    case .icon(let style):
      HStack(spacing: 6) {
        content

        // Filled disc with the glyph knocked out, so it reads as a quiet badge, not a line icon.
        Image(systemName: style.systemImage)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .onHover { hovering in isHovering = hovering }
          .popover(isPresented: $isHovering, arrowEdge: .bottom) {
            HintPopoverContent(text: text)
          }
      }
    }
  }
}

// MARK: - Popover Content

private struct HintPopoverContent: View {
  let text: String

  private static let fontSize: CGFloat = 11
  private static let maxTextWidth: CGFloat = 240
  private static let horizontalPadding: CGFloat = 10
  private static let verticalPadding: CGFloat = 6

  var body: some View {
    // NSPopover sizes itself from the hosting view's fitting size. A flexible width lets
    // macOS 15 measure the text at a near-zero width, so the popover grows very tall (#730).
    // Pin an exact width (the text's own width, capped) and let SwiftUI derive the height at it.
    Text(text)
      .font(.system(size: Self.fontSize))
      .foregroundColor(.primary)
      .lineLimit(nil)
      .frame(width: Self.textWidth(for: text), alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, Self.horizontalPadding)
      .padding(.vertical, Self.verticalPadding)
      .fixedSize()
  }

  private static func textWidth(for text: String) -> CGFloat {
    let rect = (text as NSString).boundingRect(
      with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: NSFont.systemFont(ofSize: fontSize)]
    )
    // Small slack so SwiftUI never wraps a line AppKit measured as fitting.
    return min(ceil(rect.width) + 2, maxTextWidth)
  }
}
