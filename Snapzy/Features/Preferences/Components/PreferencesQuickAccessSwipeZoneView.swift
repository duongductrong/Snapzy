import SwiftUI

struct QuickAccessPreviewSwipeZone: View {
  let direction: QuickAccessSwipeDirection
  let action: QuickAccessActionKind?
  let isTargeted: Bool
  let isHighlighted: Bool
  let diameter: CGFloat
  let onHover: (Bool) -> Void

  var body: some View {
    VStack(spacing: 7) {
      actionOrb
      directionLabel
    }
    .frame(width: diameter + 72, height: diameter + 30)
    .contentShape(Rectangle())
    .onHover(perform: onHover)
    .help("\(direction.displayName): \(swipeActionTitle)")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("\(direction.displayName), \(swipeActionTitle)"))
  }

  private var actionOrb: some View {
    Group {
      if let action {
        Image(systemName: action.systemImage)
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(.white)
          .frame(width: 20, height: 20)
          .background(Circle().fill(Color.black.opacity(0.62)))
      } else {
        Circle()
          .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
          .overlay(
            Image(systemName: "plus")
              .font(.system(size: 9, weight: .bold))
              .foregroundColor(.white.opacity(0.8))
          )
          .frame(width: 20, height: 20)
          .background(Circle().fill(Color.black.opacity(0.25)))
      }
    }
    .frame(width: diameter, height: diameter)
    .overlay(
      Circle().stroke(isActive ? Color(nsColor: .controlAccentColor) : Color.clear, lineWidth: 2)
    )
    .contentShape(Circle())
    .scaleEffect(isActive ? 1.1 : 1)
  }

  private var directionLabel: some View {
    Text(direction.displayName)
      .font(.caption2.weight(.semibold))
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .foregroundStyle(isActive ? .primary : .tertiary)
  }

  private var swipeActionTitle: String {
    guard let action else {
      return L10n.Common.none
    }
    return action == .dismiss
      ? L10n.PreferencesQuickAccess.swipeActionDismiss
      : action.settingsTitle
  }

  private var isActive: Bool {
    isTargeted || isHighlighted
  }
}

struct QuickAccessPreviewSwipeArrow: View {
  let direction: QuickAccessSwipeDirection
  let isHighlighted: Bool
  let cardWidth: CGFloat
  let targetOffsetX: CGFloat
  let targetDiameter: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let points = arrowPoints(in: proxy.size)
      let arrowOpacity = isHighlighted ? 0.6 : 0.3

      Path { path in
        path.move(to: points.start)
        path.addCurve(to: points.end, control1: points.control1, control2: points.control2)
      }
      .stroke(
        Color.secondary.opacity(arrowOpacity),
        style: StrokeStyle(
          lineWidth: isHighlighted ? 2.0 : 1.4,
          lineCap: .round,
          lineJoin: .round
        )
      )

      Image(systemName: arrowHeadSystemImage)
        .font(.system(size: isHighlighted ? 10 : 8, weight: .semibold))
        .foregroundStyle(Color.secondary.opacity(arrowOpacity))
        .position(points.end)
    }
  }

  private var arrowHeadSystemImage: String {
    switch direction {
    case .left:
      return "arrowtriangle.left.fill"
    case .right:
      return "arrowtriangle.right.fill"
    }
  }

  private func arrowPoints(in size: CGSize) -> (start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint) {
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let directionSign: CGFloat = direction == .left ? -1 : 1
    // arcLift is negative for BOTH directions so it curves upwards
    let arcLift: CGFloat = -45

    let start = CGPoint(
      x: center.x + directionSign * (cardWidth / 2 + 10),
      y: center.y
    )
    // End the line exactly at the arrow head center for seamless joint
    let end = CGPoint(
      x: center.x + directionSign * (targetOffsetX - targetDiameter / 2 - 4),
      y: center.y
    )
    
    // Distance between start and end is roughly 50 points.
    // Ensure control points don't cross horizontally to prevent looping/kinks.
    let dx = end.x - start.x
    let control1 = CGPoint(
      x: start.x + dx * 0.33,
      y: start.y + arcLift
    )
    // control2.y == end.y ensures horizontal tangent at arrival, matching arrowhead perfectly
    let control2 = CGPoint(
      x: end.x - dx * 0.33,
      y: end.y
    )

    return (start, control1, control2, end)
  }
}

struct QuickAccessPreviewSwipeZonePopover: View {
  let direction: QuickAccessSwipeDirection
  let action: QuickAccessActionKind?

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: direction.systemImage)
        .font(.system(size: 12, weight: .semibold))
      VStack(alignment: .leading, spacing: 1) {
        Text(direction.displayName)
          .font(.caption.weight(.semibold))
        Text(swipeActionTitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .foregroundStyle(.primary)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.regularMaterial, in: Radius.rect(Radius.card))
    .overlay(
      Radius.rect(Radius.card)
        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
  }

  private var swipeActionTitle: String {
    guard let action else {
      return L10n.Common.none
    }
    return action == .dismiss
      ? L10n.PreferencesQuickAccess.swipeActionDismiss
      : action.settingsTitle
  }
}
