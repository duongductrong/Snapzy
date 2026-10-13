//
//  SnapzyCurvedHintArrow.swift
//  Snapzy
//
//  Animated curved vector hint arrow with pure text label.
//  Directs user attention to target interactive controls during onboarding.
//

import SwiftUI

enum SnapzyHintArrowOrientation {
  case curveDownToTarget   // Label sits above, curves down to point at target
  case curveLeftToTarget   // Label sits to the right, curves down-left to point at target
  case curveRightToTarget  // Label sits to the left, curves down-right to point at target
}

struct SnapzyCurvedHintArrow: View {
  let text: String
  var orientation: SnapzyHintArrowOrientation = .curveDownToTarget
  var arrowAlignment: HorizontalAlignment = .center
  var color: Color = .white

  @State private var floatOffset: CGFloat = 0

  var body: some View {
    Group {
      switch orientation {
      case .curveDownToTarget:
        downToTargetLayout
      case .curveLeftToTarget:
        leftToTargetLayout
      case .curveRightToTarget:
        rightToTargetLayout
      }
    }
    .onAppear {
      withAnimation(
        Animation.easeInOut(duration: 1.6)
          .repeatForever(autoreverses: true)
      ) {
        floatOffset = -3
      }
    }
  }

  // MARK: - Layout: Label above, curve arcs down to target

  private var downToTargetLayout: some View {
    VStack(alignment: arrowAlignment, spacing: 2) {
      labelView

      // Vector curved stroke with arrowhead
      ZStack {
        // Dark contour stroke for high contrast on light backgrounds
        Path { path in
          path.move(to: CGPoint(x: 45, y: 0))
          path.addQuadCurve(to: CGPoint(x: 18, y: 36), control: CGPoint(x: 45, y: 24))
        }
        .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

        // Crisp main stroke
        Path { path in
          path.move(to: CGPoint(x: 45, y: 0))
          path.addQuadCurve(to: CGPoint(x: 18, y: 36), control: CGPoint(x: 45, y: 24))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

        // Arrowhead
        arrowHead(tip: CGPoint(x: 18, y: 36), from: CGPoint(x: 45, y: 24))
      }
      .frame(width: 60, height: 38)
      .shadow(color: Color.black.opacity(0.60), radius: 3, x: 0, y: 1)
      .padding(.trailing, arrowAlignment == .trailing ? 14 : 0)
      .padding(.leading, arrowAlignment == .leading ? 14 : 0)
    }
    .offset(y: floatOffset)
  }

  // MARK: - Layout: Label to the right, curves left to point at card

  private var leftToTargetLayout: some View {
    HStack(alignment: .bottom, spacing: 6) {
      ZStack {
        // Dark contour stroke
        Path { path in
          path.move(to: CGPoint(x: 58, y: 6))
          path.addQuadCurve(to: CGPoint(x: 4, y: 32), control: CGPoint(x: 48, y: 36))
        }
        .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

        // Main stroke
        Path { path in
          path.move(to: CGPoint(x: 58, y: 6))
          path.addQuadCurve(to: CGPoint(x: 4, y: 32), control: CGPoint(x: 48, y: 36))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

        // Arrowhead
        arrowHead(tip: CGPoint(x: 4, y: 32), from: CGPoint(x: 48, y: 36))
      }
      .frame(width: 62, height: 38)
      .shadow(color: Color.black.opacity(0.60), radius: 3, x: 0, y: 1)

      labelView
        .padding(.bottom, 10)
    }
    .offset(y: floatOffset)
  }

  // MARK: - Layout: Label to the left, curves right to point at target

  private var rightToTargetLayout: some View {
    HStack(alignment: .bottom, spacing: 6) {
      labelView
        .padding(.bottom, 10)

      ZStack {
        // Dark contour stroke
        Path { path in
          path.move(to: CGPoint(x: 4, y: 6))
          path.addQuadCurve(to: CGPoint(x: 58, y: 32), control: CGPoint(x: 14, y: 36))
        }
        .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

        // Main stroke
        Path { path in
          path.move(to: CGPoint(x: 4, y: 6))
          path.addQuadCurve(to: CGPoint(x: 58, y: 32), control: CGPoint(x: 14, y: 36))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

        // Arrowhead
        arrowHead(tip: CGPoint(x: 58, y: 32), from: CGPoint(x: 14, y: 36))
      }
      .frame(width: 62, height: 38)
      .shadow(color: Color.black.opacity(0.60), radius: 3, x: 0, y: 1)
    }
    .offset(y: floatOffset)
  }

  // MARK: - Arrowhead Generator

  private func arrowHead(tip: CGPoint, from control: CGPoint) -> some View {
    Path { path in
      let tipAngle = atan2(tip.y - control.y, tip.x - control.x)
      let headLength: CGFloat = 8
      let headAngle: CGFloat = .pi / 5.2
      path.move(to: tip)
      path.addLine(to: CGPoint(
        x: tip.x - headLength * cos(tipAngle - headAngle),
        y: tip.y - headLength * sin(tipAngle - headAngle)
      ))
      path.addLine(to: CGPoint(
        x: tip.x - (headLength * 0.65) * cos(tipAngle),
        y: tip.y - (headLength * 0.65) * sin(tipAngle)
      ))
      path.addLine(to: CGPoint(
        x: tip.x - headLength * cos(tipAngle + headAngle),
        y: tip.y - headLength * sin(tipAngle + headAngle)
      ))
      path.closeSubpath()
    }
    .fill(color)
  }

  // MARK: - Pure Text Label View

  private var labelView: some View {
    Text(text)
      .font(.system(size: 11.5, weight: .semibold))
      .foregroundStyle(color)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
      .shadow(color: Color.black.opacity(0.80), radius: 2.5, x: 0, y: 1)
      .shadow(color: Color.black.opacity(0.40), radius: 0.8, x: 0, y: 0.5)
  }
}
