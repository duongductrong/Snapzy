//
//  QuickAccessOptimizeMenuView.swift
//  Snapzy
//
//  Vertical Liquid Glass (clear) list of Optimize levels shown beside a Quick
//  Access card. Each row shows the level, its pixel size and its encoded size.
//

import AppKit
import Combine
import SwiftUI

enum QuickAccessOptimizeMenuFormatting {
  /// "1x", or "Original (2x)" for the untouched size.
  static func title(for level: QuickAccessOptimizeLevel) -> String {
    level.isOriginal
      ? "\(L10n.QuickAccess.optimizeOriginal) (\(level.scaleLabel))"
      : level.scaleLabel
  }

  /// "−62%" against the original, or nil when it would not shrink anything.
  static func savingsLabel(byteCount: Int, originalByteCount: Int?) -> String? {
    guard let originalByteCount, originalByteCount > 0, byteCount < originalByteCount else { return nil }
    let percent = Int((Double(originalByteCount - byteCount) / Double(originalByteCount) * 100).rounded())
    guard percent > 0 else { return nil }
    return "−\(percent)%"
  }
}

@MainActor
final class QuickAccessOptimizeMenuModel: ObservableObject {
  struct Row: Identifiable, Equatable {
    let level: QuickAccessOptimizeLevel
    var byteCount: Int?
    var encodedData: Data?
    var isEstimating: Bool

    var id: CGFloat { level.fraction }
  }

  let itemID: UUID
  let originalByteCount: Int?
  @Published private(set) var rows: [Row]
  @Published private(set) var currentFraction: CGFloat
  @Published var highlightedFraction: CGFloat?

  var onChoose: ((Row) -> Void)?

  init(itemID: UUID, plan: QuickAccessOptimizePlan) {
    self.itemID = itemID
    originalByteCount = plan.originalByteCount
    currentFraction = plan.currentFraction
    highlightedFraction = plan.currentFraction
    rows = plan.levels.map { level in
      Row(
        level: level,
        byteCount: level.isOriginal ? plan.originalByteCount : nil,
        encodedData: nil,
        isEstimating: !level.isOriginal
      )
    }
  }

  func record(_ level: QuickAccessOptimizeLevel, data: Data?) {
    guard let index = rows.firstIndex(where: { $0.level == level }) else { return }
    rows[index].encodedData = data
    rows[index].byteCount = data?.count
    rows[index].isEstimating = false
  }

  func choose(_ row: Row) {
    onChoose?(row)
  }

  func moveHighlight(by offset: Int) {
    guard !rows.isEmpty else { return }
    let currentIndex = rows.firstIndex { $0.level.fraction == highlightedFraction } ?? 0
    let nextIndex = min(max(currentIndex + offset, 0), rows.count - 1)
    highlightedFraction = rows[nextIndex].level.fraction
  }

  func chooseHighlighted() {
    guard let row = rows.first(where: { $0.level.fraction == highlightedFraction }) else { return }
    choose(row)
  }
}

struct QuickAccessOptimizeMenuView: View {
  @ObservedObject var model: QuickAccessOptimizeMenuModel

  static let width: CGFloat = 224
  private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(L10n.QuickAccess.optimizeMenuTitle)
        .font(.system(size: 10, weight: .semibold))
        .textCase(.uppercase)
        .tracking(0.6)
        .foregroundColor(.white.opacity(0.6))
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 2)

      ForEach(model.rows) { row in
        QuickAccessOptimizeRowView(
          row: row,
          isCurrent: row.level.fraction == model.currentFraction,
          isHighlighted: row.level.fraction == model.highlightedFraction,
          originalByteCount: model.originalByteCount,
          onHover: { hovering in
            if hovering { model.highlightedFraction = row.level.fraction }
          },
          onChoose: { model.choose(row) }
        )
      }
    }
    .padding(6)
    .frame(width: Self.width)
    // Clear glass over a busy screenshot needs a dim layer for legible text.
    .background(shape.fill(Color.black.opacity(0.22)))
    .liquidGlassSurface(
      shape: shape,
      substrate: 0.3,
      layer: .backdrop,
      nativeVariant: .clear
    )
    .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
    .environment(\.colorScheme, .dark)
    .padding(10)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.QuickAccess.optimizeMenuTitle)
  }
}

private struct QuickAccessOptimizeRowView: View {
  let row: QuickAccessOptimizeMenuModel.Row
  let isCurrent: Bool
  let isHighlighted: Bool
  let originalByteCount: Int?
  let onHover: (Bool) -> Void
  let onChoose: () -> Void

  var body: some View {
    Button(action: onChoose) {
      HStack(spacing: 10) {
        scaleBadge

        VStack(alignment: .leading, spacing: 1) {
          if row.level.isOriginal {
            Text(L10n.QuickAccess.optimizeOriginal)
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(.white)
          }
          Text(row.level.dimensionsLabel)
            .font(.system(size: row.level.isOriginal ? 10 : 12, weight: .medium).monospacedDigit())
            .foregroundColor(.white.opacity(row.level.isOriginal ? 0.6 : 0.9))
        }

        Spacer(minLength: 4)

        sizeColumn
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(Color.white.opacity(isHighlighted ? 0.16 : 0))
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      onHover(hovering)
      if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }
    .accessibilityLabel(accessibilityText)
    .accessibilityAddTraits(isCurrent ? .isSelected : [])
  }

  /// The scale label, circled when it is what the file currently holds (as in the mockup).
  private var scaleBadge: some View {
    Text(row.level.scaleLabel)
      .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
      .foregroundColor(.white)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .frame(width: 38, height: 30)
      .background(
        Capsule(style: .continuous)
          .strokeBorder(Color.white.opacity(isCurrent ? 0.9 : 0), lineWidth: 1.5)
      )
  }

  @ViewBuilder
  private var sizeColumn: some View {
    if row.isEstimating {
      ProgressView()
        .controlSize(.small)
        .scaleEffect(0.7)
        .frame(width: 18, height: 18)
        .help(L10n.QuickAccess.optimizeEstimating)
    } else if let byteCount = row.byteCount {
      VStack(alignment: .trailing, spacing: 1) {
        Text(QuickAccessImageOptimizer.formatByteCount(byteCount))
          .font(.system(size: 11, weight: .semibold).monospacedDigit())
          .foregroundColor(.white.opacity(0.95))
        if let savings = QuickAccessOptimizeMenuFormatting.savingsLabel(
          byteCount: byteCount,
          originalByteCount: originalByteCount
        ) {
          Text(savings)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundColor(Color(red: 0.45, green: 0.9, blue: 0.6))
        }
      }
    }
  }

  private var accessibilityText: String {
    var parts = [QuickAccessOptimizeMenuFormatting.title(for: row.level), row.level.dimensionsLabel]
    if let byteCount = row.byteCount {
      parts.append(QuickAccessImageOptimizer.formatByteCount(byteCount))
    }
    return parts.joined(separator: ", ")
  }
}
