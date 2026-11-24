//
//  AutomationCanvasTheme.swift
//  Snapzy
//
//  Colors and the floating surface of the canvas editor. Everything maps to
//  AppKit semantic colors and system materials so the canvas follows light/dark
//  mode, the accent color, Reduce Transparency and Increase Contrast the way the
//  rest of macOS does. Everything floating over the canvas (bars, inspector,
//  step picker, minimap, link actions) shares one Liquid Glass surface.
//

import AppKit
import SwiftUI

enum AutomationCanvasTheme {
  static let backdrop = Color(nsColor: .underPageBackgroundColor)
  static let card = Color(nsColor: .controlBackgroundColor)
  static let hairline = Color(nsColor: .separatorColor)
  static let link = Color(nsColor: .tertiaryLabelColor)
  static let gridDot = Color(nsColor: .quaternaryLabelColor)
  static let port = Color(nsColor: .secondaryLabelColor)
  static let shadow = Color.black.opacity(0.12)
  static let otherwise = Color(nsColor: .systemOrange)

  /// Header beside the traffic lights, sized like macOS 26 toolbar item groups:
  /// the group's height, each button's square, and the symbol size.
  static let headerHeight: CGFloat = 36
  static let headerButtonSize: CGFloat = 34
  static let headerIconSize: CGFloat = 15
  /// Gap between a button's hover highlight and the group's edge.
  static let headerHoverInset: CGFloat = 2

  /// Spring used for every structural change (add, remove, link, tidy up).
  static let spring = Animation.spring(response: 0.32, dampingFraction: 0.9)
}

extension View {
  /// The surface of everything floating over the canvas: native Liquid Glass on
  /// macOS 26+ (when Liquid Glass is on in Preferences), otherwise a system
  /// material with a hairline and a soft shadow. `interactive` gives button-like
  /// surfaces the glass press and hover response.
  func canvasFloating<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
    modifier(AutomationCanvasFloatingSurface(shape: shape, interactive: interactive))
  }
}

private struct AutomationCanvasFloatingSurface<S: InsettableShape>: ViewModifier {
  let shape: S
  let interactive: Bool
  @AppStorage(PreferencesKeys.useLiquidGlass) private var isLiquidGlassEnabled = true

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *), isLiquidGlassEnabled {
      content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    } else {
      content
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(AutomationCanvasTheme.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
    }
  }
}

/// Borderless icon button of the floating bars, with the hover highlight of a
/// toolbar button.
struct AutomationCanvasBarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    AutomationCanvasBarButtonBody(configuration: configuration)
  }
}

private struct AutomationCanvasBarButtonBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  var body: some View {
    configuration.label
      .font(.system(size: 13, weight: .regular))
      .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.6))
      .frame(minWidth: 28, minHeight: 26)
      .padding(.horizontal, 2)
      .background(
        RoundedRectangle(cornerRadius: Radius.controlXS, style: .continuous)
          .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (isHovered && isEnabled ? 0.07 : 0)))
      )
      .contentShape(Rectangle())
      .onHover { isHovered = $0 }
  }
}
