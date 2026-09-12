//
//  LiquidGlassPreview.swift
//  Snapzy
//
//  Interactive Design System Studio & Playground for Liquid Glass:
//  macOS 26+ (Apple Native Liquid Glass) vs macOS 13–15 (Solid Native Fallback).
//

import AppKit
import SwiftUI

// MARK: - Wallpapers

enum PlaygroundWallpaper: String, CaseIterable, Identifiable {
  case darkAmbient = "dark"
  case brightDesktop = "bright"
  case vibrantSunset = "vibrant"
  case emeraldOcean = "ocean"
  case checkerboard = "checker"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .darkAmbient: return "Dark Ambient"
    case .brightDesktop: return "Bright Clean"
    case .vibrantSunset: return "Sunset Gradient"
    case .emeraldOcean: return "Emerald Ocean"
    case .checkerboard: return "Checkerboard"
    }
  }

  @ViewBuilder
  var backgroundView: some View {
    switch self {
    case .darkAmbient:
      LinearGradient(
        colors: [Color(red: 0.09, green: 0.11, blue: 0.16), Color(red: 0.04, green: 0.05, blue: 0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .brightDesktop:
      LinearGradient(
        colors: [Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.88, green: 0.91, blue: 0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .vibrantSunset:
      LinearGradient(
        colors: [Color(red: 0.38, green: 0.16, blue: 0.58), Color(red: 0.85, green: 0.32, blue: 0.38), Color(red: 0.96, green: 0.58, blue: 0.28)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    case .emeraldOcean:
      LinearGradient(
        colors: [Color(red: 0.08, green: 0.35, blue: 0.42), Color(red: 0.05, green: 0.22, blue: 0.32), Color(red: 0.03, green: 0.12, blue: 0.20)],
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
          let color = isDark ? Color(white: 0.18) : Color(white: 0.26)
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
    case .sideBySide: return "So sánh song song"
    case .macOS26: return "macOS 26+ (Apple Glass)"
    case .macOS1315: return "macOS 13–15 (Solid Native)"
    }
  }
}

// MARK: - Design System Categories

enum PlaygroundCategory: String, CaseIterable, Identifiable {
  case overview = "overview"
  case buttons = "buttons"
  case segmented = "segmented"
  case toolbars = "toolbars"
  case cards = "cards"
  case forms = "forms"
  case mockups = "mockups"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: return "Overview & Tokens"
    case .buttons: return "Buttons & Actions"
    case .segmented: return "Segmented Controls"
    case .toolbars: return "Toolbars & Docks"
    case .cards: return "Cards & Overlays"
    case .forms: return "Form Controls"
    case .mockups: return "Feature Mockups"
    }
  }

  var icon: String {
    switch self {
    case .overview: return "swatchpalette"
    case .buttons: return "button.programmable"
    case .segmented: return "square.split.2x1"
    case .toolbars: return "menubar.rectangle"
    case .cards: return "macwindow.on.rectangle"
    case .forms: return "slider.horizontal.3"
    case .mockups: return "sparkles.rectangle.stack"
    }
  }

  var subtitle: String {
    switch self {
    case .overview: return "Màu sắc, độ mờ substrate, bán kính và viền specular"
    case .buttons: return "Đầy đủ emphasis, kích cỡ, hình dạng và trạng thái tương tác"
    case .segmented: return "Thanh chọn phân đoạn trượt mượt mà với hiệu ứng đệm kính"
    case .toolbars: return "Thanh công cụ nổi Annotate và Dock điều khiển Recording"
    case .cards: return "Thẻ Quick Access, Toast thông báo và hộp thoại xác nhận"
    case .forms: return "Ô tìm kiếm phủ kính, thanh trượt, toggle và ô chọn"
    case .mockups: return "Mô phỏng chân thực trải nghiệm Snapzy trong môi trường làm việc"
    }
  }
}

// MARK: - Main Playground View

struct LiquidGlassPlaygroundView: View {
  @State private var selectedCategory: PlaygroundCategory = .buttons
  @State private var displayMode: PlaygroundDisplayMode = .sideBySide
  @State private var selectedWallpaper: PlaygroundWallpaper = .brightDesktop
  @State private var colorSchemeOverride: ColorScheme? = nil
  @State private var isInspectorVisible = true

  // Optical Tuning State
  @State private var tuning = LiquidGlassTuning.default
  @State private var isAppForcedLegacy = LiquidGlassCapabilities.forcesLegacyGlass

  // Simulator State
  @State private var simulateDisabled = false
  @State private var simulateBusy = false
  @State private var hasCopiedCode = false

  // Component Interactive States
  @State private var selectedTab = "Capture"
  @State private var selectedMode = 1
  @State private var isActionActive = false
  @State private var isToolbarToggleActive = true
  @State private var searchQuery = ""
  @State private var sliderValue: Double = 0.65
  @State private var toggleValue = true
  @State private var checkboxValue = true
  @State private var selectedColorIndex = 0

  private let tabs = ["Capture", "Record", "OCR", "History"]
  private let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple]

  var body: some View {
    HStack(spacing: 0) {
      // 1. Left Navigation Sidebar
      studioSidebar

      Divider()

      // 2. Central Studio Canvas
      ZStack {
        selectedWallpaper.backgroundView

        VStack(spacing: 0) {
          studioTopBar
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
              Divider()
            }

          ScrollView {
            VStack(spacing: 24) {
              categoryHeaderView

              switch displayMode {
              case .sideBySide:
                sideBySideGallery
              case .macOS26:
                singleVersionGallery(mode: .native, title: "macOS 26+ (Apple Liquid Glass)", badge: "Official API", badgeColor: .blue)
              case .macOS1315:
                singleVersionGallery(mode: .legacy, title: "macOS 13–15 (Solid Native Fallback)", badge: "Solid Native", badgeColor: .orange)
              }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
          }
        }
      }
      .frame(minWidth: 580, maxWidth: .infinity)

      // 3. Right Collapsible Inspector
      if isInspectorVisible {
        Divider()

        studioInspector
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .preferredColorScheme(colorSchemeOverride)
    .animation(.easeInOut(duration: 0.22), value: isInspectorVisible)
    .animation(.easeInOut(duration: 0.20), value: displayMode)
    .animation(.easeInOut(duration: 0.18), value: selectedCategory)
  }

  // MARK: - Sidebar

  private var studioSidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Studio Brand Header
      HStack(spacing: 10) {
        Image(systemName: "drop.halffull")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(Color.accentColor)

        VStack(alignment: .leading, spacing: 1) {
          Text("Snapzy Studio")
            .font(.system(size: 13, weight: .bold))
          Text("Liquid Glass Design System")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }

        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      Divider()

      // Categories List
      ScrollView {
        VStack(spacing: 4) {
          ForEach(PlaygroundCategory.allCases) { category in
            let isSelected = selectedCategory == category

            Button {
              selectedCategory = category
            } label: {
              HStack(spacing: 10) {
                Image(systemName: category.icon)
                  .font(.system(size: 12, weight: .medium))
                  .frame(width: 18)
                  .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(category.title)
                  .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                  .foregroundStyle(isSelected ? .primary : .secondary)
                  .lineLimit(1)
                  .fixedSize(horizontal: true, vertical: false)

                Spacer()
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
              )
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
      }

      Spacer()

      Divider()

      // Host OS Status Pill
      HStack(spacing: 8) {
        Circle()
          .fill(LiquidGlassCapabilities.isSystemSupported ? Color.green : Color.orange)
          .frame(width: 7, height: 7)

        VStack(alignment: .leading, spacing: 1) {
          Text(LiquidGlassCapabilities.isSystemSupported ? "macOS 26+ Native Ready" : "macOS 13–15 Compatible")
            .font(.system(size: 10, weight: .semibold))
          Text(LiquidGlassCapabilities.forcesLegacyGlass ? "Ép chế độ Solid Fallback" : "Chế độ Auto Adaptive")
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
        }

        Spacer()
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }
    .frame(width: 240)
    .background(Color(NSColor.windowBackgroundColor))
  }

  // MARK: - Top Toolbar

  private var studioTopBar: some View {
    HStack(spacing: 12) {
      // Display Mode Picker
      Picker("", selection: $displayMode) {
        ForEach(PlaygroundDisplayMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 460)

      Spacer()

      // Wallpaper Selector
      Picker("Nền", selection: $selectedWallpaper) {
        ForEach(PlaygroundWallpaper.allCases) { wp in
          Text(wp.title).tag(wp)
        }
      }
      .pickerStyle(.menu)
      .frame(width: 140)

      // Light/Dark Theme Switcher
      Button {
        if colorSchemeOverride == nil {
          colorSchemeOverride = .light
        } else if colorSchemeOverride == .light {
          colorSchemeOverride = .dark
        } else {
          colorSchemeOverride = nil
        }
      } label: {
        Image(systemName: colorSchemeOverride == .dark ? "moon.fill" : (colorSchemeOverride == .light ? "sun.max.fill" : "circle.lefthalf.filled"))
          .font(.system(size: 12))
          .frame(width: 28, height: 24)
      }
      .buttonStyle(.bordered)
      .help("Đổi giao diện Sáng / Tối / Theo hệ thống")

      // Inspector Toggle Button
      Button {
        withAnimation {
          isInspectorVisible.toggle()
        }
      } label: {
        Image(systemName: "sidebar.right")
          .font(.system(size: 12, weight: isInspectorVisible ? .bold : .regular))
          .foregroundStyle(isInspectorVisible ? Color.accentColor : .primary)
          .frame(width: 28, height: 24)
      }
      .buttonStyle(.bordered)
      .help("Ẩn/Hiện thanh Inspector tinh chỉnh")
    }
  }

  // MARK: - Category Header

  private var categoryHeaderView: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Image(systemName: selectedCategory.icon)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.accentColor)

          Text(selectedCategory.title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.primary)
        }

        Text(selectedCategory.subtitle)
          .font(.system(size: 11.5))
          .foregroundStyle(Color.secondary)
      }

      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
    )
  }

  // MARK: - Galleries

  private var sideBySideGallery: some View {
    HStack(alignment: .top, spacing: 20) {
      // Left Column: Native Liquid Glass (macOS 26+)
      VStack(spacing: 16) {
        columnHeader(title: "macOS 26+ (Apple Liquid Glass)", badge: "Official API", badgeColor: .blue)

        categoryContent(for: selectedCategory, mode: .native)
      }
      .environment(\.liquidGlassRenderMode, .native)
      .frame(maxWidth: .infinity)

      // Right Column: Solid Native Fallback (macOS 13–15)
      VStack(spacing: 16) {
        columnHeader(title: "macOS 13–15 (Solid Native Fallback)", badge: "Solid Native", badgeColor: .orange)

        categoryContent(for: selectedCategory, mode: .legacy)
      }
      .environment(\.liquidGlassRenderMode, .legacy)
      .environment(\.liquidGlassTuning, tuning)
      .frame(maxWidth: .infinity)
    }
  }

  private func singleVersionGallery(mode: LiquidGlassRenderMode, title: String, badge: String, badgeColor: Color) -> some View {
    VStack(spacing: 18) {
      columnHeader(title: title, badge: badge, badgeColor: badgeColor)

      categoryContent(for: selectedCategory, mode: mode)
        .frame(maxWidth: 680)
    }
    .environment(\.liquidGlassRenderMode, mode)
    .environment(\.liquidGlassTuning, mode == .legacy ? tuning : nil)
  }

  private func columnHeader(title: String, badge: String, badgeColor: Color) -> some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.system(size: 12.5, weight: .bold))
        .foregroundStyle(LiquidGlassTokens.inkPrimary)

      Text(badge)
        .font(.system(size: 9.5, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.18))
        .foregroundStyle(badgeColor)
        .clipShape(Capsule())
    }
    .padding(.vertical, 3)
  }

  // MARK: - Category Content Switcher

  @ViewBuilder
  private func categoryContent(for category: PlaygroundCategory, mode: LiquidGlassRenderMode) -> some View {
    switch category {
    case .overview:
      overviewSection(mode: mode)
    case .buttons:
      buttonsSection(mode: mode)
    case .segmented:
      segmentedSection(mode: mode)
    case .toolbars:
      toolbarsSection(mode: mode)
    case .cards:
      cardsSection(mode: mode)
    case .forms:
      formsSection(mode: mode)
    case .mockups:
      mockupsSection(mode: mode)
    }
  }

  // MARK: - 1. Overview & Tokens

  private func overviewSection(mode: LiquidGlassRenderMode) -> some View {
    VStack(spacing: 16) {
      studioCard("Color & Ink Tokens", subtitle: "Màu chữ và biểu tượng tương thích theo nền sáng/tối") {
        VStack(spacing: 10) {
          HStack(spacing: 12) {
            tokenSwatch(name: "inkPrimary", color: LiquidGlassTokens.inkPrimary, subtitle: "Đậm nét chính")
            tokenSwatch(name: "inkBody", color: LiquidGlassTokens.inkBody, subtitle: "Nội dung thân")
            tokenSwatch(name: "inkMuted", color: LiquidGlassTokens.inkMuted, subtitle: "Gợi ý / Disabled")
          }

          HStack(spacing: 12) {
            tokenSwatch(name: "Accent Blue", color: .accentColor, subtitle: "Primary Action")
            tokenSwatch(name: "Destructive", color: .red, subtitle: "Xóa / Cảnh báo")
            tokenSwatch(name: "Glass Tint", color: .white.opacity(0.18), subtitle: "Neutral Layer")
          }
        }
      }

      studioCard("Substrate Levels", subtitle: "Độ đậm nền các trạng thái nút secondary") {
        HStack(spacing: 12) {
          VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
              .fill(Color.black.opacity(LiquidGlassTokens.controlSubstrateResting))
              .frame(height: 38)
              .overlay(Text("0.45").font(.caption.monospacedDigit()).foregroundStyle(.white))
            Text("Resting").font(.system(size: 10.5)).foregroundStyle(.secondary)
          }

          VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
              .fill(Color.black.opacity(LiquidGlassTokens.controlSubstrateHover))
              .frame(height: 38)
              .overlay(Text("0.60").font(.caption.monospacedDigit()).foregroundStyle(.white))
            Text("Hover").font(.system(size: 10.5)).foregroundStyle(.secondary)
          }

          VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8)
              .fill(Color.black.opacity(LiquidGlassTokens.controlSubstratePressed))
              .frame(height: 38)
              .overlay(Text("0.72").font(.caption.monospacedDigit()).foregroundStyle(.white))
            Text("Pressed").font(.system(size: 10.5)).foregroundStyle(.secondary)
          }
        }
      }

      studioCard("Geometry & Hairline Physics", subtitle: "Bán kính bo cong và viền vật lý 0.5pt") {
        VStack(spacing: 8) {
          HStack {
            Text("Specular Hairline 0.5pt:")
              .font(.system(size: 11, weight: .medium))
            Spacer()
            Text("Top: 0.22 • Bottom: 0.06")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }

          HStack(spacing: 8) {
            Text("Control Radius: 8pt")
              .font(.system(size: 10.5))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Capsule().fill(.secondary.opacity(0.15)))

            Text("Card Radius: 12pt")
              .font(.system(size: 10.5))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Capsule().fill(.secondary.opacity(0.15)))

            Text("Capsule: 999pt")
              .font(.system(size: 10.5))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Capsule().fill(.secondary.opacity(0.15)))
          }
        }
      }
    }
  }

  private func tokenSwatch(name: String, color: Color, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      RoundedRectangle(cornerRadius: 6)
        .fill(color)
        .frame(height: 28)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
      Text(name)
        .font(.system(size: 10, weight: .bold))
      Text(subtitle)
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - 2. Buttons & Actions

  private func buttonsSection(mode: LiquidGlassRenderMode) -> some View {
    VStack(spacing: 16) {
      studioCard("Emphasis Levels", subtitle: "Primary, Secondary, Destructive và Ghost") {
        VStack(spacing: 8) {
          HStack(spacing: 8) {
            LiquidGlassActionButton(
              title: "Lưu lại",
              icon: "square.and.arrow.down",
              trailingKey: "⌘S",
              emphasis: .primary,
              capsule: true
            ) {}
            .disabled(simulateDisabled)

            LiquidGlassActionButton(
              title: "Sao chép",
              trailingKey: "⌘C",
              emphasis: .secondary,
              capsule: true
            ) {}
            .disabled(simulateDisabled)
          }

          HStack(spacing: 8) {
            LiquidGlassActionButton(
              title: "Xóa",
              icon: "trash",
              emphasis: .destructive,
              capsule: true
            ) {}
            .disabled(simulateDisabled)

            Button("Ghost / Subtle") {}
              .buttonStyle(LiquidGlassButtonStyle(emphasis: .contextPill, capsule: false))
              .disabled(simulateDisabled)
          }

          HStack(spacing: 8) {
            Button("Active Filter") {
              isActionActive.toggle()
            }
            .buttonStyle(LiquidGlassButtonStyle(emphasis: .secondary, capsule: false, isActive: isActionActive))
            .disabled(simulateDisabled)

            if simulateBusy {
              HStack(spacing: 6) {
                ProgressView()
                  .controlSize(.small)
                Text("Đang xử lý...")
                  .font(.system(size: 11, weight: .medium))
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(Capsule().fill(.black.opacity(0.5)))
              .foregroundStyle(.white)
            }
          }
        }
      }

      studioCard("Shape & Size Variants", subtitle: "Capsule (viên thuốc) vs Rounded Rectangle (chữ nhật bo)") {
        VStack(spacing: 10) {
          HStack(spacing: 8) {
            LiquidGlassActionButton(
              title: "Capsule Regular",
              icon: "star.fill",
              emphasis: .secondary,
              capsule: true
            ) {}
            .disabled(simulateDisabled)

            LiquidGlassActionButton(
              title: "Rounded Rect",
              icon: "slider.horizontal.3",
              emphasis: .secondary,
              capsule: false
            ) {}
            .disabled(simulateDisabled)
          }
        }
      }

      studioCard("Icon Action Grid", subtitle: "Bộ nút thao tác biểu tượng dùng trong toolbar và preview") {
        HStack(spacing: 10) {
          ForEach(["crop", "pencil.tip", "character", "arrow.up.right", "hand.draw", "trash"], id: \.self) { iconName in
            let isActive = iconName == "pencil.tip" && isToolbarToggleActive

            Button {
              if iconName == "pencil.tip" {
                isToolbarToggleActive.toggle()
              }
            } label: {
              Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isActive ? LiquidGlassTokens.ink(onTint: .accentColor, renderMode: mode) : LiquidGlassTokens.inkPrimary)
            }
            .buttonStyle(LiquidGlassButtonStyle(emphasis: isActive ? .primary : .secondary, capsule: false))
            .disabled(simulateDisabled)
          }
        }
      }
    }
  }

  // MARK: - 3. Segmented Controls

  private func segmentedSection(mode: LiquidGlassRenderMode) -> some View {
    VStack(spacing: 16) {
      studioCard("Sliding Pill Tabs", subtitle: "Bộ chọn phân đoạn chuẩn với hiệu ứng lò xo trượt fluid") {
        VStack(spacing: 12) {
          LiquidGlassSegmentedControl(items: tabs, selection: $selectedTab) { tab in
            Text(tab)
          }

          HStack {
            Text("Đang chọn:")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
            Text(selectedTab)
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Color.accentColor)
          }
        }
      }

      studioCard("Capture Mode Selector", subtitle: "Phân loại chế độ chụp với biểu tượng") {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
          ForEach([("Toàn màn hình", "display"), ("Vùng chọn", "crop"), ("Cửa sổ", "macwindow"), ("Cuộn trang", "arrow.down.doc")], id: \.0) { item in
            let isSelected = selectedTab == item.0

            Button {
              selectedTab = item.0
            } label: {
              HStack(spacing: 6) {
                Image(systemName: item.1)
                  .font(.system(size: 11))
                Text(item.0)
                  .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
              }
              .frame(maxWidth: .infinity)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .foregroundStyle(isSelected ? LiquidGlassTokens.ink(onTint: .accentColor, renderMode: mode) : LiquidGlassTokens.inkPrimary)
            }
            .buttonStyle(LiquidGlassButtonStyle(emphasis: isSelected ? .primary : .secondary, capsule: true))
          }
        }
      }
    }
  }

  // MARK: - 4. Toolbars & Docks

  private func toolbarsSection(mode: LiquidGlassRenderMode) -> some View {
    VStack(spacing: 16) {
      studioCard("Annotate Floating Dock", subtitle: "Thanh công cụ nổi chứa các bút vẽ, màu và hành động") {
        VStack(spacing: 12) {
          HStack(spacing: 6) {
            Group {
              Button {} label: { Image(systemName: "cursorarrow").frame(width: 22, height: 22) }
              Button {} label: { Image(systemName: "rectangle").frame(width: 22, height: 22) }
              Button {} label: { Image(systemName: "arrow.up.right").frame(width: 22, height: 22) }
              Button {} label: { Image(systemName: "pencil").frame(width: 22, height: 22) }
              Button {} label: { Image(systemName: "textformat").frame(width: 22, height: 22) }
            }
            .buttonStyle(LiquidGlassButtonStyle(emphasis: .secondary, capsule: false))

            Divider().frame(height: 18).padding(.horizontal, 2)

            // Color Palette
            HStack(spacing: 4) {
              ForEach(0..<colors.count, id: \.self) { idx in
                Circle()
                  .fill(colors[idx])
                  .frame(width: 14, height: 14)
                  .overlay(
                    Circle()
                      .stroke(Color.white, lineWidth: selectedColorIndex == idx ? 2 : 0)
                  )
                  .onTapGesture {
                    selectedColorIndex = idx
                  }
              }
            }

            Divider().frame(height: 18).padding(.horizontal, 2)

            Button {} label: { Image(systemName: "arrow.uturn.backward").frame(width: 22, height: 22) }
              .buttonStyle(LiquidGlassButtonStyle(emphasis: .secondary, capsule: false))
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .liquidGlassSurface(shape: Capsule(), layer: .control)
        }
      }

      studioCard("Recording Control Dock", subtitle: "Dock điều khiển phiên quay màn hình với timer thời gian thực") {
        HStack(spacing: 12) {
          HStack(spacing: 6) {
            Circle()
              .fill(.red)
              .frame(width: 8, height: 8)

            Text("01:42")
              .font(.system(size: 12, weight: .bold).monospacedDigit())
              .foregroundStyle(.primary)
          }

          Divider().frame(height: 16)

          HStack(spacing: 8) {
            LiquidGlassActionButton(title: "Tạm dừng", icon: "pause.fill", emphasis: .secondary, capsule: true) {}
            LiquidGlassActionButton(title: "Kết thúc", icon: "stop.fill", emphasis: .destructive, capsule: true) {}
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .liquidGlassSurface(shape: Capsule(), layer: .control)
      }
    }
  }

  // MARK: - 5. Cards & Overlays

  private func cardsSection(mode: LiquidGlassRenderMode) -> some View {
    VStack(spacing: 16) {
      studioCard("Quick Access Floating Card", subtitle: "Thẻ kết quả chụp nổi trên màn hình góc dưới phải") {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Image(systemName: "camera.fill")
              .font(.system(size: 11))
              .foregroundStyle(Color.accentColor)
            Text("Snapzy_2026-09-12_13-40.png")
              .font(.system(size: 11, weight: .bold))
              .lineLimit(1)
            Spacer()
            Text("PNG • 2.1 MB")
              .font(.system(size: 9.5))
              .foregroundStyle(.secondary)
          }

          // Fake Thumbnail
          RoundedRectangle(cornerRadius: 8)
            .fill(
              LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(height: 90)
            .overlay(
              Image(systemName: "photo")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.7))
            )

          // Card Action Buttons
          HStack(spacing: 8) {
            LiquidGlassActionButton(title: "Sao chép", icon: "doc.on.doc", trailingKey: "⌘C", emphasis: .secondary, capsule: true) {}
            LiquidGlassActionButton(title: "Sửa ảnh", icon: "pencil", emphasis: .secondary, capsule: true) {}
            Spacer()
            LiquidGlassActionButton(title: "Lưu", icon: "arrow.down", emphasis: .primary, capsule: true) {}
          }
        }
        .padding(14)
        .liquidGlassSurface(shape: RoundedRectangle(cornerRadius: 12), layer: .control)
        .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
      }

      studioCard("Notification Toast HUD", subtitle: "Thông báo nổi trạng thái (OCR, sao chép)") {
        HStack(spacing: 8) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(.green)

          Text("Đã sao chép ảnh chụp vào bộ nhớ tạm")
            .font(.system(size: 11.5, weight: .medium))

          Spacer()

          Text("⌘V")
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(.secondary.opacity(0.2)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .liquidGlassSurface(shape: Capsule(), layer: .control)
      }
    }
  }

  // MARK: - 6. Form Controls

  private func formsSection(mode: LiquidGlassRenderMode) -> some View {
    VStack(spacing: 16) {
      studioCard("Glass Search Field", subtitle: "Ô nhập liệu tìm kiếm phủ kính thời gian thực") {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

          TextField("Tìm kiếm lịch sử chụp, ghi chú...", text: $searchQuery)
            .textFieldStyle(.plain)
            .font(.system(size: 12))

          if !searchQuery.isEmpty {
            Button {
              searchQuery = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .liquidGlassSurface(shape: RoundedRectangle(cornerRadius: 8), layer: .control)
      }

      studioCard("Glass Sliders & Toggles", subtitle: "Thanh kéo tinh chỉnh và công tắc") {
        VStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text("Độ trong suốt:")
                .font(.system(size: 11, weight: .medium))
              Spacer()
              Text("\(Int(sliderValue * 100))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Slider(value: $sliderValue, in: 0...1)
          }

          Divider()

          Toggle("Tự động mở Annotate sau khi chụp", isOn: $toggleValue)
            .font(.system(size: 11.5))
            .toggleStyle(.switch)
        }
      }
    }
  }

  // MARK: - 7. Feature Mockups

  private func mockupsSection(mode: LiquidGlassRenderMode) -> some View {
    VStack(spacing: 18) {
      studioCard("Full Workspace Preview", subtitle: "Mô phỏng phối hợp Quick Access Card và Dock công cụ") {
        ZStack {
          // Inner Wallpaper Canvas
          RoundedRectangle(cornerRadius: 12)
            .fill(
              LinearGradient(
                colors: [Color(red: 0.15, green: 0.20, blue: 0.32), Color(red: 0.08, green: 0.10, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .frame(height: 240)
            .overlay(alignment: .top) {
              // Floating Toolbar in Mockup
              HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                  .font(.system(size: 11, weight: .bold))
                  .foregroundStyle(Color.accentColor)

                Text("Area Capture")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(.white)

                Text("1920 × 1080")
                  .font(.system(size: 10).monospacedDigit())
                  .foregroundStyle(.white.opacity(0.6))
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .liquidGlassSurface(shape: Capsule(), layer: .control)
              .padding(.top, 14)
            }
            .overlay(alignment: .bottomTrailing) {
              // Mini Quick Access Card
              HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                  .fill(Color.blue.opacity(0.4))
                  .frame(width: 44, height: 32)
                  .overlay(Image(systemName: "photo").font(.system(size: 12)).foregroundStyle(.white))

                VStack(alignment: .leading, spacing: 1) {
                  Text("Chụp nhanh")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white)
                  Text("Nhấn ⌘C để chép")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
                }

                LiquidGlassActionButton(title: "Sao chép", trailingKey: "⌘C", emphasis: .primary, capsule: true) {}
              }
              .padding(8)
              .liquidGlassSurface(shape: RoundedRectangle(cornerRadius: 10), layer: .control)
              .shadow(radius: 6)
              .padding(14)
            }
        }
      }
    }
  }

  // MARK: - Reusable Studio Card

  private func studioCard<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(LiquidGlassTokens.inkPrimary)

        if let subtitle {
          Text(subtitle)
            .font(.system(size: 10))
            .foregroundStyle(LiquidGlassTokens.inkMuted)
        }
      }

      content()
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    )
  }

  // MARK: - Studio Inspector

  private var studioInspector: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Inspector Header
      HStack {
        Image(systemName: "slider.horizontal.below.square.and.square.filled")
          .font(.system(size: 12))
          .foregroundStyle(Color.accentColor)

        Text("Inspector & Tuning")
          .font(.system(size: 12, weight: .bold))

        Spacer()

        Button {
          withAnimation {
            isInspectorVisible = false
          }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          // 1. Global App Override
          inspectorGlobalSection

          Divider()

          // 2. Interactive Simulator
          inspectorSimulatorSection

          Divider()

          // 3. Fallback Optical Sliders
          inspectorSlidersSection

          Divider()

          // 4. Composite Layers
          inspectorLayersSection

          Divider()

          // 5. Code Exporter
          inspectorExportSection
        }
        .padding(16)
      }
    }
    .frame(width: 290)
    .background(Color(NSColor.windowBackgroundColor))
  }

  private var inspectorGlobalSection: some View {
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
           ? "Toàn bộ cửa sổ Snapzy đang dùng Solid Native Fallback."
           : "Ứng dụng dùng macOS 26+ Apple Glass (hoặc Solid Fallback trên macOS cũ).")
        .font(.system(size: 10))
        .foregroundStyle(isAppForcedLegacy ? .orange : .secondary)
        .lineSpacing(1.5)
    }
  }

  private var inspectorSimulatorSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Interactive Simulator")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 8) {
        Toggle("Mô phỏng Disabled", isOn: $simulateDisabled)
          .font(.system(size: 11))

        Toggle("Mô phỏng Đang bận (Busy)", isOn: $simulateBusy)
          .font(.system(size: 11))
      }
    }
  }

  private var inspectorSlidersSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Thông Số macOS 13–15")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.secondary)

        Spacer()

        Button("Đặt lại") {
          tuning = LiquidGlassTuning.default
        }
        .buttonStyle(.plain)
        .font(.system(size: 10.5))
        .foregroundStyle(Color.accentColor)
      }

      // Slider 1: Substrate
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text("1. Substrate nền:")
            .font(.system(size: 11, weight: .medium))
          Spacer()
          Text(String(format: "%.2f", tuning.substrateOpacity))
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        Slider(value: $tuning.substrateOpacity, in: 0.0...0.80, step: 0.02)
      }

      // Slider 2: Sheen
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text("2. Sheen phản xạ:")
            .font(.system(size: 11, weight: .medium))
          Spacer()
          Text(String(format: "%.2f", tuning.sheenTopOpacity))
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        Slider(value: $tuning.sheenTopOpacity, in: 0.0...0.30, step: 0.01)
      }

      // Slider 3: Specular Hairline
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text("4. Viền Specular 0.5pt:")
            .font(.system(size: 11, weight: .medium))
          Spacer()
          Text(String(format: "%.2f", tuning.specularTopOpacity))
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        Slider(value: $tuning.specularTopOpacity, in: 0.0...0.50, step: 0.02)
      }
    }
  }

  private var inspectorLayersSection: some View {
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

  private var inspectorExportSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Xuất Tokens Cho Codebase")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)

      Button {
        copySwiftTokensToClipboard()
      } label: {
        HStack {
          Image(systemName: hasCopiedCode ? "checkmark" : "doc.on.doc")
          Text(hasCopiedCode ? "Đã chép mã Swift!" : "Sao chép Swift Tokens")
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(hasCopiedCode ? .green : .accentColor)
      .controlSize(.regular)
    }
  }

  private func copySwiftTokensToClipboard() {
    let code = """
    // Snapzy Liquid Glass Fallback Tuning Preset
    let tuning = LiquidGlassTuning(
      substrateOpacity: \(String(format: "%.2f", tuning.substrateOpacity)),
      sheenTopOpacity: \(String(format: "%.2f", tuning.sheenTopOpacity)),
      sheenBottomOpacity: \(String(format: "%.2f", tuning.sheenBottomOpacity)),
      specularTopOpacity: \(String(format: "%.2f", tuning.specularTopOpacity)),
      specularBottomOpacity: \(String(format: "%.2f", tuning.specularBottomOpacity)),
      isSubstrateEnabled: \(tuning.isSubstrateEnabled),
      isRefractionEnabled: \(tuning.isRefractionEnabled),
      isVeilEnabled: \(tuning.isVeilEnabled),
      isSpecularEnabled: \(tuning.isSpecularEnabled),
      isRimLightingEnabled: \(tuning.isRimLightingEnabled)
    )
    """

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(code, forType: .string)

    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
      hasCopiedCode = true
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
      withAnimation {
        hasCopiedCode = false
      }
    }
  }
}

// MARK: - Xcode Preview

#Preview {
  LiquidGlassPlaygroundView()
}
