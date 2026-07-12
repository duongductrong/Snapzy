import CoreGraphics
import Foundation

enum CombineImagesMode: String, CaseIterable {
  case autoStitch
  case freeCanvas
}

enum CombineImagesDirection: String, CaseIterable {
  case smart
  case horizontal
  case vertical
}

struct CombineImagesLayoutItem: Equatable {
  let id: UUID
  let size: CGSize
}

struct CombineImagesLayoutResult: Equatable {
  let direction: CombineImagesDirection
  let boundsByID: [UUID: CGRect]
  let contentBounds: CGRect
}

enum CombineImagesLayout {
  static func resolveDirection(
    requested: CombineImagesDirection,
    items: [CombineImagesLayoutItem],
    gap: CGFloat = 0
  ) -> CombineImagesDirection {
    guard requested == .smart else { return requested }
    guard let first = items.first, first.size.width > 0, first.size.height > 0 else {
      return .horizontal
    }

    let horizontalWidth = items.reduce(CGFloat.zero) { total, item in
      total + scaledSize(item.size, matchingHeight: first.size.height).width
    } + gap * CGFloat(max(items.count - 1, 0))
    let horizontalAspect = horizontalWidth / first.size.height

    let verticalHeight = items.reduce(CGFloat.zero) { total, item in
      total + scaledSize(item.size, matchingWidth: first.size.width).height
    } + gap * CGFloat(max(items.count - 1, 0))
    let verticalAspect = first.size.width / verticalHeight

    // Prefer the arrangement closest to a useful landscape canvas while avoiding
    // extremely long strips in either direction.
    let preferredAspect: CGFloat = 1.35
    let horizontalDistance = abs(log(max(horizontalAspect, 0.0001) / preferredAspect))
    let verticalDistance = abs(log(max(verticalAspect, 0.0001) / preferredAspect))
    return horizontalDistance <= verticalDistance ? .horizontal : .vertical
  }

  static func layout(
    items: [CombineImagesLayoutItem],
    direction requestedDirection: CombineImagesDirection,
    gap: CGFloat
  ) -> CombineImagesLayoutResult {
    guard let first = items.first, first.size.width > 0, first.size.height > 0 else {
      return CombineImagesLayoutResult(
        direction: requestedDirection == .vertical ? .vertical : .horizontal,
        boundsByID: [:],
        contentBounds: .zero
      )
    }

    let direction = resolveDirection(requested: requestedDirection, items: items, gap: gap)
    let safeGap = max(0, gap)
    var cursor: CGFloat = 0
    var boundsByID: [UUID: CGRect] = [:]

    for item in items where item.size.width > 0 && item.size.height > 0 {
      let targetSize: CGSize
      let origin: CGPoint
      switch direction {
      case .horizontal, .smart:
        targetSize = scaledSize(item.size, matchingHeight: first.size.height)
        origin = CGPoint(x: cursor, y: 0)
        cursor += targetSize.width + safeGap
      case .vertical:
        targetSize = scaledSize(item.size, matchingWidth: first.size.width)
        origin = CGPoint(x: 0, y: cursor)
        cursor += targetSize.height + safeGap
      }
      boundsByID[item.id] = CGRect(origin: origin, size: targetSize)
    }

    let allBounds = Array(boundsByID.values)
    let contentBounds = allBounds.dropFirst().reduce(allBounds.first ?? .zero) { $0.union($1) }
    return CombineImagesLayoutResult(
      direction: direction,
      boundsByID: boundsByID,
      contentBounds: contentBounds
    )
  }

  private static func scaledSize(_ size: CGSize, matchingHeight height: CGFloat) -> CGSize {
    guard size.height > 0 else { return .zero }
    let scale = height / size.height
    return CGSize(width: size.width * scale, height: height)
  }

  private static func scaledSize(_ size: CGSize, matchingWidth width: CGFloat) -> CGSize {
    guard size.width > 0 else { return .zero }
    let scale = width / size.width
    return CGSize(width: width, height: size.height * scale)
  }
}

