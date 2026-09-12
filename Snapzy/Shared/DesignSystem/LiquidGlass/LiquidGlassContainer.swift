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
  func liquidGlassGroup(spacing: CGFloat? = nil) -> some View {
    modifier(LiquidGlassGroupModifier(spacing: spacing))
  }

  /// Gives a glass surface a morphing identity so it animates between sibling positions
  /// (a sliding segmented indicator, for example) instead of cross-fading.
  func liquidGlassID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
    modifier(LiquidGlassIDModifier(id: id, namespace: namespace))
  }
}

private struct LiquidGlassGroupModifier: ViewModifier {
  let spacing: CGFloat?
  @Environment(\.liquidGlassRenderMode) private var renderMode
  @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

  private var usesNativeGlass: Bool {
    LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
  }

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *), usesNativeGlass {
      GlassEffectContainer(spacing: spacing) { content }
    } else {
      content
    }
  }
}

private struct LiquidGlassIDModifier<ID: Hashable & Sendable>: ViewModifier {
  let id: ID
  let namespace: Namespace.ID
  @Environment(\.liquidGlassRenderMode) private var renderMode
  @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

  private var usesNativeGlass: Bool {
    LiquidGlassCapabilities.usesNativeGlass(for: renderMode, userEnabled: isLiquidGlassEnabled)
  }

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 26.0, *), usesNativeGlass {
      content.glassEffectID(id, in: namespace)
    } else {
      content
    }
  }
}
