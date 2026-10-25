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

  var body: some View {
    Text(text)
      .font(.system(size: 11))
      .foregroundColor(.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: 260, alignment: .leading)
  }
}
