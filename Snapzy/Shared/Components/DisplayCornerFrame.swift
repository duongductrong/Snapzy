//
//  DisplayCornerFrame.swift
//  Snapzy
//
//  Artistic crop of a Mac display's top-right corner: dark bezel, rounded
//  screen corner, and an aluminium-edge rim. Content renders as the screen.
//

import SwiftUI

/// Frames `content` as the top-right corner of a Mac display. The crop runs
/// off the left and bottom edges, so content should read as continuing there.
struct DisplayCornerFrame<Content: View>: View {
  var bezelWidth: CGFloat = 9
  var screenCornerRadius: CGFloat = 13
  var chassisCornerRadius: CGFloat = 22
  @ViewBuilder var content: Content

  var body: some View {
    let screenShape = CornerRoundedRectangle(topTrailing: screenCornerRadius)

    content
      .clipShape(screenShape)
      // Hairlines and rim trace only the physical top and right edges; the
      // left and bottom are crop lines and must stay open.
      .overlay(
        DisplayEdgeShape(startInset: 0, cornerRadius: screenCornerRadius)
          .stroke(Color.black.opacity(0.6), lineWidth: 0.5)
      )
      .padding(.top, bezelWidth)
      .padding(.trailing, bezelWidth)
      .background(
        // Display bezel. A faint top-down sheen keeps it from reading as flat black.
        LinearGradient(
          colors: [Color(white: 0.11), Color(white: 0.04)],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .clipShape(chassisShape)
      .overlay(
        DisplayEdgeShape(startInset: Radius.card, cornerRadius: chassisCornerRadius, inset: 0.5)
          .stroke(
            LinearGradient(
              colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
              startPoint: .topTrailing,
              endPoint: .bottomLeading
            ),
            lineWidth: 1
          )
      )
  }

  private var chassisShape: CornerRoundedRectangle {
    CornerRoundedRectangle(
      topLeading: Radius.card,
      topTrailing: chassisCornerRadius,
      bottomLeading: Radius.card,
      bottomTrailing: Radius.card
    )
  }
}

/// Open path along a display's top edge, around the rounded top-right corner,
/// and down the right edge.
private struct DisplayEdgeShape: Shape {
  var startInset: CGFloat
  var cornerRadius: CGFloat
  var inset: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    let rect = rect.insetBy(dx: inset, dy: inset)
    let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + startInset, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + radius),
      control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + inset))
    return path
  }
}

/// Rounded rectangle with independent corner radii (UnevenRoundedRectangle
/// needs macOS 14).
struct CornerRoundedRectangle: InsettableShape {
  var topLeading: CGFloat = 0
  var topTrailing: CGFloat = 0
  var bottomLeading: CGFloat = 0
  var bottomTrailing: CGFloat = 0
  var insetAmount: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
    let limit = min(rect.width, rect.height) / 2
    let tl = min(topLeading, limit)
    let tr = min(topTrailing, limit)
    let bl = min(bottomLeading, limit)
    let br = min(bottomTrailing, limit)

    var path = Path()
    path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + tr),
      control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - br, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - bl),
      control: CGPoint(x: rect.minX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + tl, y: rect.minY),
      control: CGPoint(x: rect.minX, y: rect.minY)
    )
    path.closeSubpath()
    return path
  }

  func inset(by amount: CGFloat) -> CornerRoundedRectangle {
    var shape = self
    shape.insetAmount += amount
    return shape
  }
}
