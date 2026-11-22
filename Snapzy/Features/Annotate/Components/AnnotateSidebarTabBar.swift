//
//  AnnotateSidebarTabBar.swift
//  Snapzy
//
//  Top-of-sidebar switch between canvas styling and image adjustments. A Liquid Glass track
//  whose active pill is its own glass surface: on macOS 26+ both are native `.glassEffect`s in
//  one `GlassEffectContainer`, and the pill morphs between tabs through `glassEffectID`. On
//  macOS 13–15 the design system's composite glass stands in, and the pill slides via the
//  shared selection animation.
//

import SwiftUI

/// Top-level tabs of the Annotate sidebar: canvas styling vs. image adjustments.
nonisolated enum AnnotateSidebarTab: Hashable, CaseIterable, Sendable {
  case style
  case adjust

  var title: String {
    switch self {
    case .style: return L10n.Common.style
    case .adjust: return L10n.AnnotateAdjust.section
    }
  }
}

struct AnnotateSidebarTabBar: View {
  @Binding var selection: AnnotateSidebarTab

  @Namespace private var glassNamespace
  @State private var hoveredTab: AnnotateSidebarTab?
  @Environment(\.liquidGlassRenderMode) private var renderMode
  @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

  /// Gap between the track edge and the active pill.
  private static let trackInset: CGFloat = 3
  private static let segmentSpacing: CGFloat = 2
  /// Matches the toolbar's capsule action buttons (12pt medium, 7pt vertical padding).
  private static let labelFontSize: CGFloat = 12
  private static let actionButtonVerticalPadding: CGFloat = 7
  private static let selectionSpring = Animation.spring(response: 0.36, dampingFraction: 0.78)

  private var usesNativeGlass: Bool {
    LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
  }

  var body: some View {
    HStack(spacing: Self.segmentSpacing) {
      ForEach(AnnotateSidebarTab.allCases, id: \.self) { tab in
        segment(tab)
      }
    }
    .padding(Self.trackInset)
    .liquidGlassGroup(spacing: Self.segmentSpacing)
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: LiquidGlassTokens.controlSubstrateResting,
      tint: 0.01,
      highlight: .none,
      withRimLighting: !usesNativeGlass
    )
    .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)
  }

  private func segment(_ tab: AnnotateSidebarTab) -> some View {
    let isSelected = selection == tab
    let isHovered = hoveredTab == tab

    return Button {
      guard selection != tab else { return }
      withAnimation(Self.selectionSpring) {
        selection = tab
      }
    } label: {
      Text(tab.title)
        .font(.system(size: Self.labelFontSize, weight: isSelected ? .semibold : .medium))
        .foregroundStyle(
          isSelected
            ? LiquidGlassTokens.inkPrimary
            : (isHovered ? LiquidGlassTokens.inkBody : LiquidGlassTokens.inkMuted)
        )
        .lineLimit(1)
        .padding(.vertical, Self.actionButtonVerticalPadding - Self.trackInset)
        .frame(maxWidth: .infinity)
        .background {
          if !isSelected, isHovered {
            Capsule(style: .continuous)
              .fill(LiquidGlassTokens.veilFill.opacity(0.06))
          }
        }
        // Every segment carries the pill surface, visible only when selected, so the native
        // container morphs the glass from one tab to the other instead of cross-fading.
        .liquidGlassSurface(
          shape: Capsule(style: .continuous),
          isVisible: isSelected,
          substrate: LiquidGlassTokens.controlSubstrateHover,
          tint: 0.08,
          highlight: .none,
          withRimLighting: isSelected && !usesNativeGlass,
          isInteractive: true
        )
        .liquidGlassID(tab, in: glassNamespace)
        .shadow(
          color: !usesNativeGlass && isSelected ? Color.black.opacity(0.14) : .clear,
          radius: 2,
          y: 1
        )
        .contentShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) {
        hoveredTab = hovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
      }
    }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
