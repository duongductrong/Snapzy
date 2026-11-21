//
//  SnapzyMockSystemSettingsWindow.swift
//  Snapzy
//
//  Faithful macOS System Settings (Keyboard Shortcuts → Screenshots sheet) in Light Mode
//  for Step 3 onboarding. Guides users on disabling conflicting native macOS screenshot keys.
//

import SwiftUI

struct SnapzyMockSystemSettingsWindow: View {
  @Binding var hasFullscreenConflict: Bool
  @Binding var hasAreaConflict: Bool
  @Binding var hasRecordingConflict: Bool
  var onConflictChanged: ((Bool, Bool, Bool) -> Void)? = nil
  var onResolveAll: (() -> Void)? = nil
  var onOpenRealSettings: (() -> Void)? = nil

  @State private var hoveredRow: String? = nil
  @State private var isOpenSettingsHovered: Bool = false
  @State private var isRestoreHovered: Bool = false

  var body: some View {
    ZStack(alignment: .top) {
      // 1. Background System Settings Window (Authentic macOS Split-View Keyboard Pane)
      backgroundSettingsWindow

      // 2. Dimming Sheet Backdrop (Standard macOS modal presentation)
      Color.black.opacity(0.16)
        .clipShape(Radius.rect(Radius.card))

      // 3. Modal Sheet anchored cleanly beneath the window titlebar (like real macOS sheets)
      keyboardShortcutsSheet
        .padding(.top, 28)
    }
    .frame(width: 512, height: 310)
    .clipShape(Radius.rect(Radius.card))
    .overlay(
      Radius.rect(Radius.card)
        .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.24), radius: 22, x: 0, y: 10)
    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
  }

  // MARK: - 1. Background System Settings Window (Authentic Full-Height Sidebar)

  private var backgroundSettingsWindow: some View {
    HStack(spacing: 0) {
      // Full-height macOS System Settings Sidebar
      VStack(alignment: .leading, spacing: 6) {
        SnapzyMockTrafficLights(size: 9.5, spacing: 6)
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 2)

        // Sidebar Search Field (positioned directly under traffic lights like real macOS Settings)
        HStack(spacing: 4) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 8.5))
            .foregroundStyle(Color.black.opacity(0.42))
          Text("Search")
            .font(.system(size: 9.5))
            .foregroundStyle(Color.black.opacity(0.42))
          Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .background(
          Radius.rect(Radius.controlXS)
            .fill(Color.black.opacity(0.06))
        )
        .padding(.horizontal, 8)

        HStack(spacing: 6) {
          Circle()
            .fill(Color.gray.opacity(0.32))
            .frame(width: 20, height: 20)
            .overlay(Image(systemName: "person.fill").font(.system(size: 9)).foregroundStyle(Color.white))
          VStack(alignment: .leading, spacing: 0.5) {
            Text("User Account")
              .font(.system(size: 8.5, weight: .semibold))
              .foregroundStyle(SnapzyMockPalette.ink.opacity(0.85))
            Text("Apple Account")
              .font(.system(size: 7.5))
              .foregroundStyle(SnapzyMockPalette.inkTertiary)
          }
        }
        .padding(.horizontal, 9)
        .padding(.top, 2)

        Rectangle()
          .fill(Color.black.opacity(0.06))
          .frame(height: 0.5)
          .padding(.horizontal, 8)

        VStack(spacing: 2) {
          bgSidebarItem(icon: "gearshape.fill", title: "General", badgeColor: Color.gray)
          bgSidebarItem(icon: "sun.max.fill", title: "Displays", badgeColor: SnapzyMockPalette.macBlue)
          bgSidebarItem(icon: "keyboard", title: "Keyboard", badgeColor: Color(white: 0.48), isSelected: false)
          bgSidebarItem(icon: "hand.raised.fill", title: "Privacy & Security", badgeColor: SnapzyMockPalette.macBlue)
        }

        Spacer()
      }
      .frame(width: 136)
      .background(Color(red: 0.942, green: 0.946, blue: 0.955))

      Rectangle()
        .fill(Color.black.opacity(0.09))
        .frame(width: 0.5)

      // Right Detail Pane (Titlebar + Grouped Settings Card)
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 8) {
          HStack(spacing: 6) {
            Image(systemName: "chevron.left")
              .foregroundStyle(Color.black.opacity(0.45))
            Image(systemName: "chevron.right")
              .foregroundStyle(Color.black.opacity(0.18))
          }
          .font(.system(size: 9.5, weight: .semibold))

          Text("Keyboard")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(SnapzyMockPalette.ink)

          Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Color(red: 0.968, green: 0.970, blue: 0.976))

        Rectangle()
          .fill(Color.black.opacity(0.06))
          .frame(height: 0.5)

        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Key repeat rate")
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(Color.black.opacity(0.72))
            sliderTrackPreview
          }
          VStack(alignment: .leading, spacing: 4) {
            Text("Delay until repeat")
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(Color.black.opacity(0.72))
            sliderTrackPreview
          }
          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.962, green: 0.965, blue: 0.972))
      }
    }
  }

  private func bgSidebarItem(icon: String, title: String, badgeColor: Color, isSelected: Bool = false) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(Color.white)
        .frame(width: 15, height: 15)
        .background(
          Radius.rect(Radius.ornament)
            .fill(isSelected ? Color.white.opacity(0.24) : badgeColor)
        )
      Text(title)
        .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? Color.white : SnapzyMockPalette.ink.opacity(0.82))
        .lineLimit(1)
      Spacer()
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3.5)
    .background(
      Radius.rect(Radius.controlXS)
        .fill(isSelected ? SnapzyMockPalette.macBlue : Color.clear)
    )
    .padding(.horizontal, 7)
  }

  private var sliderTrackPreview: some View {
    ZStack(alignment: .leading) {
      Capsule()
        .fill(Color.black.opacity(0.12))
        .frame(height: 3.5)
      Circle()
        .fill(Color.white)
        .frame(width: 10, height: 10)
        .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
        .offset(x: 80)
    }
    .frame(width: 140)
  }

  // MARK: - 2. Modal Sheet (Keyboard Shortcuts → Screenshots)

  private var keyboardShortcutsSheet: some View {
    VStack(spacing: 0) {
      // Sheet Main Content (Categories sidebar + Screenshots list)
      HStack(spacing: 0) {
        // Left Column: Categories list (Authentic 14 macOS categories)
        sheetCategoriesSidebar
          .frame(width: 154)

        Rectangle()
          .fill(Color.black.opacity(0.08))
          .frame(width: 0.5)

        // Right Column: Screenshots Shortcuts List
        sheetShortcutsPane
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      Rectangle()
        .fill(Color.black.opacity(0.08))
        .frame(height: 0.5)

      // Sheet Footer Bar
      sheetFooterBar
    }
    .frame(width: 484, height: 264)
    .background(Color.white)
    .clipShape(Radius.rect(Radius.controlL))
    .overlay(
      Radius.rect(Radius.controlL)
        .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.32), radius: 18, x: 0, y: 8)
    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
  }

  // MARK: - Categories Sidebar

  private var sheetCategoriesSidebar: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 1.5) {
        sheetCategoryRow(title: "Dock", icon: "dock.rectangle", isSelected: false)
        sheetCategoryRow(title: "Display", icon: "sun.max.fill", isSelected: false)
        sheetCategoryRow(title: "Mission Control", icon: "rectangle.split.2x1", isSelected: false)
        sheetCategoryRow(title: "Windows", icon: "macwindow.on.rectangle", isSelected: false)
        sheetCategoryRow(title: "Keyboard", icon: "keyboard", isSelected: false)
        sheetCategoryRow(title: "Input Sources", icon: "character.cursor.ibeam", isSelected: false)
        sheetCategoryRow(title: "Screenshots", icon: "camera.viewfinder", isSelected: true)
        sheetCategoryRow(title: "Presenter Overlay", icon: "person.crop.square", isSelected: false)
        sheetCategoryRow(title: "Services", icon: "gearshape.2", isSelected: false)
        sheetCategoryRow(title: "Spotlight", icon: "magnifyingglass", isSelected: false)
        sheetCategoryRow(title: "Accessibility", icon: "figure.walk.circle", isSelected: false)
        sheetCategoryRow(title: "App Shortcuts", icon: "slider.horizontal.3", isSelected: false)
        sheetCategoryRow(title: "Function Keys", icon: "f.cursive", isSelected: false)
        sheetCategoryRow(title: "Modifier Keys", icon: "command", isSelected: false)
      }
      .padding(.vertical, 5)
    }
    .background(Color(red: 0.955, green: 0.958, blue: 0.965))
  }

  private func sheetCategoryRow(title: String, icon: String, isSelected: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 9.5, weight: .medium))
        .frame(width: 14)
      Text(title)
        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.82))
    .padding(.horizontal, 7)
    .padding(.vertical, 3.5)
    .background(
      Radius.rect(Radius.controlXS)
        .fill(isSelected ? SnapzyMockPalette.macBlue : Color.clear)
    )
    .padding(.horizontal, 5)
  }

  // MARK: - Screenshots Shortcuts Pane

  private var sheetShortcutsPane: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Quiet native macOS header note + single clean status indicator (zero noisy warning banners)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("To change a shortcut, double click the key combination, then type the new keys.")
          .font(.system(size: 9, weight: .regular))
          .foregroundStyle(Color.black.opacity(0.52))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 4)

        HStack(spacing: 4) {
          Circle()
            .fill(hasAnyConflict ? Color.orange : Color.green)
            .frame(width: 5.5, height: 5.5)

          Text(hasAnyConflict ? L10n.Onboarding.mockConflictsActive : L10n.Onboarding.mockNoConflicts)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.62))
        }
        .fixedSize()
      }
      .padding(.horizontal, 12)
      .padding(.top, 10)
      .padding(.bottom, 8)

      Rectangle()
        .fill(Color.black.opacity(0.07))
        .frame(height: 0.5)

      // 5 macOS Screenshot Shortcuts in Exact Native Order
      VStack(spacing: 1) {
        // 1. Fullscreen to file (⇧⌘3) - Conflict with Snapzy Fullscreen
        shortcutItemRow(
          id: "screen",
          title: "Save picture of screen as a file",
          keys: "⇧⌘3",
          isChecked: hasFullscreenConflict,
          hasConflict: hasFullscreenConflict
        ) {
          withAnimation(.easeInOut(duration: 0.18)) {
            hasFullscreenConflict.toggle()
            notifyChanges()
          }
        }

        // 2. Fullscreen to clipboard (⌃⇧⌘3)
        shortcutItemRow(
          id: "copyScreen",
          title: "Copy picture of screen to the clipboard",
          keys: "⌃⇧⌘3",
          isChecked: false,
          hasConflict: false
        ) {}

        // 3. Selected area to file (⇧⌘4) - Conflict with Snapzy Area
        shortcutItemRow(
          id: "area",
          title: "Save picture of selected area as a file",
          keys: "⇧⌘4",
          isChecked: hasAreaConflict,
          hasConflict: hasAreaConflict
        ) {
          withAnimation(.easeInOut(duration: 0.18)) {
            hasAreaConflict.toggle()
            notifyChanges()
          }
        }

        // 4. Selected area to clipboard (⌃⇧⌘4)
        shortcutItemRow(
          id: "copyArea",
          title: "Copy picture of selected area to the clipboard",
          keys: "⌃⇧⌘4",
          isChecked: false,
          hasConflict: false
        ) {}

        // 5. Screenshot and recording options (⇧⌘5) - Conflict with Snapzy Recording
        shortcutItemRow(
          id: "recording",
          title: "Screenshot and recording options",
          keys: "⇧⌘5",
          isChecked: hasRecordingConflict,
          hasConflict: hasRecordingConflict
        ) {
          withAnimation(.easeInOut(duration: 0.18)) {
            hasRecordingConflict.toggle()
            notifyChanges()
          }
        }
      }
      .padding(.vertical, 6)

      Spacer(minLength: 0)
    }
    .background(Color.white)
  }

  private func shortcutItemRow(
    id: String,
    title: String,
    keys: String,
    isChecked: Bool,
    hasConflict: Bool,
    onToggle: @escaping () -> Void
  ) -> some View {
    Button(action: onToggle) {
      HStack(spacing: 8) {
        // Native macOS Checkbox
        ZStack {
          Radius.rect(Radius.ornament)
            .fill(isChecked ? SnapzyMockPalette.macBlue : Color.white)
            .frame(width: 13.5, height: 13.5)

          Radius.rect(Radius.ornament)
            .strokeBorder(isChecked ? SnapzyMockPalette.macBlue : Color.black.opacity(0.28), lineWidth: 0.75)
            .frame(width: 13.5, height: 13.5)

          if isChecked {
            Image(systemName: "checkmark")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(Color.white)
          }
        }

        // Shortcut Description
        Text(title)
          .font(.system(size: 9.5, weight: .regular))
          .foregroundStyle(SnapzyMockPalette.ink.opacity(0.90))
          .lineLimit(1)

        Spacer(minLength: 6)

        // Quiet dot marks conflicting macOS shortcuts without repeating loud orange pills
        if hasConflict {
          Circle()
            .fill(Color.orange)
            .frame(width: 5, height: 5)
        }

        // Native macOS right-aligned shortcut glyphs (clean, unboxed)
        Text(keys)
          .font(.system(size: 9.5, weight: .medium, design: .monospaced))
          .foregroundStyle(hasConflict ? SnapzyMockPalette.ink.opacity(0.85) : Color.black.opacity(0.45))
          .frame(minWidth: 34, alignment: .trailing)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5.5)
      .background(
        Radius.rect(Radius.ornament)
          .fill(hoveredRow == id ? Color.black.opacity(0.045) : Color.clear)
      )
      .padding(.horizontal, 4)
    }
    .buttonStyle(.plain)
    .onHover { h in hoveredRow = h ? id : nil }
  }

  // MARK: - Sheet Footer Bar

  private var sheetFooterBar: some View {
    HStack(spacing: 8) {
      // Restore Defaults Button (Native macOS white push button)
      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          hasFullscreenConflict = true
          hasAreaConflict = true
          hasRecordingConflict = true
          notifyChanges()
        }
      } label: {
        Text(L10n.Onboarding.mockRestoreDefaults)
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(SnapzyMockPalette.ink.opacity(0.86))
          .padding(.horizontal, 9)
          .padding(.vertical, 4)
          .background(
            Radius.rect(Radius.controlXS)
              .fill(isRestoreHovered ? Color(white: 0.94) : Color.white)
              .overlay(
                Radius.rect(Radius.controlXS)
                  .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
              )
              .shadow(color: Color.black.opacity(0.06), radius: 1, y: 0.5)
          )
      }
      .buttonStyle(.plain)
      .onHover { h in isRestoreHovered = h }

      // Direct macOS System Settings Link
      Button {
        onOpenRealSettings?()
      } label: {
        HStack(spacing: 3.5) {
          Text(L10n.Onboarding.mockOpenSystemSettings)
            .font(.system(size: 9.5, weight: .medium))
          Image(systemName: "arrow.up.right")
            .font(.system(size: 7.5, weight: .semibold))
        }
        .foregroundStyle(SnapzyMockPalette.macBlue)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
          Radius.rect(Radius.controlXS)
            .fill(isOpenSettingsHovered ? SnapzyMockPalette.macBlue.opacity(0.08) : Color.clear)
        )
      }
      .buttonStyle(.plain)
      .onHover { h in isOpenSettingsHovered = h }
      .help("Open macOS System Settings → Keyboard → Keyboard Shortcuts → Screenshots")

      Spacer()

      // Standard Done button (Apple Blue default push button — also resolves conflicts cleanly)
      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          hasFullscreenConflict = false
          hasAreaConflict = false
          hasRecordingConflict = false
          notifyChanges()
        }
      } label: {
        Text(L10n.Onboarding.mockDone)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Color.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 4)
          .background(
            Radius.rect(Radius.controlXS)
              .fill(SnapzyMockPalette.macBlue)
              .shadow(color: Color.black.opacity(0.12), radius: 1, y: 0.5)
          )
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(Color(red: 0.955, green: 0.958, blue: 0.965))
  }

  // MARK: - Helpers

  private var hasAnyConflict: Bool {
    hasFullscreenConflict || hasAreaConflict || hasRecordingConflict
  }

  private func notifyChanges() {
    onConflictChanged?(hasFullscreenConflict, hasAreaConflict, hasRecordingConflict)
    if !hasAnyConflict {
      onResolveAll?()
    }
  }
}
