//
//  LiquidGlassPreview.swift
//  Snapzy
//
//  Interactive design system playground and comparison tool for Liquid Glass:
//  macOS 26+ (Apple Native Liquid Glass) vs macOS 13–15 (Ruru 4-Layer Optical Composite).
//

import AppKit
import SwiftUI

// MARK: - Wallpaper Preset

enum PlaygroundWallpaper: String, CaseIterable, Identifiable {
  case darkAmbient = "dark"
  case brightDesktop = "bright"
  case vibrantGradient = "vibrant"
  case checkerboard = "checker"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .darkAmbient:
      return "Tối (Dark)"
    case .brightDesktop:
      return "Sáng / Trắng (Bright)"
    case .vibrantGradient:
      return "Màu sắc (Vibrant)"
    case .checkerboard:
      return "Bàn cờ (Grid)"
    }
  }

  @ViewBuilder
  var backgroundView: some View {
    switch self {
    case .darkAmbient:
      LinearGradient(
        colors: [Color(red: 0.10, green: 0.12, blue: 0.18), Color(red: 0.04, green: 0.05, blue: 0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .brightDesktop:
      LinearGradient(
        colors: [Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.88, green: 0.91, blue: 0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .vibrantGradient:
      LinearGradient(
        colors: [Color(red: 0.35, green: 0.15, blue: 0.55), Color(red: 0.85, green: 0.35, blue: 0.35), Color(red: 0.15, green: 0.45, blue: 0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .checkerboard:
      CheckerboardCanvas()
    }
  }
}

// MARK: - Checkerboard Pattern

private struct CheckerboardCanvas: View {
  var body: some View {
    Canvas { context, size in
      let squareSize: CGFloat = 20
      let rows = Int(ceil(size.height / squareSize))
      let cols = Int(ceil(size.width / squareSize))

      for row in 0..<rows {
        for col in 0..<cols {
          let isDark = (row + col).isMultiple(of: 2)
          let color = isDark ? Color(white: 0.20) : Color(white: 0.28)
          let rect = CGRect(
            x: CGFloat(col) * squareSize,
            y: CGFloat(row) * squareSize,
            width: squareSize,
            height: squareSize
          )
          context.fill(Path(rect), with: .color(color))
        }
      }
    }
  }
}

// MARK: - Display Mode

enum PlaygroundDisplayMode: String, CaseIterable, Identifiable {
  case sideBySide = "sideBySide"
  case macOS26 = "macos26"
  case macOS1315 = "macos1315"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .sideBySide:
      return "So sánh song song"
    case .macOS26:
      return "macOS 26+ (Apple Glass)"
    case .macOS1315:
      return "macOS 13–15 (Fallback)"
    }
  }
}

// MARK: - Main Playground View

struct LiquidGlassPlaygroundView: View {
  @State private var displayMode: PlaygroundDisplayMode = .sideBySide
  @State private var selectedWallpaper: PlaygroundWallpaper = .brightDesktop
  @State private var colorSchemeOverride: ColorScheme? = nil
  @State private var tuning = LiquidGlassTuning.default
  @State private var isAppForcedLegacy = LiquidGlassCapabilities.runtimeLegacyOverride ?? false

  @State private var selectedTab = "Capture"
  @State private var isActionActive = false
  @State private var isToolbarToggleActive = true
  @State private var isBusy = false

  private let tabs = ["Capture", "Record", "OCR", "History"]

  var body: some View {
    HSplitView {
      // Left / Main preview canvas
      ZStack {
        selectedWallpaper.backgroundView
          .ignoresSafeArea()

        VStack(spacing: 16) {
          topToolbarHeader

          ScrollView {
            VStack(spacing: 24) {
              switch displayMode {
              case .sideBySide:
                sideBySideSection
              case .macOS26:
                singleVersionSection(
                  title: "macOS 26+ (Apple Native Liquid Glass)",
                  subtitle: "Sử dụng .glassEffect(.regular.interactive()) của Apple, khúc xạ nền thời gian thực",
                  mode: .native
                )
              case .macOS1315:
                singleVersionSection(
                  title: "macOS 13–15 (Ruru 4-Layer Optical Composite)",
                  subtitle: "Tầng 1 Substrate + Tầng 2 Sheen/Blur + Tầng 3 Veil + Tầng 4 Specular Hairline 0.5pt",
                  mode: .legacy
                )
              }
            }
            .padding(24)
          }
        }
      }
      .frame(minWidth: 620, minHeight: 650)

      // Right: Adjustment sidebar ("Bản điều chỉnh")
      adjustmentSidebar
        .frame(width: 290)
    }
    .preferredColorScheme(colorSchemeOverride)
    .frame(minWidth: 920, minHeight: 680)
  }

  // MARK: - Top Toolbar Header

  private var topToolbarHeader: some View {
    HStack(spacing: 12) {
      Picker("Chế độ", selection: $displayMode) {
        ForEach(PlaygroundDisplayMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 320)

      Spacer()

      Picker("Hình nền", selection: $selectedWallpaper) {
        ForEach(PlaygroundWallpaper.allCases) { wp in
          Text(wp.title).tag(wp)
        }
      }
      .pickerStyle(.menu)
      .frame(width: 140)

      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          if colorSchemeOverride == nil {
            colorSchemeOverride = .light
          } else if colorSchemeOverride == .light {
            colorSchemeOverride = .dark
          } else {
            colorSchemeOverride = nil
          }
        }
      } label: {
        Image(systemName: appearanceIcon)
          .font(.system(size: 13, weight: .medium))
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.bordered)
      .help("Đổi giao diện: Tự động / Sáng / Tối")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background {
      Capsule(style: .continuous)
        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        .overlay {
          Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        }
    }
    .padding(.horizontal, 20)
    .padding(.top, 14)
    .padding(.bottom, 6)
  }

  private var appearanceIcon: String {
    switch colorSchemeOverride {
    case .light: return "sun.max.fill"
    case .dark: return "moon.fill"
    case nil: return "circle.lefthalf.filled"
    @unknown default: return "circle.lefthalf.filled"
    }
  }

  // MARK: - Side by Side Section

  private var sideBySideSection: some View {
    HStack(alignment: .top, spacing: 20) {
      // Column 1: macOS 26+ Native
      VStack(spacing: 16) {
        columnHeader(
          title: "macOS 26+ (Apple Liquid Glass)",
          badge: "Official API",
          badgeColor: .blue
        )

        componentGallery(renderMode: .native)
      }
      .environment(\.liquidGlassRenderMode, .native)
      .frame(maxWidth: .infinity)

      // Column 2: macOS 13–15 Fallback
      VStack(spacing: 16) {
        columnHeader(
          title: "macOS 13–15 (Solid Native Fallback)",
          badge: "Solid Native",
          badgeColor: .orange
        )

        componentGallery(renderMode: .legacy)
      }
      .environment(\.liquidGlassRenderMode, .legacy)
      .environment(\.liquidGlassTuning, tuning)
      .frame(maxWidth: .infinity)
    }
  }

  private func singleVersionSection(title: String, subtitle: String, mode: LiquidGlassRenderMode) -> some View {
    VStack(spacing: 20) {
      VStack(spacing: 4) {
        Text(title)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundStyle(LiquidGlassTokens.inkMuted)
          .multilineTextAlignment(.center)
      }

      componentGallery(renderMode: mode)
        .frame(maxWidth: 540)
    }
    .environment(\.liquidGlassRenderMode, mode)
    .environment(\.liquidGlassTuning, mode == .legacy ? tuning : nil)
  }

  private func columnHeader(title: String, badge: String, badgeColor: Color) -> some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(LiquidGlassTokens.inkPrimary)

      Text(badge)
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.18))
        .foregroundStyle(badgeColor)
        .clipShape(Capsule())
    }
    .padding(.vertical, 4)
  }

  // MARK: - Component Gallery

  private func componentGallery(renderMode: LiquidGlassRenderMode) -> some View {
    VStack(spacing: 20) {
      // 1. Sliding Segmented Control
      LiquidGlassSegmentedControl(items: tabs, selection: $selectedTab) { tab in
        Text(tab)
      }

      // 2. Button Emphasis Suite
      VStack(spacing: 10) {
        HStack(spacing: 8) {
          LiquidGlassActionButton(
            title: "Lưu lại",
            icon: "square.and.arrow.down",
            trailingKey: "⌘S",
            emphasis: .primary,
            capsule: true
          ) {}

          LiquidGlassActionButton(
            title: "Sao chép",
            trailingKey: "⌘C",
            emphasis: .secondary,
            capsule: true
          ) {}

          LiquidGlassActionButton(
            title: "Xóa",
            icon: "trash",
            emphasis: .destructive,
            capsule: true
          ) {}
        }

        HStack(spacing: 8) {
          Button("Context Pill") {}
            .buttonStyle(LiquidGlassButtonStyle(emphasis: .contextPill, capsule: false))

          Button("Active Pill") {
            isActionActive.toggle()
          }
          .buttonStyle(
            LiquidGlassButtonStyle(
              emphasis: .secondary,
              capsule: false,
              isActive: isActionActive
            )
          )

          Button {
            isToolbarToggleActive.toggle()
          } label: {
            Image(systemName: "pencil.tip.crop.circle")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(
                isToolbarToggleActive
                  ? LiquidGlassTokens.ink(onTint: .accentColor, renderMode: renderMode)
                  : LiquidGlassTokens.inkPrimary
              )
              .frame(width: 32, height: 26)
              .liquidGlassControl(isActive: isToolbarToggleActive)
          }
          .buttonStyle(.plain)
          .help("Property-bar control")
        }
      }

      // 3. Floating HUD Card
      hudCardSection(renderMode: renderMode)

      // 4. Grouped Action Bar with Etched Dividers
      LiquidGlassActionBar(
        cancelTitle: "Bỏ qua",
        confirmTitle: "Tiếp tục",
        confirmKey: "↩",
        isConfirmEnabled: true,
        isBusy: isBusy,
        onCancel: {},
        onConfirm: { isBusy.toggle() }
      )
    }
    .padding(16)
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.black.opacity(0.12))
    }
  }

  private func hudCardSection(renderMode: LiquidGlassRenderMode) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: renderMode == .native ? "apple.logo" : "macwindow")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)
        Text(renderMode == .native ? "Native Metal Glass" : "Solid Native Controls")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)
        Spacer()
        Text(renderMode == .native ? "Shader" : "0.5pt Hairline")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(LiquidGlassTokens.inkMuted)
      }

      Text(
        renderMode == .native
          ? "Apple .glassEffect() tự động lấy mẫu pixel màn hình phía sau và tính toán độ tán xạ."
          : "Màu sắc solid đậm chất native macOS, viền hairline 0.5pt sắc sảo, chống lóa và không giả lập hiệu ứng kính quá đà."
      )
      .font(.system(size: 11))
      .lineSpacing(2)
      .foregroundStyle(LiquidGlassTokens.inkBody)
    }
    .padding(14)
    .liquidGlass(
      shape: RoundedRectangle(cornerRadius: LiquidGlassTokens.cardRadius, style: .continuous),
      substrate: LiquidGlassTokens.baseDarkness,
      tint: 0.03,
      withRimLighting: true
    )
  }

  // MARK: - Adjustment Sidebar ("Bản điều chỉnh")

  private var adjustmentSidebar: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        sidebarHeader

        Divider()

        globalAppSection

        Divider()

        compositeParametersSection

        Divider()

        layerDeconstructorSection

        Divider()

        technicalNotesSection
      }
      .padding(16)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var sidebarHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: "slider.horizontal.below.square.and.square.filled")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(Color.accentColor)
        Text("Bản Điều Chỉnh")
          .font(.system(size: 14, weight: .bold))
      }
      Text("Hiệu chỉnh thông số hiển thị macOS 13–15 và bóc tách các tầng kính.")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
  }

  private var globalAppSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Toàn Bộ Ứng Dụng")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)

      Toggle("Ép macOS 13–15 toàn app", isOn: $isAppForcedLegacy)
        .toggleStyle(.switch)
        .onChange(of: isAppForcedLegacy) { forced in
          LiquidGlassCapabilities.runtimeLegacyOverride = forced
        }

      Text(isAppForcedLegacy
           ? "Toàn bộ cửa sổ Snapzy (Annotate, Video Editor, Quick Access, Recording) đang hiển thị ở chế độ macOS 13–15."
           : "Ứng dụng tự động dùng macOS 26+ Apple Glass trên máy bạn.")
        .font(.system(size: 10.5))
        .foregroundStyle(isAppForcedLegacy ? .orange : .secondary)
        .lineSpacing(1.5)
    }
  }

  private var compositeParametersSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Thông Số macOS 13–15")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.secondary)
        Spacer()
        Button("Đặt lại") {
          withAnimation {
            tuning = LiquidGlassTuning.default
          }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10.5))
        .foregroundStyle(Color.accentColor)
      }

      // Slider 1: Substrate Darkness
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("1. Substrate nền:")
            .font(.system(size: 11, weight: .medium))
          Spacer()
          Text(String(format: "%.2f", tuning.substrateOpacity))
            .font(.system(size: 11, weight: .regular))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        Slider(value: $tuning.substrateOpacity, in: 0.0...0.60, step: 0.02)
        Text("Kéo về 0 để thấy hiện tượng chìm màu (washout) trên nền trắng!")
          .font(.system(size: 9.5))
          .foregroundStyle(tuning.substrateOpacity < 0.1 ? .red : .secondary)
      }

      // Slider 2: Sheen Opacity
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("2. Sheen phản xạ:")
            .font(.system(size: 11, weight: .medium))
          Spacer()
          Text(String(format: "%.2f", tuning.sheenTopOpacity))
            .font(.system(size: 11, weight: .regular))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        Slider(value: $tuning.sheenTopOpacity, in: 0.0...0.30, step: 0.01)
      }

      // Slider 3: Specular Border
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("4. Viền Specular 0.5pt:")
            .font(.system(size: 11, weight: .medium))
          Spacer()
          Text(String(format: "%.2f", tuning.specularTopOpacity))
            .font(.system(size: 11, weight: .regular))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        Slider(value: $tuning.specularTopOpacity, in: 0.0...0.50, step: 0.02)
      }
    }
  }

  private var layerDeconstructorSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Bóc Tách Từng Tầng (Composite)")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 6) {
        Toggle("Tầng 1: Substrate nền", isOn: $tuning.isSubstrateEnabled)
        Toggle("Tầng 2: Refraction Sheen", isOn: $tuning.isRefractionEnabled)
        Toggle("Tầng 3: Body Veil / Wash", isOn: $tuning.isVeilEnabled)
        Toggle("Tầng 4: Specular Border 0.5pt", isOn: $tuning.isSpecularEnabled)
        Toggle("Rim Lighting (Viền cong)", isOn: $tuning.isRimLightingEnabled)
      }
      .font(.system(size: 11))
    }
  }

  private var technicalNotesSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Ghi chú kỹ thuật")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)

      Text("• macOS 26+: Dùng API chính thức của Apple (.glassEffect), khúc xạ bằng Metal shader của WindowServer.")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)

      Text("• macOS 13–15: Chưa có Liquid Glass. Snapzy tự dựng mô hình 4 tầng quang học (Optical Composite) để giữ độ tương phản > 4.5:1.")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Xcode Preview

#Preview {
  LiquidGlassPlaygroundView()
}
