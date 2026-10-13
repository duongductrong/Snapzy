//
//  SnapzyUnevenRoundedRectangle.swift
//  Snapzy
//
//  Custom Shape with per-corner radii, backwards compatible with macOS 13.0+.
//

import SwiftUI

struct SnapzyCornerRadii: Equatable {
  var topLeading: CGFloat
  var bottomLeading: CGFloat
  var bottomTrailing: CGFloat
  var topTrailing: CGFloat

  init(topLeading: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0, topTrailing: CGFloat = 0) {
    self.topLeading = topLeading
    self.bottomLeading = bottomLeading
    self.bottomTrailing = bottomTrailing
    self.topTrailing = topTrailing
  }
}

struct SnapzyUnevenRoundedRectangle: Shape, InsettableShape {
  var cornerRadii: SnapzyCornerRadii
  var insetAmount: CGFloat = 0

  init(cornerRadii: SnapzyCornerRadii) {
    self.cornerRadii = cornerRadii
  }

  func inset(by amount: CGFloat) -> SnapzyUnevenRoundedRectangle {
    var copy = self
    copy.insetAmount += amount
    return copy
  }

  func path(in rect: CGRect) -> Path {
    let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
    let w = insetRect.width
    let h = insetRect.height

    let tl = max(0, min(cornerRadii.topLeading - insetAmount, min(w, h) / 2))
    let tr = max(0, min(cornerRadii.topTrailing - insetAmount, min(w, h) / 2))
    let br = max(0, min(cornerRadii.bottomTrailing - insetAmount, min(w, h) / 2))
    let bl = max(0, min(cornerRadii.bottomLeading - insetAmount, min(w, h) / 2))

    var path = Path()

    // Start at top edge after top-left corner
    path.move(to: CGPoint(x: insetRect.minX + tl, y: insetRect.minY))

    // Top edge & top-right corner
    path.addLine(to: CGPoint(x: insetRect.maxX - tr, y: insetRect.minY))
    if tr > 0 {
      path.addArc(
        center: CGPoint(x: insetRect.maxX - tr, y: insetRect.minY + tr),
        radius: tr,
        startAngle: Angle(degrees: -90),
        endAngle: Angle(degrees: 0),
        clockwise: false
      )
    }

    // Right edge & bottom-right corner
    path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - br))
    if br > 0 {
      path.addArc(
        center: CGPoint(x: insetRect.maxX - br, y: insetRect.maxY - br),
        radius: br,
        startAngle: Angle(degrees: 0),
        endAngle: Angle(degrees: 90),
        clockwise: false
      )
    }

    // Bottom edge & bottom-left corner
    path.addLine(to: CGPoint(x: insetRect.minX + bl, y: insetRect.maxY))
    if bl > 0 {
      path.addArc(
        center: CGPoint(x: insetRect.minX + bl, y: insetRect.maxY - bl),
        radius: bl,
        startAngle: Angle(degrees: 90),
        endAngle: Angle(degrees: 180),
        clockwise: false
      )
    }

    // Left edge & top-left corner
    path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + tl))
    if tl > 0 {
      path.addArc(
        center: CGPoint(x: insetRect.minX + tl, y: insetRect.minY + tl),
        radius: tl,
        startAngle: Angle(degrees: 180),
        endAngle: Angle(degrees: 270),
        clockwise: false
      )
    }

    path.closeSubpath()
    return path
  }
}
