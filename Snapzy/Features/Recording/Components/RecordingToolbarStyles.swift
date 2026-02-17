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
      .background(
        RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
          .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0))
      )
      .contentShape(RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius))
      .animation(ToolbarConstants.pressAnimation, value: configuration.isPressed)
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
      .background(
        RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
          .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0))
      )
      .contentShape(RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius))
      .animation(ToolbarConstants.pressAnimation, value: configuration.isPressed)
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

// MARK: - Stop Button Style (native monochrome, no red pill)

struct StopButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .regular))
      .foregroundColor(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
          .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0))
      )
      .contentShape(RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius))
      .animation(ToolbarConstants.pressAnimation, value: configuration.isPressed)
  }
}

// MARK: - Previews

#Preview("Record Button") {
  HStack {
    Button("Options") {}
      .buttonStyle(OptionsButtonStyle())
    Button("Record") {}
      .buttonStyle(RecordButtonStyle())
  }
  .padding()
  .background(.ultraThinMaterial)
  .clipShape(RoundedRectangle(cornerRadius: ToolbarConstants.toolbarCornerRadius))
}

#Preview("Toolbar Divider") {
  HStack {
    Text("Left")
    RecordingToolbarDivider()
    Text("Right")
  }
  .padding()
}
