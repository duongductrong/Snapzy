//
//  PreferencesMenuBarPreview.swift
//  Snapzy
//
//  Live preview for the Menu Bar tab: a cropped top-right corner of a Mac
//  display showing the Snapzy status item and its open menu, reflecting the
//  current icon style and item order/visibility.
//

import SwiftUI

struct MenuBarSettingsPreview: View {
  @ObservedObject var store: MenuBarCustomizationStore

  @State private var hoveredRow: String?

  private let iconRenderer = MenuBarIconRenderer.shared
  private let shortcutManager = KeyboardShortcutManager.shared

  private let previewHeight: CGFloat = 300
  private let menuBarHeight: CGFloat = 24

  var body: some View {
    DisplayCornerFrame {
      screen
    }
    .frame(height: previewHeight)
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.PreferencesMenuBar.iconSection)
  }

  private var screen: some View {
    ZStack(alignment: .topLeading) {
      PaintedSkyBackdrop()

      menuBar
    }
    .overlayPreferenceValue(MenuBarPreviewIconAnchorKey.self) { anchor in
      GeometryReader { proxy in
        if let anchor {
          let iconRect = proxy[anchor]
          menuPanel(maxHeight: proxy.size.height - iconRect.maxY - 18)
            .offset(x: iconRect.minX - 4, y: iconRect.maxY + 2)
        }
      }
    }
  }

  // MARK: - Menu Bar

  private var menuBar: some View {
    HStack(spacing: 0) {
      Spacer(minLength: 0)

      // Neighbouring third-party items, faded so the crop reads as continuing left.
      statusGlyph("cloud")
        .opacity(0.45)
      statusGlyph("circle.hexagongrid")
        .opacity(0.7)

      snapzyStatusItem

      statusGlyph("battery.75percent")
      statusGlyph("wifi")
      statusGlyph("switch.2")

      TimelineView(.everyMinute) { context in
        Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
          .font(.system(size: 12.5, weight: .medium))
          .monospacedDigit()
          .foregroundStyle(.white)
          .lineLimit(1)
          .fixedSize()
      }
      .padding(.leading, 6)
      .padding(.trailing, 14)
    }
    .frame(height: menuBarHeight)
    .background(
      LinearGradient(
        colors: [Color.white.opacity(0.14), Color.white.opacity(0.08)],
        startPoint: .top,
        endPoint: .bottom
      )
      .background(Color.black.opacity(0.18))
    )
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.black.opacity(0.25))
        .frame(height: 0.5)
    }
  }

  private func statusGlyph(_ symbolName: String) -> some View {
    Image(systemName: symbolName)
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.white)
      .frame(width: 30, height: menuBarHeight)
  }

  /// The Snapzy status item, shown pressed because its menu is open.
  private var snapzyStatusItem: some View {
    Group {
      if let image = iconRenderer.statusImage(for: store.iconStyle) {
        Image(nsImage: image)
          .renderingMode(.template)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .frame(width: 16, height: 16)
      } else {
        Image(systemName: "camera.viewfinder")
          .font(.system(size: 13, weight: .medium))
      }
    }
    .foregroundStyle(.white)
    .frame(width: 30, height: 20)
    .background(
      RoundedRectangle(cornerRadius: 5, style: .continuous) // radius-lint:allow mimics macOS status item highlight
        .fill(Color.white.opacity(0.24))
    )
    .padding(.horizontal, 2)
    .anchorPreference(key: MenuBarPreviewIconAnchorKey.self, value: .bounds) { $0 }
    .animation(.easeInOut(duration: 0.15), value: store.iconStyle)
  }

  // MARK: - Menu Panel

  private func menuPanel(maxHeight: CGFloat) -> some View {
    ViewThatFits(in: .vertical) {
      menuContent
      ScrollView(.vertical, showsIndicators: false) {
        menuContent
      }
      .mask(
        VStack(spacing: 0) {
          Color.black
          LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 28)
        }
      )
    }
    .frame(width: 252)
    .frame(maxHeight: max(maxHeight, 0), alignment: .top)
    .modifier(MenuBarPreviewGlassPanel(shape: menuShape))
    .shadow(color: Color.black.opacity(0.28), radius: 22, x: 0, y: 12)
    .shadow(color: Color.black.opacity(0.12), radius: 1.5, x: 0, y: 0.5)
  }

  private var menuShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 13, style: .continuous) // radius-lint:allow mimics macOS 26 menu panel
  }

  private var menuContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      let groups = MenuBarItemGroup.allCases
        .map { store.orderedVisibleItems(for: $0) }
        .filter { !$0.isEmpty }

      ForEach(Array(groups.enumerated()), id: \.offset) { _, items in
        ForEach(items, id: \.rawValue) { item in
          menuRow(
            id: item.rawValue,
            symbol: item.systemImage,
            title: menuTitle(for: item),
            shortcut: shortcutText(for: item)
          )
        }
        menuSeparator
      }

      if !store.isHidden(.checkForUpdates) {
        menuRow(
          id: MenuBarItemKind.checkForUpdates.rawValue,
          symbol: MenuBarItemKind.checkForUpdates.systemImage,
          title: MenuBarItemKind.checkForUpdates.settingsTitle,
          shortcut: nil
        )
      }
      menuRow(id: "preferences", symbol: "gear", title: L10n.Menu.preferences, shortcut: "⌘,")
      menuRow(
        id: "onboarding",
        symbol: "arrow.counterclockwise.circle",
        title: L10n.PreferencesGeneral.restartOnboardingTitle,
        shortcut: nil
      )
      menuSeparator
      menuRow(id: "quit", symbol: "power", title: L10n.Menu.quitSnapzy, shortcut: "⌘Q")
    }
    .padding(5)
    .animation(.easeInOut(duration: 0.18), value: store.itemOrder)
    .animation(.easeInOut(duration: 0.18), value: store.hiddenItems)
  }

  private func menuRow(id: String, symbol: String, title: String, shortcut: String?) -> some View {
    let isHovered = hoveredRow == id

    return HStack(spacing: 7) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .regular))
        .frame(width: 16)

      Text(title)
        .font(.system(size: 13))
        .lineLimit(1)

      Spacer(minLength: 12)

      if let shortcut {
        Text(shortcut)
          .font(.system(size: 12.5))
          .foregroundStyle(isHovered ? Color.white.opacity(0.85) : Color.secondary)
      }
    }
    .foregroundStyle(isHovered ? Color.white : Color.primary)
    .padding(.horizontal, 8)
    .frame(height: 22)
    .background(
      RoundedRectangle(cornerRadius: 5, style: .continuous) // radius-lint:allow mimics NSMenu selection
        .fill(isHovered ? Color.accentColor : Color.clear)
    )
    .contentShape(Rectangle())
    .onHover { hovering in
      if hovering {
        hoveredRow = id
      } else if hoveredRow == id {
        hoveredRow = nil
      }
    }
    .transition(.opacity)
  }

  private var menuSeparator: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.1))
      .frame(height: 1)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
  }

  // MARK: - Content Mapping

  /// Mirrors the titles AppStatusBarController builds, including delay seconds.
  private func menuTitle(for item: MenuBarItemKind) -> String {
    switch item {
    case .captureDelayed:
      return L10n.Menu.delayedCapture(CaptureDelayOption.current().seconds)
    case .captureDelayedFullscreen:
      return L10n.Menu.delayedFullscreenCapture(CaptureDelayOption.current().seconds)
    default:
      return item.settingsTitle
    }
  }

  private func shortcutText(for item: MenuBarItemKind) -> String? {
    guard let kind = shortcutKind(for: item),
          shortcutManager.isShortcutEnabled(for: kind),
          let config = shortcutManager.shortcut(for: kind) else { return nil }

    // NSMenu orders modifiers ⌃⌥⇧⌘ with no spacing.
    let parts = config.displayParts
    let modifierOrder = ["⌃", "⌥", "⇧", "⌘", "fn"]
    let modifiers = modifierOrder.filter { parts.contains($0) }
    let keys = parts.filter { !modifierOrder.contains($0) }
    return (modifiers + keys).joined()
  }

  private func shortcutKind(for item: MenuBarItemKind) -> GlobalShortcutKind? {
    switch item {
    case .captureArea: return .area
    case .captureAreaAnnotate: return .areaAnnotate
    case .captureFullscreen: return .fullscreen
    case .captureActiveWindow: return .activeWindow
    case .scrollingCapture: return .scrollingCapture
    case .captureOCR: return .ocr
    case .captureSmartElement: return .smartElement
    case .captureObjectCutout: return .objectCutout
    case .captureDelayed: return .delayedCapture
    case .captureDelayedFullscreen: return .delayedFullscreen
    case .recordScreen: return .recording
    case .openAnnotate: return .annotate
    case .pickColor: return .pickColor
    case .editVideo: return .videoEditor
    case .cloudUploads: return .cloudUploads
    case .openHistory: return .history
    case .shortcutList: return .shortcutList
    case .captureApplication, .recordApplication, .combineImages, .checkForUpdates:
      return nil
    }
  }
}

// MARK: - Glass Panel

/// Liquid Glass menu chrome. On macOS 26 the native `.regular` glass — the same
/// material NSMenu uses — frosts and refracts the wallpaper and adapts its content
/// tone; older systems fall back to a tinted composite.
private struct MenuBarPreviewGlassPanel<S: InsettableShape>: ViewModifier {
  let shape: S

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content
        .glassEffect(.regular, in: shape)
        .overlay(rim)
    } else {
      content
        .background(
          ZStack {
            shape.fill(Color(red: 0.06, green: 0.12, blue: 0.38).opacity(0.72))
            shape.fill(
              LinearGradient(
                colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
          }
        )
        .clipShape(shape)
        .overlay(rim)
    }
  }

  /// Specular rim: bright where light hits the top edge, fading along the sides, with a
  /// faint dark outer hairline that separates the panel from bright wallpaper.
  private var rim: some View {
    ZStack {
      shape.strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
      shape
        .inset(by: 0.5)
        .strokeBorder(
          LinearGradient(
            colors: [
              Color.white.opacity(0.32),
              Color.white.opacity(0.12),
              Color.white.opacity(0.06),
              Color.white.opacity(0.22),
            ],
            startPoint: .top,
            endPoint: .bottom
          ),
          lineWidth: 0.75
        )
    }
    .allowsHitTesting(false)
  }
}

// MARK: - Supporting Types

private struct MenuBarPreviewIconAnchorKey: PreferenceKey {
  static var defaultValue: Anchor<CGRect>?
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = value ?? nextValue()
  }
}


#Preview {
  MenuBarSettingsPreview(store: MenuBarCustomizationStore.shared)
    .padding()
    .frame(width: 600)
}
