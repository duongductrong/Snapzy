//
//  LiquidGlassContainer.swift
//  Snapzy
//
//  Grouping container so sibling glass surfaces sample once and merge optically on macOS 26+.
//

import SwiftUI

extension View {
  /// Groups sibling Liquid Glass surfaces into a single effect container.
  ///
  /// On macOS 26+ this lets adjacent surfaces blend into one another when they come within
  /// `spacing`, and lets the system evaluate the glass in one pass instead of once per control.
  /// On macOS 13–15 it is a passthrough — the legacy composite has nothing to merge.
  @ViewBuilder
  func liquidGlassGroup(spacing: CGFloat? = nil) -> some View {
    if #available(macOS 26.0, *), !LiquidGlassCapabilities.forcesLegacyGlass {
      GlassEffectContainer(spacing: spacing) { self }
    } else {
      self
    }
  }

  /// Gives a glass surface a morphing identity so it animates between sibling positions
  /// (a sliding segmented indicator, for example) instead of cross-fading.
  @ViewBuilder
  func liquidGlassID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
    if #available(macOS 26.0, *), !LiquidGlassCapabilities.forcesLegacyGlass {
      glassEffectID(id, in: namespace)
    } else {
      self
    }
  }
}
