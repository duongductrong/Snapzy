//
//  RecordingToolbarStyles.swift
//  ClaudeShot
//
//  Design constants and button styles for the recording toolbar
//

import SwiftUI

// MARK: - Toolbar Constants

enum ToolbarConstants {
  static let iconButtonSize: CGFloat = 36
  static let iconSize: CGFloat = 20
  static let buttonCornerRadius: CGFloat = 8
  static let toolbarCornerRadius: CGFloat = 14
  static let dividerHeight: CGFloat = 20
  static let itemSpacing: CGFloat = 12
  static let horizontalPadding: CGFloat = 16
  static let verticalPadding: CGFloat = 12
  static let hoverAnimation: Animation = .easeInOut(duration: 0.15)
  static let pressAnimation: Animation = .easeInOut(duration: 0.1)
}

// MARK: - Record Button Style

struct RecordButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14, weight: .semibold))
      .foregroundColor(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
          .fill(Color.blue)
      )
      .opacity(configuration.isPressed ? 0.85 : 1.0)
      .animation(ToolbarConstants.pressAnimation, value: configuration.isPressed)
  }
}

// MARK: - Recording Toolbar Divider

struct RecordingToolbarDivider: View {
  var body: some View {
    Divider()
      .frame(height: ToolbarConstants.dividerHeight)
  }
}

// MARK: - Stop Button Style

struct StopButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14, weight: .semibold))
      .foregroundColor(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: ToolbarConstants.buttonCornerRadius)
          .fill(Color.red)
      )
      .opacity(configuration.isPressed ? 0.85 : 1.0)
      .animation(ToolbarConstants.pressAnimation, value: configuration.isPressed)
  }
}

// MARK: - Previews

#Preview("Record Button") {
  Button("Record") {}
    .buttonStyle(RecordButtonStyle())
    .padding()
}

#Preview("Toolbar Divider") {
  HStack {
    Text("Left")
    ToolbarDivider()
    Text("Right")
  }
  .padding()
}
