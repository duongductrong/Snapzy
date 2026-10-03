//
//  LiquidGlassSegmentedControl.swift
//  Snapzy
//
//  Sliding-indicator Liquid Glass segmented control with matched geometry and spring physics.
//

import SwiftUI

struct LiquidGlassSegmentedControl<Item: Hashable, Content: View>: View {
  let items: [Item]
  @Binding var selection: Item
  /// Tint applied to the selected segment. Pass `nil` for a neutral, translucent active state.
  var activeGlassTint: Color? = .accentColor
  /// Optional total control height, including the inset around the selected segment. Bottom-bar
  /// callers provide `ControlMetrics.bottomBarControl` to align with the action buttons.
  var controlHeight: CGFloat? = nil
  @ViewBuilder let label: (Item) -> Content

  @Namespace private var segmentNamespace
  @State private var hoveredItem: Item? = nil
  @Environment(\.liquidGlassRenderMode) private var renderMode
  @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

  private var usesNativeGlass: Bool {
    LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
  }

  var body: some View {
    HStack(spacing: 2) {
      ForEach(items, id: \.self) { item in
        let isSelected = selection == item
        let isHovered = hoveredItem == item

        Button {
          withAnimation(
            isQuietSelection ? LiquidGlassTokens.settleSpring : LiquidGlassTokens.hoverSpring
          ) {
            selection = item
          }
        } label: {
          label(item)
            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(
              isSelected
                ? LiquidGlassTokens.ink(onTint: activeGlassTint)
                : (isHovered ? LiquidGlassTokens.inkBody : LiquidGlassTokens.inkMuted)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(height: controlHeight.map { max(0, $0 - trackInset * 2) })
            .liquidGlassSurface(
              shape: Capsule(style: .continuous),
              isVisible: isSelected,
              substrate: isQuietSelection
                ? LiquidGlassTokens.controlSubstrateResting
                : LiquidGlassTokens.controlSubstrateHover,
              tint: isQuietSelection ? 0.06 : 0.14,
              highlight: .none,
              withRimLighting: isSelected && !usesNativeGlass,
              isInteractive: true,
              glassTint: activeGlassTint
            )
            .liquidGlassID(item, in: segmentNamespace)
            .contentShape(Capsule(style: .continuous))
            .shadow(
              color: !usesNativeGlass && isSelected
                ? Color.black.opacity(isQuietSelection ? 0.08 : 0.18)
                : .clear,
              radius: isQuietSelection ? 1 : 2,
              y: 1
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .background {
          if !isSelected, isHovered {
            Capsule(style: .continuous)
              .fill(LiquidGlassTokens.veilFill.opacity(isQuietSelection ? 0.04 : 0.06))
          }
        }
        .onHover { hovering in
          withAnimation(LiquidGlassTokens.hoverSpring) {
            hoveredItem = hovering ? item : nil
          }
        }
      }
    }
    .padding(trackInset)
    .frame(height: controlHeight)
    .liquidGlassGroup(spacing: 2)
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: isQuietSelection
        ? LiquidGlassTokens.controlSubstrateResting
        : LiquidGlassTokens.baseDarkness,
      tint: isQuietSelection ? 0.01 : 0.02,
      highlight: .none,
      withRimLighting: !usesNativeGlass
    )
    .shadow(
      color: Color.black.opacity(isQuietSelection ? 0.08 : 0.15),
      radius: isQuietSelection ? 4 : 6,
      y: isQuietSelection ? 2 : 3
    )
  }

  private var isQuietSelection: Bool {
    activeGlassTint == nil
  }

  private var trackInset: CGFloat {
    isQuietSelection ? 2 : 3
  }
}
