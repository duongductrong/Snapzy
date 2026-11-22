//
//  SnapzyMockScene.swift
//  Snapzy
//
//  Shared geometry, transitions and chrome for the miniature macOS scenes on the mock stage.
//

import SwiftUI

/// The stage's own layout vocabulary.
///
/// Every scene used to invent its own insets and its own entrance, which is why the Notes window
/// sat at one height in step 1 and the video editor at another in step 2. One place now decides
/// where a window lives on the stage and how it arrives.
enum SnapzyMockScene {
  /// Space between the stage edge and a mock window, so nothing crowds the menu bar or the bezel.
  static let windowInset: CGFloat = 22
  static let windowTopInset: CGFloat = 40

  /// A window opening is a zoom from its own place on the desk, never from nothing.
  static let windowTransition: AnyTransition = .asymmetric(
    insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
    removal: .scale(scale: 0.97, anchor: .top).combined(with: .opacity)
  )

  /// A card flying out of the bottom edge of the screen, the way Quick Access really appears.
  static let cardTransition: AnyTransition = .asymmetric(
    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)),
    removal: .move(edge: .bottom).combined(with: .opacity)
  )

  /// A floating HUD chip.
  static let hudTransition: AnyTransition = .asymmetric(
    insertion: .scale(scale: 0.94).combined(with: .opacity),
    removal: .opacity
  )
}

/// Whether the mock scene is the one on screen. The Spaces deck keeps every scene mounted, so a
/// scene that slid off-stage would otherwise keep its timers and looping animations running and
/// redraw for nobody. Looping motion reads this and pauses while the scene is off-stage.
private struct SnapzyMockSceneIsLiveKey: EnvironmentKey {
  static let defaultValue = true
}

/// Whether the mock scene is on stage and at rest. AppKit-backed controls inside a scene (a
/// scroll view, a switch) are swapped for identical-looking SwiftUI stand-ins while the scene is
/// gliding or being inserted/removed: a platform view inside the 3D-transformed, clipped Spaces
/// deck forces a full geometry sync every animation frame.
private struct SnapzyMockSceneIsSettledKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  var snapzyMockSceneIsLive: Bool {
    get { self[SnapzyMockSceneIsLiveKey.self] }
    set { self[SnapzyMockSceneIsLiveKey.self] = newValue }
  }

  var snapzyMockSceneIsSettled: Bool {
    get { self[SnapzyMockSceneIsSettledKey.self] }
    set { self[SnapzyMockSceneIsSettledKey.self] = newValue }
  }
}

/// Shared native macOS window traffic lights so every simulated app shares identical Apple chrome.
struct SnapzyMockTrafficLights: View {
  var size: CGFloat = 10
  var spacing: CGFloat = 6.5

  var body: some View {
    HStack(spacing: spacing) {
      dot(SnapzyMockPalette.trafficRed)
      dot(SnapzyMockPalette.trafficYellow)
      dot(SnapzyMockPalette.trafficGreen)
    }
    .accessibilityHidden(true)
  }

  private func dot(_ color: Color) -> some View {
    Circle()
      .fill(color)
      .frame(width: size, height: size)
      .overlay(
        Circle()
          .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
      )
  }
}

/// The pill that invites a click inside a mock scene — the stage's version of the real capture HUD.
struct SnapzyMockSceneButton: View {
  var title: String
  var symbol: String?
  var action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        if let symbol {
          Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
        }

        Text(title)
          .font(.system(size: SnapzyOnboardingType.body, weight: .semibold))
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .foregroundStyle(Color.white)
      .padding(.horizontal, 14)
      .frame(height: 34)
      .background {
        SnapzyGlassSurface(
          shape: Capsule(style: .continuous),
          substrate: SnapzySurfaceGlass.baseDarkness + (isHovered ? 0.06 : 0),
          tint: isHovered ? 0.16 : 0.10
        )
      }
      .clipShape(Capsule(style: .continuous))
      .shadow(color: SnapzyGlassShadow.controlColor, radius: SnapzyGlassShadow.controlRadius,
              y: SnapzyGlassShadow.controlY)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(SnapzyMotionPreferences.shared.spec(.hover).animation) {
        isHovered = hovering
      }
    }
  }
}
