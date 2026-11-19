//
//  QuickAccessOptimizeMenuView.swift
//  Snapzy
//
//  Optimize levels (`0.5x`, `1x`, `2x`…), saved presets and "Custom…" as a
//  native-style pop-up menu on clear Liquid Glass, opened with the current level
//  over the Optimize button.
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
    enum Kind: Equatable {
      case level(QuickAccessOptimizeLevel)
      case preset(QuickAccessOptimizePreset)
      case custom
    }

    let id: String
    let kind: Kind
    /// Draws a separator above the row, like a native menu group break.
    let startsGroup: Bool
    var byteCount: Int?
    var encodedData: Data?
    var isEstimating: Bool

    var level: QuickAccessOptimizeLevel? {
      if case let .level(level) = kind { return level }
      return nil
    }

    static func id(for level: QuickAccessOptimizeLevel) -> String { "level-\(level.fraction)" }
  }

  let itemID: UUID
  let originalByteCount: Int?
  let originalExtension: String
  @Published private(set) var rows: [Row]
  /// The level on disk, or nil when custom settings produced the file.
  let currentRowID: String?
  @Published var highlightedID: String?
  /// Drives the bubble in/out animation; the panel stays up until it has played.
  @Published var isShown = false

  var onChoose: ((Row) -> Void)?

  /// Explicit and nonisolated: the synthesized main-actor deinit hops through the
  /// back-deployed swift_task_deinitOnExecutor, which aborts on macOS 13-15 (#668).
  nonisolated deinit {}

  init(itemID: UUID, plan: QuickAccessOptimizePlan, presets: [QuickAccessOptimizePreset]) {
    self.itemID = itemID
    originalByteCount = plan.originalByteCount
    originalExtension = plan.fileExtension

    var rows = plan.levels.map { level in
      Row(
        id: Row.id(for: level),
        kind: .level(level),
        startsGroup: false,
        byteCount: level.isOriginal ? plan.originalByteCount : nil,
        encodedData: nil,
        isEstimating: !level.isOriginal
      )
    }
    rows += presets.enumerated().map { index, preset in
      Row(
        id: "preset-\(preset.id.uuidString)",
        kind: .preset(preset),
        startsGroup: index == 0,
        byteCount: nil,
        encodedData: nil,
        isEstimating: false
      )
    }
    rows.append(Row(id: "custom", kind: .custom, startsGroup: true, byteCount: nil, encodedData: nil, isEstimating: false))
    self.rows = rows

    currentRowID = plan.levels.first { $0.fraction == plan.currentFraction }.map(Row.id(for:))
    highlightedID = currentRowID ?? rows.last?.id
  }

  /// Row the menu opens on (and grows out of): the current level, else "Custom…".
  var anchorIndex: Int {
    rows.firstIndex { $0.id == (currentRowID ?? "custom") } ?? 0
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
    let currentIndex = rows.firstIndex { $0.id == highlightedID } ?? 0
    let nextIndex = min(max(currentIndex + offset, 0), rows.count - 1)
    highlightedID = rows[nextIndex].id
  }

  func chooseHighlighted() {
    guard let row = rows.first(where: { $0.id == highlightedID }) else { return }
    choose(row)
  }
}

struct QuickAccessOptimizeMenuView: View {
  @ObservedObject var model: QuickAccessOptimizeMenuModel

  // Geometry mirrors a native pop-up menu; the panel controller reads it to put
  // the current row right over the Optimize button.
  static let shadowPadding: CGFloat = 14
  static let inset: CGFloat = 4
  static let rowHeight: CGFloat = 19
  static let rowSpacing: CGFloat = 1
  /// Height of a group separator, hairline included.
  static let separatorHeight: CGFloat = 9

  /// Distance from the hosting view's top edge to the centre of row `index`.
  static func rowCenterOffset(at index: Int, in rows: [QuickAccessOptimizeMenuModel.Row]) -> CGFloat {
    let separators = rows.prefix(index + 1).filter(\.startsGroup).count
    return shadowPadding + inset
      + CGFloat(index) * (rowHeight + rowSpacing)
      + CGFloat(separators) * (separatorHeight + rowSpacing)
      + rowHeight / 2
  }

  static func contentHeight(for rows: [QuickAccessOptimizeMenuModel.Row]) -> CGFloat {
    let separators = rows.filter(\.startsGroup).count
    return 2 * (shadowPadding + inset)
      + CGFloat(rows.count) * rowHeight
      + CGFloat(max(rows.count - 1, 0)) * rowSpacing
      + CGFloat(separators) * (separatorHeight + rowSpacing)
  }

  /// On native glass the menu is concentric with its capsule rows (row radius +
  /// inset), so the ends read fully rounded; the classic menu keeps its 11pt corners.
  private var shape: RoundedRectangle {
    RoundedRectangle(
      cornerRadius: usesNativeGlass ? Self.rowHeight / 2 + Self.inset : 11,
      style: .continuous
    )
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.liquidGlassRenderMode) private var renderMode
  @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

  /// macOS 26 glass gets the borderless clear water-drop look; macOS 13–15 (or glass
  /// turned off) keeps the classic pop-up menu look with a light dim and hairline.
  private var usesNativeGlass: Bool {
    LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
  }

  /// The bubble grows out of (and shrinks back into) the current row, which sits
  /// over the Optimize button.
  private var bubbleAnchor: UnitPoint {
    let height = Self.contentHeight(for: model.rows)
    let offset = Self.rowCenterOffset(at: model.anchorIndex, in: model.rows)
    return UnitPoint(x: 0.5, y: offset / max(height, 1))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Self.rowSpacing) {
      ForEach(model.rows) { row in
        if row.startsGroup {
          Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, (Self.separatorHeight - 1) / 2)
            .accessibilityHidden(true)
        }
        QuickAccessOptimizeRowView(
          row: row,
          isHighlighted: row.id == model.highlightedID,
          isCurrent: row.id == model.currentRowID,
          originalByteCount: model.originalByteCount,
          originalExtension: model.originalExtension,
          usesNativeGlass: usesNativeGlass,
          onHover: { hovering in
            if hovering { model.highlightedID = row.id }
          },
          onChoose: { model.choose(row) }
        )
      }
    }
    // Every row takes the widest label's width, so the menu hugs its longest value.
    .fixedSize(horizontal: true, vertical: false)
    .padding(Self.inset)
    // Dark tint under the glass keeps labels legible over any screenshot. The shadow
    // rides on the dim layer: compositing the glass itself would stop it sampling
    // the backdrop.
    .background(
      shape.fill(Color.black.opacity(usesNativeGlass ? 0.5 : 0.18))
        .shadow(color: .black.opacity(usesNativeGlass ? 0.35 : 1), radius: 12, y: 5)
    )
    // Native: no drawn border, clear glass supplies its own refractive edge and
    // `interactive` lets it react to the pointer like system glass.
    .liquidGlassSurface(
      shape: shape,
      substrate: 0.3,
      layer: .backdrop,
      isInteractive: true,
      nativeVariant: .clear
    )
    .overlay {
      if !usesNativeGlass {
        shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
      }
    }
    .environment(\.colorScheme, .dark)
    .scaleEffect(model.isShown || reduceMotion ? 1 : 0.4, anchor: bubbleAnchor)
    .opacity(model.isShown ? 1 : 0)
    .padding(Self.shadowPadding)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.QuickAccess.optimizeMenuTitle)
  }
}

/// One row (`Nx` level, preset name or "Custom…"), laid out like a native menu item. The highlighted row (the current
/// level when the menu opens, then whatever the pointer or arrow keys land on) sits
/// on accent-tinted native glass. Pixel and byte sizes live in the tooltip.
private struct QuickAccessOptimizeRowView: View {
  let row: QuickAccessOptimizeMenuModel.Row
  let isHighlighted: Bool
  let isCurrent: Bool
  let originalByteCount: Int?
  let originalExtension: String
  let usesNativeGlass: Bool
  let onHover: (Bool) -> Void
  let onChoose: () -> Void

  private var shape: RoundedRectangle {
    RoundedRectangle(
      cornerRadius: usesNativeGlass ? QuickAccessOptimizeMenuView.rowHeight / 2 : 6,
      style: .continuous
    )
  }

  var body: some View {
    Button(action: onChoose) {
      Text(title)
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundColor(.white.opacity(isHighlighted ? 1 : 0.9))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(
          maxWidth: .infinity,
          minHeight: QuickAccessOptimizeMenuView.rowHeight,
          maxHeight: QuickAccessOptimizeMenuView.rowHeight,
          alignment: .leading
        )
        .liquidGlassSurface(
          shape: shape,
          isVisible: isHighlighted,
          substrate: 0,
          highlight: .none,
          glassTint: Color.accentColor.opacity(0.85)
        )
        .contentShape(shape)
    }
    .buttonStyle(.plain)
    .onHover(perform: onHover)
    .help(tooltip)
    .accessibilityLabel(tooltip)
    .accessibilityAddTraits(isCurrent ? .isSelected : [])
  }

  private var title: String {
    switch row.kind {
    case let .level(level): level.scaleLabel
    case let .preset(preset): preset.name
    case .custom: L10n.QuickAccess.optimizeCustom
    }
  }

  /// "Original (2x) · 2880×1800 · 1.2 MB · −62%", or a preset's settings.
  private var tooltip: String {
    let level: QuickAccessOptimizeLevel
    switch row.kind {
    case let .level(rowLevel):
      level = rowLevel
    case let .preset(preset):
      return "\(preset.name) · \(preset.settings.summary(originalExtension: originalExtension))"
    case .custom:
      return L10n.QuickAccess.optimizeCustomHelp
    }
    var parts = [QuickAccessOptimizeMenuFormatting.title(for: level), level.dimensionsLabel]
    if let byteCount = row.byteCount {
      parts.append(QuickAccessImageOptimizer.formatByteCount(byteCount))
      if let savings = QuickAccessOptimizeMenuFormatting.savingsLabel(
        byteCount: byteCount,
        originalByteCount: originalByteCount
      ) {
        parts.append(savings)
      }
    } else if row.isEstimating {
      parts.append(L10n.QuickAccess.optimizeEstimating)
    }
    return parts.joined(separator: " · ")
  }
}
