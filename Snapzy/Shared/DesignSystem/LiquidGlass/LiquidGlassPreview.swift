//
//  LiquidGlassPreview.swift
//  Snapzy
//
//  Interactive design system preview and playground for Liquid Glass components.
//

import SwiftUI

#if DEBUG

struct LiquidGlassPreview: View {
  @State private var selectedTab = "Capture"
  @State private var isActionActive = false
  @State private var isBusy = false

  private let tabs = ["Capture", "Record", "OCR", "History"]

  var body: some View {
    ZStack {
      // Wallpaper background simulation
      LinearGradient(
        colors: [Color(red: 0.12, green: 0.14, blue: 0.22), Color(red: 0.05, green: 0.07, blue: 0.12)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      VStack(spacing: 24) {
        headerSection

        // Sliding Segmented Control
        LiquidGlassSegmentedControl(items: tabs, selection: $selectedTab) { tab in
          Text(tab)
        }

        // Button Emphasis Suite
        buttonSection

        // Custom View Card
        customCardSection

        // Action Bar with Etched Dividers
        LiquidGlassActionBar(
          cancelTitle: "Cancel",
          confirmTitle: "Proceed",
          confirmKey: "↩",
          isConfirmEnabled: true,
          isBusy: isBusy,
          onCancel: {},
          onConfirm: { isBusy.toggle() }
        )
      }
      .padding(32)
      .frame(width: 580)
    }
  }

  // MARK: - Sections

  private var headerSection: some View {
    VStack(spacing: 6) {
      Text("Liquid Glass Design System")
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(LiquidGlassTokens.inkPrimary)
      Text("4-Layer Optical Composite Architecture")
        .font(.system(size: 12))
        .foregroundStyle(LiquidGlassTokens.inkMuted)
    }
  }

  private var buttonSection: some View {
    VStack(spacing: 12) {
      HStack(spacing: 10) {
        LiquidGlassActionButton(
          title: "Primary Action",
          icon: "sparkles",
          emphasis: .primary
        ) {}

        LiquidGlassActionButton(
          title: "Secondary",
          trailingKey: "⌘K",
          emphasis: .secondary
        ) {}

        LiquidGlassActionButton(
          title: "Delete",
          icon: "trash",
          emphasis: .destructive
        ) {}
      }

      HStack(spacing: 10) {
        Button("Context Pill") {}
          .buttonStyle(LiquidGlassButtonStyle(emphasis: .contextPill, capsule: false))

        Button("Active Toggle") {
          isActionActive.toggle()
        }
        .buttonStyle(
          LiquidGlassButtonStyle(
            emphasis: .secondary,
            capsule: false,
            isActive: isActionActive
          )
        )
      }
    }
  }

  private var customCardSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: "macwindow.on.rectangle")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)
        Text("Custom View Surface")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)
        Spacer()
        Text("0.5pt Border")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(LiquidGlassTokens.inkMuted)
      }

      Text("Ruru-calibrated dark substrate (0.28) and specular hairline gradient ensure high contrast and tangible physics over any wallpaper.")
        .font(.system(size: 11.5))
        .lineSpacing(2)
        .foregroundStyle(LiquidGlassTokens.inkBody)
    }
    .padding(16)
    .liquidGlass(
      shape: RoundedRectangle(cornerRadius: LiquidGlassTokens.cardRadius, style: .continuous),
      substrate: LiquidGlassTokens.baseDarkness,
      tint: 0.03,
      withRimLighting: true
    )
  }
}

#Preview {
  LiquidGlassPreview()
}

#endif
