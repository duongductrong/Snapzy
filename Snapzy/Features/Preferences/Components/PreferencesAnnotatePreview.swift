//
//  PreferencesAnnotatePreview.swift
//  Snapzy
//
//  Illustrative preview above the Annotate tab: the top-left corner of an
//  Annotate window resting on the desktop — toolbar, quick properties bar,
//  background sidebar, and an annotated screenshot on the canvas. Static; it
//  conveys what the tab configures rather than mirroring each setting, so it
//  is rasterized once per process and drawn as a single bitmap.
//

import SwiftUI

struct AnnotateSettingsPreview: View {
  /// All geometry is authored on this canvas and scaled to the available width.
  private static let canvas = CGSize(width: 600, height: 280)
  /// The window runs past the right and bottom edges, like a crop.
  private static let windowOrigin = CGPoint(x: 26, y: 24)
  private static let windowSize = CGSize(width: 640, height: 340)
  private static let windowRadius: CGFloat = 12

  private static let toolbarHeight: CGFloat = 36
  private static let propertiesHeight: CGFloat = 30
  private static let sidebarWidth: CGFloat = 150

  // Cool palette centred on blue, white and periwinkle: annotations share one
  // periwinkle ink, and every swatch stays within the same blue family.
  private static let accent = Color(red: 0.49, green: 0.47, blue: 0.98)
  private static let blue = Color(red: 0.29, green: 0.56, blue: 0.98)
  private static let paper = Color.white
  static let ink = Color(red: 0.13, green: 0.16, blue: 0.36)

  var body: some View {
    Group {
      if let image = Self.renderedImage {
        Image(decorative: image, scale: Self.renderScale)
          .resizable()
          .interpolation(.high)
      } else {
        GeometryReader { proxy in
          sceneCanvas
            .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
            // Cover, not fit, so sub-pixel rounding never leaves a sliver.
            .scaleEffect(
              max(proxy.size.width / Self.canvas.width, proxy.size.height / Self.canvas.height),
              anchor: .topLeading
            )
        }
      }
    }
    .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
    )
    .accessibilityHidden(true)
  }

  /// Retina-sharp at the Preferences pane width; the scene never changes, so
  /// shadows, gradients and symbols are composited exactly once.
  private static let renderScale: CGFloat = 2

  @MainActor
  private static let renderedImage: CGImage? = {
    let renderer = ImageRenderer(
      content: AnnotateSettingsPreview().sceneCanvas
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .clipped()
    )
    renderer.scale = renderScale
    renderer.isOpaque = true
    return renderer.cgImage
  }()

  private var sceneCanvas: some View {
    ZStack(alignment: .topLeading) {
      PaintedSkyBackdrop()

      annotateWindow
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .topLeading)
        .offset(x: Self.windowOrigin.x, y: Self.windowOrigin.y)
    }
    .environment(\.colorScheme, .dark)
  }

  // MARK: - Window

  private var windowShape: CornerRoundedRectangle {
    CornerRoundedRectangle(topLeading: Self.windowRadius, topTrailing: Self.windowRadius)
  }

  private var annotateWindow: some View {
    VStack(spacing: 0) {
      toolbar
      hairline
      propertiesBar
      hairline
      HStack(spacing: 0) {
        sidebar
        Rectangle()
          .fill(Color.black.opacity(0.4))
          .frame(width: 0.5)
        canvasArea
      }
    }
    .background(Color(red: 0.12, green: 0.13, blue: 0.17))
    .clipShape(windowShape)
    .overlay(
      windowShape
        .inset(by: 0.5)
        .stroke(Color.white.opacity(0.14), lineWidth: 0.75)
    )
    // Flatten first so the window casts one shadow, not one per child.
    .compositingGroup()
    .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 10)
  }

  private var hairline: some View {
    Rectangle()
      .fill(Color.black.opacity(0.4))
      .frame(height: 0.5)
  }

  // MARK: - Toolbar

  private var toolbar: some View {
    HStack(spacing: 0) {
      HStack(spacing: 7) {
        // Unfocused-window lights keep the chrome quiet.
        ForEach(0..<3, id: \.self) { _ in
          trafficLight(Color.white.opacity(0.2))
        }
      }
      .padding(.leading, 13)
      .padding(.trailing, 20)

      toolGroup(["crop", "rectangle.on.rectangle"])
      toolbarDivider
      toolGroup(["scissors", "rotate.left", "rotate.right"])
      toolbarDivider

      HStack(spacing: 3) {
        ForEach(AnnotationToolType.inlineAnnotateTools) { tool in
          toolButton(tool.icon, isSelected: tool == .rectangle)
        }
      }

      toolbarDivider
      toolGroup(["arrow.uturn.backward", "arrow.uturn.forward"])

      Spacer(minLength: 0)
    }
    .frame(height: Self.toolbarHeight)
    .background(Color(red: 0.15, green: 0.16, blue: 0.20))
  }

  private func trafficLight(_ color: Color) -> some View {
    Circle()
      .fill(color)
      .overlay(Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
      .frame(width: 10, height: 10)
  }

  private func toolGroup(_ symbols: [String]) -> some View {
    HStack(spacing: 3) {
      ForEach(symbols, id: \.self) { toolButton($0, isSelected: false) }
    }
  }

  private func toolButton(_ symbol: String, isSelected: Bool) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 10.5, weight: .medium))
      .foregroundStyle(Color.white.opacity(isSelected ? 1 : 0.82))
      .frame(width: 22, height: 22)
      .background(
        RoundedRectangle(cornerRadius: Radius.controlXS, style: .continuous)
          .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
      )
  }

  private var toolbarDivider: some View {
    Rectangle()
      .fill(Color.white.opacity(0.14))
      .frame(width: 1, height: 14)
      .padding(.horizontal, 7)
  }

  // MARK: - Quick Properties Bar

  private var propertiesBar: some View {
    HStack(spacing: 9) {
      Image(systemName: "rectangle")
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: 20, height: 20)
        .background(Circle().fill(Color.white.opacity(0.1)))
        .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.75))

      propertyLabel("Color")
      Circle().fill(Self.accent).frame(width: 11, height: 11)
      Circle().fill(Self.blue).frame(width: 11, height: 11)

      propertyDivider
      propertyLabel("Stroke")
      slider(fraction: 0.25)
      propertyValue("4")

      propertyDivider
      propertyLabel("Corners")
      slider(fraction: 0.2)
      propertyValue("5")

      propertyDivider
      propertyLabel("Line Style")
      Capsule().fill(Color.white).frame(width: 12, height: 1.5)
        .frame(width: 22, height: 16)
        .background(
          RoundedRectangle(cornerRadius: Radius.controlXS, style: .continuous)
            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
        )

      Spacer(minLength: 0)
    }
    .padding(.leading, 12)
    .frame(height: Self.propertiesHeight)
    .background(Color(red: 0.13, green: 0.14, blue: 0.18))
  }

  private func propertyLabel(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 8.5, weight: .medium))
      .foregroundStyle(Color.white.opacity(0.6))
      .fixedSize()
  }

  private func propertyValue(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 8.5, weight: .medium))
      .monospacedDigit()
      .foregroundStyle(Color.white.opacity(0.7))
      .fixedSize()
  }

  private var propertyDivider: some View {
    Rectangle()
      .fill(Color.white.opacity(0.12))
      .frame(width: 1, height: 14)
  }

  private func slider(fraction: CGFloat) -> some View {
    let width: CGFloat = 54
    return ZStack(alignment: .leading) {
      Capsule().fill(Color.white.opacity(0.16)).frame(height: 2.5)
      Capsule().fill(Self.accent).frame(width: width * fraction, height: 2.5)
      Circle()
        .fill(Color.white)
        .shadow(color: Color.black.opacity(0.3), radius: 1, y: 0.5)
        .frame(width: 9, height: 9)
        .offset(x: width * fraction - 4.5)
    }
    .frame(width: width)
  }

  // MARK: - Sidebar

  private static let gradientSwatches: [[Color]] = [
    [Color(red: 0.62, green: 0.8, blue: 1.0), Color(red: 0.29, green: 0.5, blue: 0.96)],
    [Color(red: 0.36, green: 0.48, blue: 0.98), Color(red: 0.6, green: 0.5, blue: 0.98)],
    [Color(red: 0.96, green: 0.97, blue: 1.0), Color(red: 0.7, green: 0.76, blue: 0.98)],
    [Color(red: 0.2, green: 0.28, blue: 0.7), Color(red: 0.45, green: 0.4, blue: 0.9)],
    [Color(red: 0.12, green: 0.15, blue: 0.36), Color(red: 0.3, green: 0.4, blue: 0.82)],
  ]

  private static let wallpaperSwatches: [[Color]] = [
    [Color(red: 0.1, green: 0.14, blue: 0.42), Color(red: 0.5, green: 0.48, blue: 0.98)],
    [Color(red: 0.3, green: 0.52, blue: 0.96), Color(red: 0.92, green: 0.95, blue: 1.0)],
    [Color(red: 0.42, green: 0.36, blue: 0.86), Color(red: 0.72, green: 0.78, blue: 1.0)],
    [Color(red: 0.16, green: 0.24, blue: 0.62), Color(red: 0.55, green: 0.72, blue: 1.0)],
    [Color(red: 0.08, green: 0.1, blue: 0.24), Color(red: 0.36, green: 0.42, blue: 0.9)],
  ]

  private static let solidSwatches: [Color] = [
    Color(red: 0.49, green: 0.47, blue: 0.98), Color(red: 0.29, green: 0.56, blue: 0.98),
    Color(red: 0.62, green: 0.8, blue: 1.0), Color(red: 0.13, green: 0.16, blue: 0.36),
    Color.white,
  ]

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 7) {
      sidebarHeading("Presets")
      HStack(spacing: 4) {
        Text("None")
          .padding(.horizontal, 7)
          .frame(height: 18)
          .background(Capsule().fill(Color.white.opacity(0.08)))
        HStack(spacing: 3) {
          Text("Select preset")
          Spacer(minLength: 0)
          Image(systemName: "chevron.down").font(.system(size: 6, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
        .background(Capsule().fill(Color.white.opacity(0.08)))
      }
      .font(.system(size: 7.5, weight: .medium))
      .lineLimit(1)
      .fixedSize(horizontal: false, vertical: true)
      .foregroundStyle(Color.white.opacity(0.85))

      sidebarHeading("Gradients").padding(.top, 3)
      swatchRow(Self.gradientSwatches.map { AnyShapeStyle(swatchGradient($0)) }, selected: nil)

      sidebarHeading("Wallpapers").padding(.top, 3)
      swatchRow(Self.wallpaperSwatches.map { AnyShapeStyle(wallpaperGradient($0)) }, selected: 1)

      sidebarHeading("Colors").padding(.top, 3)
      HStack(spacing: 6) {
        ForEach(Self.solidSwatches.indices, id: \.self) { index in
          Circle().fill(Self.solidSwatches[index]).frame(width: 12, height: 12)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.top, 11)
    .frame(width: Self.sidebarWidth, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color(red: 0.13, green: 0.14, blue: 0.19))
  }

  private func sidebarHeading(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 8.5, weight: .semibold))
      .foregroundStyle(Color.white.opacity(0.7))
      .lineLimit(1)
  }

  private func swatchRow(_ fills: [AnyShapeStyle], selected: Int?) -> some View {
    HStack(spacing: 5) {
      ForEach(fills.indices, id: \.self) { index in
        RoundedRectangle(cornerRadius: Radius.controlXS, style: .continuous)
          .fill(fills[index])
          .frame(width: 17, height: 17)
          .overlay(
            RoundedRectangle(cornerRadius: Radius.controlXS + 2, style: .continuous)
              .strokeBorder(Color.white, lineWidth: 1.25)
              .padding(-2.5)
              .opacity(index == selected ? 0.9 : 0)
          )
      }
    }
  }

  private func swatchGradient(_ colors: [Color]) -> LinearGradient {
    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  private func wallpaperGradient(_ colors: [Color]) -> RadialGradient {
    RadialGradient(colors: colors.reversed(), center: .bottomTrailing, startRadius: 1, endRadius: 22)
  }

  // MARK: - Canvas

  private var canvasArea: some View {
    ZStack(alignment: .topLeading) {
      Color(red: 0.1, green: 0.11, blue: 0.14)

      // Selected wallpaper framing the screenshot.
      ZStack(alignment: .topLeading) {
        Y2KSkyBackdrop()
          .clipShape(RoundedRectangle(cornerRadius: Radius.controlS, style: .continuous))

        annotatedScreenshot
          .padding(.top, 18)
          .padding(.leading, 20)
      }
      .frame(width: 400, height: 260)
      .compositingGroup()
      .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
      .offset(x: 24, y: 16)
    }
    .clipped()
  }

  /// A mock web dashboard with a handful of annotations drawn over it.
  private var annotatedScreenshot: some View {
    ZStack(alignment: .topLeading) {
      MockDashboardScreenshot()
        .frame(width: 360, height: 220)

      // Pixelated blur over an email address.
      PixelatedBlock()
        .frame(width: 72, height: 10)
        .offset(x: 112, y: 46)

      // Highlighter stroke over a headline.
      Capsule()
        .fill(Self.blue.opacity(0.24))
        .frame(width: 104, height: 11)
        .offset(x: 12, y: 74)

      // Rectangle around the primary button.
      RoundedRectangle(cornerRadius: 5, style: .continuous) // radius-lint:allow mirrors the rectangle tool's corner value
        .strokeBorder(Self.accent, lineWidth: 2.2)
        .frame(width: 92, height: 32)
        .offset(x: 196, y: 104)

      AnnotationArrow()
        .stroke(Self.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        .frame(width: 70, height: 36)
        .offset(x: 124, y: 96)

      counterBadge(1)
        .offset(x: 278, y: 94)
      counterBadge(2)
        .offset(x: 2, y: 66)

      Text("Click here")
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(Self.paper)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
          RoundedRectangle(cornerRadius: Radius.controlXS, style: .continuous)
            .fill(Self.ink)
        )
        .offset(x: 82, y: 132)
    }
    .frame(width: 360, height: 220, alignment: .topLeading)
  }

  private func counterBadge(_ number: Int) -> some View {
    Text("\(number)")
      .font(.system(size: 8.5, weight: .bold, design: .rounded))
      .foregroundStyle(Self.paper)
      .frame(width: 16, height: 16)
      .background(Circle().fill(Self.accent))
      .overlay(Circle().strokeBorder(Self.paper, lineWidth: 1.25))
  }
}

// MARK: - Y2K Backdrop

/// Blue-and-white sky in a Y2K graphic style: the brand cloud backdrop with a
/// receding grid floor, an orbit ring, a glossy chrome orb and sparkles.
private struct Y2KSkyBackdrop: View {
  /// (x, y, size, opacity) in unit space.
  private static let sparkles: [(CGFloat, CGFloat, CGFloat, Double)] = [
    (0.95, 0.10, 18, 0.95), (0.86, 0.24, 9, 0.8), (0.04, 0.12, 12, 0.85),
    (0.97, 0.52, 11, 0.75), (0.02, 0.62, 8, 0.7), (0.6, 0.04, 7, 0.7),
  ]

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size

      ZStack(alignment: .topLeading) {
        PaintedSkyBackdrop()

        Y2KGridFloor()
          .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
          .frame(width: size.width, height: size.height * 0.42)
          .offset(y: size.height * 0.58)

        Ellipse()
          .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
          .frame(width: size.width * 0.5, height: size.height * 0.22)
          .rotationEffect(.degrees(-14))
          .position(x: size.width * 0.86, y: size.height * 0.2)

        Circle()
          .fill(
            RadialGradient(
              colors: [Color.white, Color(red: 0.72, green: 0.84, blue: 1.0), Color(red: 0.2, green: 0.4, blue: 0.95)],
              center: UnitPoint(x: 0.32, y: 0.28),
              startRadius: 1,
              endRadius: 26
            )
          )
          .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 0.75))
          .frame(width: 34, height: 34)
          .position(x: size.width * 0.92, y: size.height * 0.2)

        ForEach(Self.sparkles.indices, id: \.self) { index in
          let sparkle = Self.sparkles[index]
          Y2KSparkle()
            .fill(Color.white)
            .frame(width: sparkle.2, height: sparkle.2)
            .opacity(sparkle.3)
            .position(x: size.width * sparkle.0, y: size.height * sparkle.1)
        }
      }
      .frame(width: size.width, height: size.height)
    }
  }
}

/// Four-point star with concave sides.
private struct Y2KSparkle: Shape {
  func path(in rect: CGRect) -> Path {
    let c = CGPoint(x: rect.midX, y: rect.midY)
    var path = Path()
    path.move(to: CGPoint(x: c.x, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: rect.maxX, y: c.y), control: c)
    path.addQuadCurve(to: CGPoint(x: c.x, y: rect.maxY), control: c)
    path.addQuadCurve(to: CGPoint(x: rect.minX, y: c.y), control: c)
    path.addQuadCurve(to: CGPoint(x: c.x, y: rect.minY), control: c)
    path.closeSubpath()
    return path
  }
}

/// Perspective grid receding toward a horizon at the top of its frame.
private struct Y2KGridFloor: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let vanishing = CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6)
    for index in -8...8 {
      let x = rect.midX + CGFloat(index) * rect.width / 8
      let t = rect.height * 0.6 / (rect.height * 1.6)
      path.move(to: CGPoint(x: vanishing.x + (x - vanishing.x) * t, y: rect.minY))
      path.addLine(to: CGPoint(x: x, y: rect.maxY))
    }
    for row in 0..<7 {
      let progress = pow(CGFloat(row) / 6, 1.8)
      let y = rect.minY + rect.height * progress
      path.move(to: CGPoint(x: rect.minX, y: y))
      path.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    return path
  }
}

// MARK: - Mock Screenshot

/// Light web-dashboard snapshot used as the image being annotated.
private struct MockDashboardScreenshot: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Browser chrome.
      HStack(spacing: 4) {
        ForEach(0..<3, id: \.self) { _ in
          Circle().fill(Color.black.opacity(0.14)).frame(width: 5, height: 5)
        }
        Capsule()
          .fill(Color.black.opacity(0.06))
          .frame(width: 140, height: 9)
          .padding(.leading, 30)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .frame(height: 18)
      .background(Color(red: 0.93, green: 0.95, blue: 0.99))

      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 5) {
          Circle().fill(AnnotateSettingsPreview.ink).frame(width: 14, height: 14)
          bar(width: 70, opacity: 0.55, height: 6)
          Spacer(minLength: 0)
        }

        HStack(spacing: 6) {
          bar(width: 88, opacity: 0.2)
          bar(width: 70, opacity: 0.2)
        }

        bar(width: 98, opacity: 0.7, height: 7)
          .padding(.top, 8)
        bar(width: 220, opacity: 0.16)
        bar(width: 190, opacity: 0.16)

        HStack(spacing: 8) {
          RoundedRectangle(cornerRadius: Radius.controlXS, style: .continuous)
            .fill(Color.black.opacity(0.05))
            .frame(width: 80, height: 24)
          RoundedRectangle(cornerRadius: Radius.controlXS, style: .continuous)
            .fill(AnnotateSettingsPreview.ink)
            .frame(width: 80, height: 24)
            .overlay(bar(width: 40, opacity: 0, height: 4).background(Capsule().fill(Color.white.opacity(0.85))))
        }
        .padding(.top, 6)
        .padding(.leading, 108)

        HStack(spacing: 8) {
          ForEach(0..<3, id: \.self) { index in
            RoundedRectangle(cornerRadius: Radius.controlS, style: .continuous)
              .fill(Color.black.opacity(0.04))
              .frame(width: 104, height: 52)
              .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                  bar(width: 40, opacity: 0.25)
                  bar(width: [60, 48, 54][index], opacity: 0.55, height: 8)
                }
                .padding(8)
              }
          }
        }
        .padding(.top, 10)
      }
      .padding(12)

      Spacer(minLength: 0)
    }
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: Radius.controlXS, style: .continuous))
  }

  private func bar(width: CGFloat, opacity: Double, height: CGFloat = 5) -> some View {
    Capsule()
      .fill(Color.black.opacity(opacity))
      .frame(width: width, height: height)
  }
}

/// Mosaic block standing in for the blur tool's pixelation.
private struct PixelatedBlock: View {
  private static let shades: [Double] = [0.55, 0.7, 0.62, 0.8, 0.5, 0.74, 0.66, 0.58, 0.78, 0.6, 0.7, 0.52]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Self.shades.indices, id: \.self) { index in
        VStack(spacing: 0) {
          Rectangle().fill(Color(white: Self.shades[index]))
          Rectangle().fill(Color(white: Self.shades[(index + 5) % Self.shades.count]))
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous)) // radius-lint:allow tiny mosaic tile
  }
}

/// Curved arrow from the bottom-left to the top-right of its frame.
private struct AnnotationArrow: Shape {
  func path(in rect: CGRect) -> Path {
    let start = CGPoint(x: rect.minX, y: rect.maxY)
    let end = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.35)
    var path = Path()
    path.move(to: start)
    path.addQuadCurve(to: end, control: CGPoint(x: rect.midX - 6, y: rect.minY))

    // Head follows the curve's tangent at the end point.
    let control = CGPoint(x: rect.midX - 6, y: rect.minY)
    let angle = atan2(end.y - control.y, end.x - control.x)
    let headLength: CGFloat = 8
    for offset in [CGFloat.pi * 0.8, -CGFloat.pi * 0.8] {
      path.move(to: end)
      path.addLine(
        to: CGPoint(
          x: end.x + headLength * cos(angle + offset),
          y: end.y + headLength * sin(angle + offset)
        )
      )
    }
    return path
  }
}

#Preview {
  AnnotateSettingsPreview()
    .padding()
    .frame(width: 600)
}
