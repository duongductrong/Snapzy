//
//  PreferencesVisualOptionTile.swift
//  Snapzy
//
//  Shared thumbnail + caption option used by visual pickers (theme, backdrop style...).
//

import SwiftUI

/// One selectable preview tile. The selection ring sits just outside the thumbnail with a
/// hairline gap, and the caption turns bold primary when picked and stays secondary otherwise,
/// so the picked option reads from the shape alone, not only from color.
struct PreferencesVisualOptionTile<Thumbnail: View>: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void
  @ViewBuilder let thumbnail: () -> Thumbnail

  @Environment(\.colorScheme) private var colorScheme
  @State private var isHovering = false

  static var thumbnailSize: CGSize { CGSize(width: 72, height: 52) }
  private static var ringInset: CGFloat { 3.5 }

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        thumbnail()
          .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
          .clipShape(Radius.rect(Radius.tile))
          .overlay { Radius.rect(Radius.tile).strokeBorder(hairlineColor, lineWidth: 0.5) }
          .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
          .brightness(isHovering && !isSelected ? 0.04 : 0)
          .padding(Self.ringInset)
          .overlay {
            Radius.rect(Radius.tile + Self.ringInset)
              .strokeBorder(Color.accentColor, lineWidth: 2.5)
              .opacity(isSelected ? 1 : 0)
          }

        Text(title)
          .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
          .foregroundStyle(isSelected ? .primary : .secondary)
          .lineLimit(1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.15), value: isSelected)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var hairlineColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
  }
}

// MARK: - Mini Desktop

/// Miniature desktop (wallpaper + menu bar) for previews that show how a floating surface
/// sits on screen. Content is laid out over the full desktop, menu bar included.
struct PreferencesMiniDesktop<Content: View>: View {
  @ViewBuilder let content: () -> Content

  static var menuBarHeight: CGFloat { 5 }

  var body: some View {
    ZStack(alignment: .top) {
      PreferencesMiniWallpaper()
      menuBar
      content()
    }
  }

  private var menuBar: some View {
    HStack(spacing: 3) {
      Capsule().fill(Color.white.opacity(0.85)).frame(width: 4, height: 1.5)
      Capsule().fill(Color.white.opacity(0.45)).frame(width: 6, height: 1.5)
      Capsule().fill(Color.white.opacity(0.45)).frame(width: 5, height: 1.5)
      Spacer(minLength: 0)
      Capsule().fill(Color.white.opacity(0.45)).frame(width: 5, height: 1.5)
      Capsule().fill(Color.white.opacity(0.85)).frame(width: 7, height: 1.5)
    }
    .padding(.horizontal, 5)
    .frame(height: Self.menuBarHeight)
    .background(Color.black.opacity(0.28))
  }
}

/// Indigo wallpaper with two soft waves — busy enough that translucency visibly reads through.
struct PreferencesMiniWallpaper: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Color(red: 0.17, green: 0.17, blue: 0.45), Color(red: 0.10, green: 0.12, blue: 0.55)],
        startPoint: .top,
        endPoint: .bottom
      )
      MiniWave(crest: 0.48, trough: 0.72)
        .fill(LinearGradient(
          colors: [Color(red: 0.36, green: 0.38, blue: 0.92), Color(red: 0.22, green: 0.26, blue: 0.85)],
          startPoint: .top,
          endPoint: .bottom
        ))
      MiniWave(crest: 0.64, trough: 0.86)
        .fill(Color(red: 0.08, green: 0.12, blue: 0.70))
      MiniWave(crest: 0.64, trough: 0.86)
        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
    }
  }
}

private struct MiniWave: Shape {
  /// Fractions of the height where the wave peaks (right) and dips (left).
  let crest: CGFloat
  let trough: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * trough))
    path.addCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * crest),
      control1: CGPoint(x: rect.width * 0.45, y: rect.minY + rect.height * (trough + 0.1)),
      control2: CGPoint(x: rect.width * 0.55, y: rect.minY + rect.height * (crest - 0.12))
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}
