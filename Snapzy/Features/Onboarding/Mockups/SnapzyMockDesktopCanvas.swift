//
//  SnapzyMockDesktopCanvas.swift
//  Snapzy
//
//  Faithful macOS desktop canvas: layered wallpaper, authentic menu bar with camera notch.
//

import AppKit
import ImageIO
import SwiftUI

// MARK: - Mock Scene

/// Which application the simulated desktop is dressed as.
///
/// Each onboarding step pairs its simulated macOS app with one of Snapzy's bundled macOS
/// wallpapers from `Snapzy/Resources/Wallpapers` so every step feels like a real Mac desktop.
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
    case .notes: ["File", "Edit", "View", "Help"]
    case .finder: ["File", "Edit", "View", "Go"]
    case .settings: ["Edit", "View", "Help"]
    }
  }

  /// Bundled wallpaper filename (without extension) from `Snapzy/Resources/Wallpapers`.
  var wallpaperResourceName: String {
    switch self {
    case .notes: "default-tahoe-light"
    case .finder: "default-helios-dark"
    case .settings: "default-macbook-pro-blue"
    }
  }
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

// MARK: - Bundled Wallpaper Loader & View

private enum SnapzyMockWallpaperLoader {
  private static let cache = NSCache<NSString, NSImage>()
  private static let subdirectories = [nil, "Wallpapers", "Resources/Wallpapers"]

  static func image(named resourceName: String) -> NSImage? {
    let key = resourceName as NSString
    if let cached = cache.object(forKey: key) {
      return cached
    }

    guard let url = resolveURL(for: resourceName),
          let image = downsampleImage(at: url, maxPixelSize: 1440) else {
      return nil
    }

    cache.setObject(image, forKey: key)
    return image
  }

  private static func resolveURL(for resourceName: String) -> URL? {
    for subdirectory in subdirectories {
      if let url = Bundle.main.url(
        forResource: resourceName,
        withExtension: "jpg",
        subdirectory: subdirectory
      ) {
        return url
      }
    }
    return nil
  }

  private static func downsampleImage(at url: URL, maxPixelSize: CGFloat) -> NSImage? {
    let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
      return nil
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return NSImage(contentsOf: url)
    }

    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
  }
}

struct SnapzyMockWallpaper: View, Equatable {
  var app: SnapzyMockApp = .notes

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      if let nsImage = SnapzyMockWallpaperLoader.image(named: app.wallpaperResourceName) {
        Image(nsImage: nsImage)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fill)
          .frame(width: size.width, height: size.height)
          .clipped()
      } else {
        Color(red: 0.08, green: 0.10, blue: 0.14)
          .frame(width: size.width, height: size.height)
      }
    }
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

// MARK: - Menu Bar

struct SnapzyMockMenuBar: View, Equatable {
  var app: SnapzyMockApp = .notes

  static let barHeight: CGFloat = 25

  var body: some View {
    ZStack(alignment: .top) {
      // Authentic translucent macOS menu bar letting the bundled wallpaper shine through
      ZStack {
        LinearGradient(
          colors: [
            Color.black.opacity(0.24),
            Color.black.opacity(0.16),
          ],
          startPoint: .top,
          endPoint: .bottom
        )

        HStack(spacing: 0) {
          leadingCluster
            .padding(.leading, 13)

          Spacer(minLength: 108)

          trailingCluster
            .padding(.trailing, 13)
        }
      }
      .frame(height: Self.barHeight)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(Color.white.opacity(0.12))
          .frame(height: 0.5)
      }

      // Authentic MacBook hardware camera notch: anchored flush at y = 0, centered horizontally,
      // matching the full menu bar height just like real macOS on notched MacBooks.
      cameraNotch
    }
    .frame(maxWidth: .infinity)
    .frame(height: Self.barHeight, alignment: .top)
    .accessibilityHidden(true)
  }

  private var leadingCluster: some View {
    HStack(spacing: 10) {
      Image(systemName: "apple.logo")
        .font(.system(size: 11, weight: .medium))

      Text(app.menuTitle)
        .font(.system(size: 10.5, weight: .bold))

      ForEach(app.menus, id: \.self) { menu in
        Text(menu)
      }
    }
    // Sized so the cluster always clears the centred notch cleanly at every onboarding window width.
    .font(.system(size: 10.5, weight: .medium))
    .foregroundStyle(Color.white.opacity(0.95))
    .shadow(color: Color.black.opacity(0.30), radius: 1.5, y: 0.5)
    .fixedSize()
  }

  private var trailingCluster: some View {
    HStack(spacing: 8) {
      Image(systemName: "camera.viewfinder")
        .font(.system(size: 9.5, weight: .semibold))

      Image(systemName: "wifi")
        .font(.system(size: 9.5, weight: .medium))

      Image(systemName: "battery.100")
        .font(.system(size: 11.5, weight: .regular))

      Image(systemName: "magnifyingglass")
        .font(.system(size: 9.5, weight: .medium))

      Image(systemName: "switch.2")
        .font(.system(size: 9.5, weight: .medium))

      Text("9:41 AM")
        .font(.system(size: 10, weight: .medium))
        .monospacedDigit()
    }
    .foregroundStyle(Color.white.opacity(0.95))
    .shadow(color: Color.black.opacity(0.30), radius: 1.5, y: 0.5)
    .fixedSize()
  }

  private var cameraNotch: some View {
    ZStack {
      MacBookNotchShape(shoulderRadius: 5, bottomRadius: 7)
        .fill(SnapzyMockPalette.bezel)

      // Recessed FaceTime HD camera optics
      HStack(spacing: 5) {
        Circle()
          .fill(Color(white: 0.14))
          .frame(width: 6, height: 6)
          .overlay(
            Circle()
              .fill(Color(red: 0.04, green: 0.05, blue: 0.09))
              .frame(width: 3.8, height: 3.8)
          )
          .overlay(
            Circle()
              .fill(Color(red: 0.24, green: 0.42, blue: 0.72).opacity(0.55))
              .frame(width: 1.4, height: 1.4)
              .offset(x: -0.6, y: -0.6)
          )
      }
      .offset(y: -0.5)
    }
    .frame(width: 100, height: Self.barHeight)
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
