//
//  LineStyleIcon.swift
//  Snapzy
//
//  Toolbar icon that renders a line dash style as an actual stroke pattern.
//

import SwiftUI

/// Draws a horizontal sample stroke for a `LineDashStyle` (solid/dashed/dotted).
/// Inherits the surrounding foreground color like a template SF Symbol would.
struct LineStyleIcon: View {
  let style: LineDashStyle

  var body: some View {
    Path { path in
      path.move(to: CGPoint(x: 0, y: 6))
      path.addLine(to: CGPoint(x: 16, y: 6))
    }
    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: style.iconDash))
    .frame(width: 16, height: 12)
  }
}
