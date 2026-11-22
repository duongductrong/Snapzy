//
//  SnapzyMockDesktopCanvas.swift
//  Snapzy
//
//  Faithful macOS desktop canvas: studio ambient wallpaper with per-step monospaced watermark
//  grid and authentic Apple Silicon menu bar with flush camera notch.
//

import SwiftUI

// MARK: - Mock Scene

/// Which application the simulated desktop is dressed as.
enum SnapzyMockApp: String, Equatable {
  case notes
  case finder
  case settings

  var menuTitle: String {
    switch self {
    case .notes: "Notes"
    case .finder: "Finder"
    case .settings: "System Settings"
    }
  }

  var menus: [String] {
    switch self {
    case .notes: ["File", "Edit", "View", "Window", "Help"]
    case .finder: ["File", "Edit", "View", "Go", "Help"]
    case .settings: ["Edit", "View", "Window", "Help"]
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
    case .settings:
      return [
        .init(text: "Settings"),
        .init(text: "Shortcuts"),
        .init(text: "Snapzy", size: 30, weight: .heavy, opacity: 0.040),
        .init(text: "Keyboard"),
        .init(text: "macOS 26", opacity: 0.040),
        .init(text: "Screenshots", opacity: 0.040),
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

// MARK: - Palette

/// The mock desktop's colours.
///
/// These are the only literal colours in the onboarding feature, on purpose. Every app token
/// describes dark glass on a dark backdrop; the stage depicts the opposite — a lit macOS desktop —
/// so there is nothing in the ramp to borrow. Gathering them here keeps "the fake desktop" one
/// decision instead of forty scattered `Color(red:)` calls, and leaves the rest of the feature
/// clean.
enum SnapzyMockPalette {
  /// Text and rules drawn on the light desktop surfaces.
  static let ink = Color(red: 0.12, green: 0.13, blue: 0.15)
  static let inkSecondary = Color(red: 0.34, green: 0.36, blue: 0.40)
  static let inkTertiary = Color(red: 0.55, green: 0.57, blue: 0.61)
  /// Window bodies and the menu bar.
  static let chrome = Color(red: 0.985, green: 0.987, blue: 0.992)
  static let chromeBar = Color(red: 0.94, green: 0.945, blue: 0.955)
  static let chromeEdge = Color(red: 0.80, green: 0.81, blue: 0.83)
  static let chromeRule = Color.black.opacity(0.08)
  /// The notch and the display bezel it sits in.
  static let bezel = Color(red: 0.04, green: 0.045, blue: 0.055)
  /// Traffic lights, kept at their real macOS system hues (`#FF5F57`, `#FEBC2E`, `#28C840`).
  static let trafficRed = Color(red: 1.00, green: 0.373, blue: 0.341)
  static let trafficYellow = Color(red: 0.996, green: 0.737, blue: 0.180)
  static let trafficGreen = Color(red: 0.157, green: 0.784, blue: 0.251)
  /// Native macOS accent hues used inside simulated Apple apps (Finder, System Settings, Notes).
  static let macBlue = Color(red: 0.00, green: 0.478, blue: 1.00)
  static let finderFolderBlue = Color(red: 0.31, green: 0.71, blue: 0.98)
  static let notesGold = Color(red: 0.90, green: 0.67, blue: 0.06)
  /// Capture chrome drawn over the dimmed desktop: the selection gradient's sky tone and the
  /// toolbar's active-toggle blue.
  static let selectionAccent = Color(red: 0.40, green: 0.75, blue: 1.0)
  static let toggleAccent = Color(red: 0.16, green: 0.50, blue: 0.98)
}

// MARK: - Studio Watermark Wallpaper

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
          ForEach(0..<8, id: \.self) { row in
            HStack(spacing: 44) {
              ForEach(0..<6, id: \.self) { col in
                let mark = app.watermarks[(row * 3 + col) % app.watermarks.count]
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
    .drawingGroup(opaque: true)
    .accessibilityHidden(true)
  }
}

// MARK: - Authentic MacBook Hardware Notch Shape

/// Real MacBook Pro / Air display notch: flush with `y = 0`, subtle concave top-corner shoulders
/// meeting the screen top bezel seamlessly, and smooth rounded bottom corners.
private struct MacBookNotchShape: Shape {
  var shoulderRadius: CGFloat = 5
  var bottomRadius: CGFloat = 7

  func path(in rect: CGRect) -> Path {
    let s = min(shoulderRadius, rect.width * 0.12)
    let r = min(bottomRadius, rect.height * 0.5, (rect.width - s * 2) * 0.5)
    let leftX = rect.minX + s
    let rightX = rect.maxX - s

    var path = Path()
    // Top edge spanning across both concave shoulders
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

    // Top-right concave shoulder curving down into the right vertical side
    path.addQuadCurve(
      to: CGPoint(x: rightX, y: rect.minY + s),
      control: CGPoint(x: rightX, y: rect.minY)
    )

    // Right vertical side + smooth bottom-right corner
    path.addLine(to: CGPoint(x: rightX, y: rect.maxY - r))
    path.addQuadCurve(
      to: CGPoint(x: rightX - r, y: rect.maxY),
      control: CGPoint(x: rightX, y: rect.maxY)
    )

    // Bottom edge + smooth bottom-left corner
    path.addLine(to: CGPoint(x: leftX + r, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: leftX, y: rect.maxY - r),
      control: CGPoint(x: leftX, y: rect.maxY)
    )

    // Left vertical side + top-left concave shoulder returning to top edge
    path.addLine(to: CGPoint(x: leftX, y: rect.minY + s))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.minY),
      control: CGPoint(x: leftX, y: rect.minY)
    )

    path.closeSubpath()
    return path
  }
}

// MARK: - Menu Bar (Cropped Real-Scale MacBook Display)

struct SnapzyMockMenuBar: View, Equatable {
  var app: SnapzyMockApp = .notes

  static let barHeight: CGFloat = 28

  var body: some View {
    GeometryReader { proxy in
      let visibleWidth = proxy.size.width
      // The right-column stage is a cropped frame onto a full-width Mac screen, so the camera
      // notch sits shifted toward the virtual display center and right status icons crop naturally.
      let notchShift = max(100, visibleWidth * 0.21)
      let notchCenterX = (visibleWidth / 2) + notchShift
      let notchWidth: CGFloat = 96
      let notchRightEdge = notchCenterX + (notchWidth / 2)

      ZStack(alignment: .topLeading) {
        // Translucent frosted menu bar strip
        Rectangle()
          .fill(Color.white.opacity(0.84))
          .frame(height: Self.barHeight)
          .overlay(
            Rectangle()
              .fill(Color.black.opacity(0.06))
              .frame(height: 0.5),
            alignment: .bottom
          )

        // 1. Left Menu Items ( + App Title + full macOS menus at real scale)
        leadingCluster
          .padding(.leading, 18)
          .frame(height: Self.barHeight, alignment: .leading)

        // 2. Camera Notch (shifted right to virtual display center, flush at y = 0)
        cameraNotch
          .position(x: notchCenterX, y: 10.5)

        // 3. Right Status Bar Items (extending naturally past the cropped right edge)
        trailingCluster
          .frame(height: Self.barHeight, alignment: .leading)
          .offset(x: notchRightEdge + 22)
      }
    }
    .frame(height: Self.barHeight)
    .accessibilityHidden(true)
  }

  private var leadingCluster: some View {
    HStack(spacing: 11) {
      Image(systemName: "apple.logo")
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(Color.black.opacity(0.90))
        .offset(y: -0.5)

      HStack(spacing: 11) {
        Text(app.menuTitle)
          .font(.system(size: 11.5, weight: .bold))
          .foregroundStyle(Color.black.opacity(0.92))

        ForEach(app.menus, id: \.self) { menu in
          Text(menu)
        }
      }
      .id(app)
      .transition(.opacity.combined(with: .offset(y: 2)))
      .animation(.timingCurve(0.20, 0.0, 0.12, 1.0, duration: 0.34), value: app)
    }
    .font(.system(size: 11.5, weight: .regular))
    .foregroundStyle(Color.black.opacity(0.82))
    .fixedSize()
  }

  private var trailingCluster: some View {
    HStack(spacing: 11) {
      // Snapzy's actual 4-petal menu bar glyph rendered as a crisp macOS template icon
      Image("WelcomeMark")
        .renderingMode(.template)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .frame(width: 11, height: 11)

      Image(systemName: "wifi")
        .font(.system(size: 10.5, weight: .semibold))

      MacOSMenuBarBattery()

      Image(systemName: "magnifyingglass")
        .font(.system(size: 10, weight: .semibold))

      MacOSControlCenterGlyph()

      Text("Sun Nov 22  9:41")
        .font(.system(size: 10.5, weight: .medium))
        .tracking(-0.1)
        .monospacedDigit()
    }
    .foregroundStyle(Color.black.opacity(0.84))
    .fixedSize()
  }

  private var cameraNotch: some View {
    ZStack {
      MacBookNotchShape(shoulderRadius: 5, bottomRadius: 6.5)
        .fill(SnapzyMockPalette.bezel)

      Circle()
        .fill(Color(white: 0.12))
        .frame(width: 4.5, height: 4.5)
        .overlay(
          Circle()
            .fill(Color(red: 0.04, green: 0.05, blue: 0.08))
            .frame(width: 2.5, height: 2.5)
        )
        .offset(y: -0.5)
    }
    .frame(width: 96, height: 21)
  }
}

/// Crisp solid-fill macOS battery indicator matching modern Sonoma/Sequoia/Tahoe menu bar geometry.
private struct MacOSMenuBarBattery: View {
  var body: some View {
    HStack(spacing: 1) {
      RoundedRectangle(cornerRadius: 2.3, style: .continuous) // radius-lint:allow — micro 8.5pt macOS battery capsule geometry
        .fill(.primary)
        .frame(width: 16.5, height: 8.5)

      UnevenRoundedRectangle(
        topLeadingRadius: 0,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 1.2,
        topTrailingRadius: 1.2
      )
      .fill(.primary.opacity(0.75))
      .frame(width: 1.4, height: 3.4)
    }
  }
}

/// Authentic two-row macOS Control Center double-toggle glyph matching the real menu bar.
private struct MacOSControlCenterGlyph: View {
  var body: some View {
    VStack(spacing: 1.8) {
      ZStack(alignment: .trailing) {
        Capsule(style: .continuous)
          .strokeBorder(.primary, lineWidth: 1.0)
          .frame(width: 11, height: 4.4)
        Circle()
          .fill(.primary)
          .frame(width: 3.2, height: 3.2)
          .padding(.trailing, 0.7)
      }

      ZStack(alignment: .leading) {
        Capsule(style: .continuous)
          .fill(.primary)
          .frame(width: 11, height: 4.4)
        Circle()
          .fill(Color.white.opacity(0.92))
          .frame(width: 2.6, height: 2.6)
          .padding(.leading, 1.0)
      }
    }
  }
}

// MARK: - Composed Canvas

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
