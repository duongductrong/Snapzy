//
//  SnapzyCurvedHintArrow.swift
//  Snapzy
//
//  Animated curved vector hint arrow with tactile glass badge and pulsing accent dot.
//  Directs user attention to target interactive controls during onboarding.
//

import SwiftUI

enum SnapzyHintArrowOrientation {
  case curveDownToTarget   // Badge sits top-left or top-center, curves down to point at target
  case curveLeftToTarget   // Badge sits to the right, curves down-left to point at target
  case curveRightToTarget  // Badge sits to the left, curves down-right to point at target
}

struct SnapzyCurvedHintArrow: View {
  let text: String
  var orientation: SnapzyHintArrowOrientation = .curveDownToTarget
  var color: Color = Color(red: 1.0, green: 0.72, blue: 0.20) // warm amber gold
  var icon: String? = nil

  @State private var isHovering = false
  @State private var isPulsing = false
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
      isPulsing = true
      withAnimation(
        Animation.easeInOut(duration: 1.6)
          .repeatForever(autoreverses: true)
      ) {
        floatOffset = -3
      }
    }
  }

  // MARK: - Layout: Badge above, curve arcs down to target

  private var downToTargetLayout: some View {
    VStack(spacing: 2) {
      badgeView

      // Vector curved stroke with arrowhead
      ZStack {
        // Subtle glow background stroke
        Path { path in
          path.move(to: CGPoint(x: 45, y: 0))
          path.addQuadCurve(to: CGPoint(x: 18, y: 36), control: CGPoint(x: 45, y: 24))
        }
        .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

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
    }
    .offset(y: floatOffset)
  }

  // MARK: - Layout: Badge to the right, curves left to point at card

  private var leftToTargetLayout: some View {
    HStack(alignment: .bottom, spacing: 3) {
      ZStack {
        // Glow stroke
        Path { path in
          path.move(to: CGPoint(x: 58, y: 6))
          path.addQuadCurve(to: CGPoint(x: 4, y: 32), control: CGPoint(x: 48, y: 36))
        }
        .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

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

      badgeView
        .padding(.bottom, 12)
    }
    .offset(y: floatOffset)
  }

  // MARK: - Layout: Badge to the left, curves right to point at target

  private var rightToTargetLayout: some View {
    HStack(alignment: .bottom, spacing: 3) {
      badgeView
        .padding(.bottom, 12)

      ZStack {
        // Glow stroke
        Path { path in
          path.move(to: CGPoint(x: 4, y: 6))
          path.addQuadCurve(to: CGPoint(x: 58, y: 32), control: CGPoint(x: 14, y: 36))
        }
        .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

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
    .shadow(color: color.opacity(0.5), radius: 3, x: 0, y: 1)
  }

  // MARK: - Badge View

  private var badgeView: some View {
    HStack(spacing: 5) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
        .scaleEffect(isPulsing ? 1.25 : 0.8)
        .opacity(isPulsing ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: isPulsing)

      if let icon {
        Image(systemName: icon)
          .font(.system(size: 9.5, weight: .bold))
          .foregroundStyle(color)
      }

      Text(text)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 4.5)
    .background {
      Capsule(style: .continuous)
        .fill(Color.black.opacity(0.78))
    }
    .overlay {
      Capsule(style: .continuous)
        .strokeBorder(
          LinearGradient(
            colors: [Color.white.opacity(0.35), Color.white.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 0.75
        )
    }
    .shadow(color: Color.black.opacity(0.40), radius: 8, y: 3)
  }
}
