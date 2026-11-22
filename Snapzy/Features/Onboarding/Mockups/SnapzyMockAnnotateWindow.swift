//
//  SnapzyMockAnnotateWindow.swift
//  Snapzy
//
//  Faithful mock Annotate Window reflecting Snapzy's actual editor layout in sleek Dark Mode:
//  macOS window chrome with traffic lights, top annotation toolbar, central canvas with annotations,
//  and bottom status bar with zoom controls.
//

import SwiftUI

struct SnapzyMockAnnotateWindow: View {
  var onReplayFlow: (() -> Void)? = nil

  @State private var hoveredTool: String? = nil
  @State private var isReplayHovered: Bool = false
  @State private var isSaveHovered: Bool = false

  var body: some View {
    VStack(spacing: 0) {
      // 1. Top Window Toolbar
      windowToolbar

      Divider()
        .opacity(0.35)

      // 2. Central Editor Canvas
      canvasArea

      Divider()
        .opacity(0.35)

      // 3. Bottom Status Bar
      bottomStatusBar
    }
    .frame(width: 480, height: 310)
    .background(Color(red: 0.12, green: 0.12, blue: 0.14))
    .clipShape(Radius.rect(Radius.card))
    .overlay(
      Radius.rect(Radius.card)
        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.42), radius: 28, x: 0, y: 14)
    .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 2)
  }

  // MARK: - Window Toolbar

  private var windowToolbar: some View {
    HStack(spacing: 5) {
      SnapzyMockTrafficLights(size: 9.5, spacing: 6)
        .padding(.leading, 4)

      divider

      // Left Capture Tools: Crop & Sidebar
      HStack(spacing: 2.5) {
        toolbarTool("crop", tooltip: "Crop")
        toolbarTool("sidebar.left", tooltip: "Sidebar")
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
        toolbarTool("arrow.uturn.forward", tooltip: "Redo", isEnabled: false)
      }

      Spacer(minLength: 6)

      // Replay Action
      if let replay = onReplayFlow {
        Button(action: replay) {
          HStack(spacing: 3) {
            Image(systemName: "arrow.counterclockwise")
              .font(.system(size: 8.5, weight: .bold))
            Text("Replay")
              .font(.system(size: 9.5, weight: .semibold))
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
          }
          .foregroundStyle(Color.white.opacity(0.85))
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .background(
            Radius.rect(Radius.controlXS)
              .fill(isReplayHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.08))
          )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { h in isReplayHovered = h }
      }

      // Save / Export button
      Button(action: {
        onReplayFlow?()
      }) {
        HStack(spacing: 3.5) {
          Image(systemName: "arrow.down.to.line")
            .font(.system(size: 9, weight: .bold))
          Text("Save")
            .font(.system(size: 9.5, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(
          Radius.rect(Radius.controlXS)
            .fill(isSaveHovered ? SnapzyMockPalette.macBlue.opacity(0.92) : SnapzyMockPalette.macBlue)
        )
        .fixedSize()
      }
      .buttonStyle(.plain)
      .onHover { h in isSaveHovered = h }
    }
    .padding(.horizontal, 10)
    .frame(height: 38)
    .background(Color(red: 0.16, green: 0.16, blue: 0.18))
  }

  private func toolbarTool(_ icon: String, tooltip: String, isSelected: Bool = false, isEnabled: Bool = true) -> some View {
    Image(systemName: icon)
      .font(.system(size: 10.5, weight: .medium))
      .foregroundStyle(isSelected ? Color.white : (isEnabled ? Color.white.opacity(0.70) : Color.white.opacity(0.30)))
      .frame(width: 21, height: 21)
      .background(
        Radius.rect(Radius.ornament)
          .fill(isSelected ? SnapzyMockPalette.macBlue : (hoveredTool == icon ? Color.white.opacity(0.08) : Color.clear))
      )
      .onHover { h in
        if isEnabled { hoveredTool = h ? icon : nil }
      }
  }

  private var divider: some View {
    Rectangle()
      .fill(Color.white.opacity(0.14))
      .frame(width: 0.5, height: 16)
      .padding(.horizontal, 1.5)
  }

  // MARK: - Central Canvas Area

  private var canvasArea: some View {
    ZStack {
      // Dark matte studio canvas
      Color(red: 0.09, green: 0.09, blue: 0.10)

      // Captured Note Document Card with shadow
      ZStack(alignment: .topLeading) {
        Color.white

        VStack(alignment: .leading, spacing: 6) {
          Text("At the top, he sat in the keeper’s chair—the one he’d occupied during countless storms and ordinary mornings. The brass was worn smooth from his hands.")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.17))
            .lineSpacing(3)

          Text("Aug 18, 2026. Light burning true. Sea calm. Work complete.")
            .font(.system(size: 10.5, weight: .regular))
            .italic()
            .foregroundStyle(Color(red: 0.25, green: 0.25, blue: 0.28))
        }
        .padding(14)

        // Vector Arrow Annotation
        Image(systemName: "arrow.up.right")
          .font(.system(size: 36, weight: .bold))
          .foregroundStyle(Color(red: 0.98, green: 0.28, blue: 0.28))
          .shadow(color: Color.black.opacity(0.30), radius: 2.5, y: 1)
          .offset(x: 180, y: 36)

        // Vector Rectangle Box
        Radius.rect(Radius.ornament)
          .strokeBorder(Color(red: 0.98, green: 0.28, blue: 0.28), lineWidth: 2)
          .frame(width: 130, height: 32)
          .offset(x: 14, y: 22)
      }
      .frame(width: 360, height: 160)
      .clipShape(Radius.rect(Radius.controlXS))
      .overlay(
        Radius.rect(Radius.controlXS)
          .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
      )
      .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 7)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Bottom Status Bar

  private var bottomStatusBar: some View {
    HStack(spacing: 8) {
      Text("344 × 184 px")
        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.55))

      Spacer()

      HStack(spacing: 4) {
        Image(systemName: "minus")
          .font(.system(size: 8))
        Text("100%")
          .font(.system(size: 9.5, weight: .medium))
        Image(systemName: "plus")
          .font(.system(size: 8))
      }
      .foregroundStyle(Color.white.opacity(0.65))
      .padding(.horizontal, 6)
      .padding(.vertical, 2.5)
      .background(
        Radius.rect(Radius.ornament)
          .fill(Color.white.opacity(0.08))
      )
    }
    .padding(.horizontal, 12)
    .frame(height: 24)
    .background(Color(red: 0.14, green: 0.14, blue: 0.16))
  }
}
