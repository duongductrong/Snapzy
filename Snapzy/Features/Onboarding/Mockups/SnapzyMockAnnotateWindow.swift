//
//  SnapzyMockAnnotateWindow.swift
//  Snapzy
//
//  Faithful mock Annotate Window reflecting Snapzy's actual editor layout:
//  macOS window chrome, top annotation toolbar, central canvas with annotations,
//  and bottom status bar with zoom controls.
//

import SwiftUI

struct SnapzyMockAnnotateWindow: View {
  var onReplayFlow: (() -> Void)? = nil

  var body: some View {
    VStack(spacing: 0) {
      // 1. Top Window Toolbar
      windowToolbar

      Rectangle()
        .fill(Color.black.opacity(0.10))
        .frame(height: 0.5)

      // 2. Central Editor Canvas
      canvasArea

      Rectangle()
        .fill(Color.black.opacity(0.08))
        .frame(height: 0.5)

      // 3. Bottom Status Bar
      bottomStatusBar
    }
    .background(Color(red: 0.94, green: 0.94, blue: 0.95))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.28), radius: 28, x: 0, y: 14)
    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
  }

  // MARK: - Window Toolbar

  private var windowToolbar: some View {
    HStack(spacing: 5) {
      // Traffic Lights
      HStack(spacing: 6) {
        Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.33)).frame(width: 9.5, height: 9.5)
        Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 9.5, height: 9.5)
        Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 9.5, height: 9.5)
      }
      .padding(.leading, 2)

      divider

      // Left Capture Tools: Crop & Sidebar
      HStack(spacing: 2.5) {
        toolbarTool("crop", tooltip: "Crop")
        toolbarTool("rectangle.on.rectangle", tooltip: "Sidebar")
      }

      divider

      // Main Annotation Tools
      HStack(spacing: 2.5) {
        toolbarTool("arrow.up.right", tooltip: "Arrow", isSelected: true)
        toolbarTool("rectangle", tooltip: "Rectangle")
        toolbarTool("1.circle.fill", tooltip: "Counter")
        toolbarTool("checkerboard.rectangle", tooltip: "Blur")
        toolbarTool("textformat", tooltip: "Text")
        toolbarTool("pencil.tip", tooltip: "Pen")
      }

      divider

      // Undo / Redo
      HStack(spacing: 2.5) {
        toolbarTool("arrow.uturn.backward", tooltip: "Undo")
        toolbarTool("arrow.uturn.forward", tooltip: "Redo")
      }

      Spacer(minLength: 6)

      // Replay / Done Actions
      if let replay = onReplayFlow {
        Button(action: replay) {
          HStack(spacing: 3) {
            Image(systemName: "arrow.counterclockwise")
              .font(.system(size: 8.5, weight: .bold))
            Text("Replay")
              .font(.system(size: 9, weight: .semibold))
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
          }
          .foregroundStyle(Color.black.opacity(0.72))
          .padding(.horizontal, 6)
          .padding(.vertical, 3.5)
          .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(Color.black.opacity(0.06))
          )
        }
        .buttonStyle(.plain)
        .fixedSize()
      }

      // Save / Export button
      HStack(spacing: 3.5) {
        Image(systemName: "arrow.down.to.line")
          .font(.system(size: 9, weight: .bold))
        Text("Save")
          .font(.system(size: 9.5, weight: .semibold))
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .foregroundStyle(Color.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(Color.accentColor)
      )
      .fixedSize()
    }
    .padding(.horizontal, 10)
    .frame(height: 38)
    .background(Color(white: 0.98))
  }

  private func toolbarTool(_ icon: String, tooltip: String, isSelected: Bool = false) -> some View {
    Image(systemName: icon)
      .font(.system(size: 10.5, weight: .medium))
      .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.70))
      .frame(width: 21, height: 21)
      .background(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(isSelected ? Color.accentColor : Color.clear)
      )
  }

  private var divider: some View {
    Rectangle()
      .fill(Color.black.opacity(0.10))
      .frame(width: 0.5, height: 15)
  }

  // MARK: - Central Canvas Area

  private var canvasArea: some View {
    ZStack {
      // Checkerboard or matte background
      Color(red: 0.88, green: 0.89, blue: 0.91)

      // Captured Image Card with shadow
      ZStack(alignment: .topLeading) {
        Color.white

        VStack(alignment: .leading, spacing: 6) {
          Text("At the top, he sat in the keeper’s chair—the one he’d occupied during countless storms and ordinary mornings. The brass was worn smooth from his hands.")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.17))
            .lineSpacing(3)

          Text("*Aug 18, 2026. Light burning true. Sea calm. Work complete.*")
            .font(.system(size: 10.5, weight: .regular))
            .italic()
            .foregroundStyle(Color(red: 0.25, green: 0.25, blue: 0.28))
        }
        .padding(14)

        // Vector Arrow Annotation
        Image(systemName: "arrow.up.right")
          .font(.system(size: 36, weight: .bold))
          .foregroundStyle(Color(red: 0.95, green: 0.20, blue: 0.20))
          .shadow(color: Color.black.opacity(0.20), radius: 2, y: 1)
          .offset(x: 180, y: 36)

        // Vector Rectangle Box
        RoundedRectangle(cornerRadius: 3)
          .strokeBorder(Color(red: 0.95, green: 0.20, blue: 0.20), lineWidth: 2)
          .frame(width: 130, height: 32)
          .offset(x: 14, y: 22)
      }
      .frame(width: 360, height: 160)
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Bottom Status Bar

  private var bottomStatusBar: some View {
    HStack(spacing: 8) {
      Text("420 × 160 px")
        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.black.opacity(0.55))

      Spacer()

      HStack(spacing: 4) {
        Image(systemName: "minus")
          .font(.system(size: 8))
        Text("100%")
          .font(.system(size: 9.5, weight: .medium))
        Image(systemName: "plus")
          .font(.system(size: 8))
      }
      .foregroundStyle(Color.black.opacity(0.60))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 3.5)
          .fill(Color.black.opacity(0.04))
      )
    }
    .padding(.horizontal, 12)
    .frame(height: 24)
    .background(Color(white: 0.98))
  }
}
