//
//  RecordingToolbarStyles.swift
//  Snapzy
//
//  Design constants and button styles for the recording toolbar
//  Styled to match Apple's native macOS recording toolbar aesthetic
//

import SwiftUI

// MARK: - Toolbar Constants

enum ToolbarConstants {
  static let iconButtonSize: CGFloat = 32
  static let iconSize: CGFloat = 15
  static let buttonCornerRadius: CGFloat = 6
  static let toolbarCornerRadius: CGFloat = 14
  static let dividerHeight: CGFloat = 20
  static let itemSpacing: CGFloat = 4
  static let groupSpacing: CGFloat = 2
  static let horizontalPadding: CGFloat = 10
  static let verticalPadding: CGFloat = 6
  static let hoverAnimation: Animation = .easeInOut(duration: 0.15)
  static let pressAnimation: Animation = .easeInOut(duration: 0.1)

  /// Shared hit/glass shape for every toolbar control, so chrome and hit target never drift.
  static var buttonShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: buttonCornerRadius, style: .continuous)
  }
}

// MARK: - Native Toolbar Button Style (for icon buttons)

struct NativeToolbarButtonStyle: ButtonStyle {
  var isActive: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.6 : 1.0)
      .animation(ToolbarConstants.pressAnimation, value: configuration.isPressed)
  }
}

// MARK: - Record Button Style (native text style, no colored background)

struct RecordButtonStyle: ButtonStyle {
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .regular))
      .foregroundColor(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .liquidGlassChrome(
        shape: ToolbarConstants.buttonShape,
        isVisible: configuration.isPressed,
        isActive: configuration.isPressed
      )
      .animation(LiquidGlassTokens.pressSpring, value: configuration.isPressed)
  }
}

// MARK: - Options Button Style (text with chevron, native look)

struct OptionsButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .regular))
      .foregroundColor(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .liquidGlassChrome(
        shape: ToolbarConstants.buttonShape,
        isVisible: configuration.isPressed,
        isActive: configuration.isPressed
      )
      .animation(LiquidGlassTokens.pressSpring, value: configuration.isPressed)
  }
}

// MARK: - Recording Toolbar Divider

struct RecordingToolbarDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.15))
      .frame(width: 1, height: ToolbarConstants.dividerHeight)
      .padding(.horizontal, 4)
  }
}

struct ToolbarIconButtonLabel: View {
  let systemName: String
  var iconSize: CGFloat = ToolbarConstants.iconSize
  let isHovered: Bool

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: iconSize, weight: .medium))
      .foregroundColor(.primary.opacity(isHovered ? 1.0 : 0.85))
      .frame(
        width: ToolbarConstants.iconButtonSize,
        height: ToolbarConstants.iconButtonSize
      )
      .liquidGlassChrome(shape: ToolbarConstants.buttonShape, isVisible: isHovered)
      .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
  }
}

// MARK: - Stop Button Style (native monochrome, no red pill)

struct StopButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .regular))
      .foregroundColor(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .liquidGlassChrome(
        shape: ToolbarConstants.buttonShape,
        isVisible: configuration.isPressed,
        isActive: configuration.isPressed
      )
      .animation(LiquidGlassTokens.pressSpring, value: configuration.isPressed)
  }
}

// MARK: - Previews

#Preview("Record Button") {
  HStack {
    Button(L10n.RecordingToolbar.options) {}
      .buttonStyle(OptionsButtonStyle())
    Button(L10n.RecordingToolbar.record) {}
      .buttonStyle(RecordButtonStyle())
  }
  .padding()
  .background(.ultraThinMaterial)
  .clipShape(RoundedRectangle(cornerRadius: ToolbarConstants.toolbarCornerRadius))
}

#Preview("Toolbar Divider") {
  HStack {
    Text(L10n.PreferencesQuickAccess.left)
    RecordingToolbarDivider()
    Text(L10n.PreferencesQuickAccess.right)
  }
  .padding()
}
