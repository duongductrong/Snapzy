//
//  SnapzyMockDesktopCanvas.swift
//  Snapzy
//
//  Faithful macOS Desktop canvas with studio ambient wallpaper, monospaced watermark grid,
//  and authentic Apple Silicon menu bar with camera notch.
//

import SwiftUI

/// Which application the simulated desktop is dressed as.
enum SnapzyMockApp: Equatable {
  case notes
  case finder

  var menuTitle: String {
    switch self {
    case .notes: return "Notes"
    case .finder: return "Finder"
    }
  }

  var menus: [String] {
    switch self {
    case .notes: return ["File", "Edit", "Format", "View", "Window", "Help"]
    case .finder: return ["File", "Edit", "View", "Go", "Window", "Help"]
    }
  }

  var watermarks: [SnapzyWatermark] {
    switch self {
    case .notes:
      return [
        .init(text: "t For style"),
        .init(text: "Snapzy"),
        .init(text: "4 . . . 1 . . . 1", size: 30, weight: .heavy, opacity: 0.040),
        .init(text: "Notes"),
        .init(text: "Studio", opacity: 0.040),
        .init(text: "Mac 26"),
      ]
    case .finder:
      return [
        .init(text: "t For style"),
        .init(text: "Finder"),
        .init(text: "Snapzy", size: 30, weight: .heavy, opacity: 0.040),
        .init(text: "Mac 26"),
        .init(text: "Studio", opacity: 0.040),
        .init(text: "Capture", opacity: 0.040),
      ]
    }
  }
}

struct SnapzyWatermark {
  var text: String
  var size: CGFloat = 36
  var weight: Font.Weight = .black
  var opacity: Double = 0.045
}

// MARK: - Equatable Wallpaper

struct SnapzyMockWallpaper: View, Equatable {
  var app: SnapzyMockApp = .notes

  var body: some View {
    ZStack {
      // Soft studio ambient gradient wallpaper
      LinearGradient(
        colors: [
          Color(red: 0.945, green: 0.950, blue: 0.960),
          Color(red: 0.885, green: 0.895, blue: 0.915),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      GeometryReader { proxy in
        VStack(alignment: .leading, spacing: 38) {
          ForEach(0..<8) { row in
            HStack(spacing: 44) {
              ForEach(0..<6) { col in
                let mark = app.watermarks[(row * 3 + col) % 6]
                Text(mark.text)
                  .font(.system(size: mark.size, weight: mark.weight, design: .monospaced))
                  .foregroundStyle(Color.black.opacity(mark.opacity))
                  .rotationEffect(.degrees(-14))
              }
            }
          }
        }
        .frame(width: proxy.size.width * 1.8, height: proxy.size.height * 1.8)
        .offset(x: -80, y: -60)
      }
      .clipped()
    }
    .compositingGroup()
  }
}

// MARK: - Equatable Menu Bar

struct SnapzyMockMenuBar: View, Equatable {
  var app: SnapzyMockApp = .notes

  var body: some View {
    GeometryReader { proxy in
      let visibleWidth = proxy.size.width
      let notchShift = max(100, visibleWidth * 0.21)
      let notchCenterX = (visibleWidth / 2) + notchShift
      let notchWidth: CGFloat = 98
      let notchRightEdge = notchCenterX + (notchWidth / 2)

      ZStack(alignment: .topLeading) {
        // Translucent menu bar strip
        Rectangle()
          .fill(Color.white.opacity(0.84))
          .frame(height: 28)
          .overlay(
            Rectangle()
              .fill(Color.black.opacity(0.06))
              .frame(height: 0.5),
            alignment: .bottom
          )

        // 1. Left Menu Items ( + App Title + standard menus)
        HStack(spacing: 11) {
          Image(systemName: "apple.logo")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.90))

          Text(app.menuTitle)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.92))

          ForEach(app.menus, id: \.self) { menu in
            Text(menu)
          }
        }
        .font(.system(size: 11.5, weight: .regular))
        .foregroundStyle(Color.black.opacity(0.82))
        .padding(.leading, 18)
        .frame(height: 28, alignment: .leading)

        // 2. Camera Notch (Shifted right to virtual display center)
        cameraNotch
          .position(x: notchCenterX, y: 9)

        // 3. Right Status Bar Items
        HStack(spacing: 11) {
          // Snapzy Camera Status Icon in subtle capsule
          HStack(spacing: 3) {
            Image(systemName: "camera.viewfinder")
              .font(.system(size: 9.5, weight: .semibold))
              .foregroundStyle(Color.black.opacity(0.85))
          }
          .padding(.horizontal, 4)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
              .fill(Color.black.opacity(0.07))
          )

          Image(systemName: "switch.2")
            .font(.system(size: 10.5))

          Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 10.5))

          Image(systemName: "wifi")
            .font(.system(size: 10.5, weight: .medium))

          HStack(spacing: 3) {
            Text("100%")
              .font(.system(size: 9.5, weight: .medium))
            Image(systemName: "battery.100")
              .font(.system(size: 11.5))
          }

          Text("9:41 AM")
            .font(.system(size: 10.5, weight: .medium))
        }
        .font(.system(size: 10.5, weight: .regular))
        .foregroundStyle(Color.black.opacity(0.82))
        .fixedSize()
        .frame(height: 28, alignment: .leading)
        .offset(x: notchRightEdge + 24)
      }
    }
    .frame(height: 28)
  }

  private var cameraNotch: some View {
    ZStack {
      SnapzyUnevenRoundedRectangle(
        cornerRadii: SnapzyCornerRadii(
          topLeading: 0,
          bottomLeading: 6,
          bottomTrailing: 6,
          topTrailing: 0
        )
      )
      .fill(Color(red: 0.05, green: 0.055, blue: 0.065))
      .frame(width: 98, height: 18)

      HStack(spacing: 5) {
        Circle()
          .fill(Color(white: 0.16))
          .frame(width: 3.5, height: 3.5)
          .overlay(
            Circle()
              .fill(Color(red: 0.2, green: 0.35, blue: 0.6).opacity(0.5))
              .frame(width: 1.5, height: 1.5)
          )
      }
    }
    .frame(width: 98, height: 18)
  }
}

// MARK: - Backward-compatible Wrapper

struct SnapzyMockDesktopCanvas: View {
  var app: SnapzyMockApp = .notes

  var body: some View {
    ZStack(alignment: .top) {
      SnapzyMockWallpaper(app: app).equatable()
      SnapzyMockMenuBar(app: app).equatable()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
