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
          withAnimation(LiquidGlassTokens.hoverSpring) {
            selection = item
          }
        } label: {
          label(item)
            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
            // The selected pill is accent-tinted glass, so its label resolves against the tint;
            // unselected labels have no surface and follow the app appearance.
            .foregroundStyle(
              isSelected
                ? LiquidGlassTokens.inkOnAccent
                : (isHovered ? LiquidGlassTokens.inkBody : LiquidGlassTokens.inkMuted)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .liquidGlassSurface(
              shape: Capsule(style: .continuous),
              isVisible: isSelected,
              substrate: LiquidGlassTokens.controlSubstrateHover,
              tint: 0.14,
              highlight: .none,
              withRimLighting: isSelected && !usesNativeGlass,
              isInteractive: true,
              glassTint: .accentColor
            )
            .liquidGlassID(item, in: segmentNamespace)
            .contentShape(Capsule(style: .continuous))
            .shadow(
              color: !usesNativeGlass && isSelected ? Color.black.opacity(0.18) : .clear,
              radius: 2,
              y: 1
            )
        }
        .buttonStyle(.plain)
        .background {
          if !isSelected, isHovered {
            Capsule(style: .continuous)
              .fill(LiquidGlassTokens.veilFill.opacity(0.06))
          }
        }
        .onHover { hovering in
          withAnimation(LiquidGlassTokens.hoverSpring) {
            hoveredItem = hovering ? item : nil
          }
        }
      }
    }
    .padding(3)
    .liquidGlassGroup(spacing: 2)
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: LiquidGlassTokens.baseDarkness,
      tint: 0.02,
      highlight: .none,
      withRimLighting: !usesNativeGlass
    )
    .shadow(color: Color.black.opacity(0.15), radius: 6, y: 3)
  }
}
