//
//  SnapzyOnboardingMockHost.swift
//  Snapzy
//
//  Right-column stage: the clipped, speculatively-edged viewport every mock scene draws into.
//

import SwiftUI

struct SnapzyOnboardingMockHost: View {
  @ObservedObject var state: SnapzyOnboardingState

  /// Every mock scene already paints its own desktop, so the stage is a screen, not a tab. The
  /// old shape rounded only the top-leading corner and squared the rest to fuse with the window's
  /// bottom-right — which left one corner of the composition carrying a different radius from the
  /// other three. One panel radius on four corners reads as a deliberate container.
  private var stageShape: RoundedRectangle {
    Radius.rect(SnapzyOnboardingMetrics.stageRadius)
  }

  var body: some View {
    ZStack {
      switch state.currentStep {
      case .meetSnapzy:
        SnapzyMockAreaCaptureView(state: state)
      case .quickAccess:
        SnapzyMockQuickAccessView(state: state)
      case .shortcuts:
        SnapzyMockShortcutsView(state: state)
      case .permissions:
        Color.clear
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipShape(stageShape)
    .overlay(
      stageShape.strokeBorder(
        Color.black.opacity(0.35),
        lineWidth: 1.5
      )
    )
    .overlay(
      stageShape.strokeBorder(
        LinearGradient(
          colors: SnapzySurfaceGlass.stageEdgeColors,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        lineWidth: SnapzySurfaceGlass.stageEdgeWidth
      )
    )
    .shadow(
      color: SnapzyGlassShadow.stageColor,
      radius: SnapzyGlassShadow.stageRadius,
      x: -6,
      y: SnapzyGlassShadow.stageY
    )
    .shadow(
      color: SnapzyGlassShadow.stageAmbientColor,
      radius: SnapzyGlassShadow.stageAmbientRadius,
      x: -2,
      y: 2
    )
  }
}
