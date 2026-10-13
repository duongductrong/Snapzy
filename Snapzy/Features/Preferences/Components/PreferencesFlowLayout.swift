//
//  PreferencesFlowLayout.swift
//  Snapzy
//
//  Horizontal wrapping flow layout for SwiftUI with configurable alignment.
//

import SwiftUI

struct PreferencesFlowLayout: Layout {
  var horizontalSpacing: CGFloat = 6
  var verticalSpacing: CGFloat = 4
  var alignment: HorizontalAlignment = .trailing

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var currentLineHeight: CGFloat = 0
    var maxLineWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if currentX + size.width > maxWidth, currentX > 0 {
        maxLineWidth = max(maxLineWidth, currentX - horizontalSpacing)
        currentX = 0
        currentY += currentLineHeight + verticalSpacing
        currentLineHeight = 0
      }
      currentX += size.width + horizontalSpacing
      currentLineHeight = max(currentLineHeight, size.height)
    }

    maxLineWidth = max(maxLineWidth, currentX > 0 ? currentX - horizontalSpacing : 0)
    let totalHeight = currentY + currentLineHeight
    let finalWidth = proposal.width ?? maxLineWidth
    return CGSize(width: finalWidth, height: totalHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
    var lines: [[(LayoutSubview, CGSize)]] = []
    var currentLine: [(LayoutSubview, CGSize)] = []
    var currentLineWidth: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if currentLineWidth + size.width > bounds.width, !currentLine.isEmpty {
        lines.append(currentLine)
        currentLine = []
        currentLineWidth = 0
      }
      currentLine.append((subview, size))
      currentLineWidth += size.width + horizontalSpacing
    }
    if !currentLine.isEmpty {
      lines.append(currentLine)
    }

    var currentY = bounds.minY
    for line in lines {
      let lineWidth = line.reduce(0) { $0 + $1.1.width } + CGFloat(max(0, line.count - 1)) * horizontalSpacing
      let lineHeight = line.map(\.1.height).max() ?? 0

      var currentX: CGFloat = switch alignment {
      case .leading:
        bounds.minX
      case .center:
        bounds.minX + max(0, bounds.width - lineWidth) / 2
      case .trailing:
        bounds.maxX - lineWidth
      default:
        bounds.maxX - lineWidth
      }

      for (subview, size) in line {
        subview.place(
          at: CGPoint(x: currentX, y: currentY + (lineHeight - size.height) / 2),
          proposal: ProposedViewSize(size)
        )
        currentX += size.width + horizontalSpacing
      }
      currentY += lineHeight + verticalSpacing
    }
  }
}
