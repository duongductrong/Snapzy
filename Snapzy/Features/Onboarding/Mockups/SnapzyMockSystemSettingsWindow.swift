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
    ZStack {
      // 1. Background System Settings Window (Keyboard Pane)
      backgroundSettingsWindow

      // 2. Dimming Sheet Backdrop (Standard macOS modal presentation)
      Color.black.opacity(0.18)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

      // 3. Modal Sheet (Keyboard Shortcuts → Screenshots)
      keyboardShortcutsSheet
    }
    .frame(width: 512, height: 324)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.26), radius: 24, x: 0, y: 10)
    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
  }

  // MARK: - 1. Background System Settings Window (Keyboard Pane)

  private var backgroundSettingsWindow: some View {
    VStack(spacing: 0) {
      // Background Window Titlebar
      HStack(spacing: 8) {
        // Traffic lights
        HStack(spacing: 6) {
          Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.33)).frame(width: 9.5, height: 9.5)
          Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 9.5, height: 9.5)
          Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 9.5, height: 9.5)
        }
        .padding(.leading, 12)

        // Simulated Search Field
        HStack(spacing: 4) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 8.5))
            .foregroundStyle(Color.black.opacity(0.40))
          Text("Search")
            .font(.system(size: 9.5))
            .foregroundStyle(Color.black.opacity(0.40))
          Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: 110)
        .background(
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.black.opacity(0.05))
        )
        .padding(.leading, 6)

        Spacer()

        // Nav chevrons + Keyboard title
        HStack(spacing: 6) {
          HStack(spacing: 3) {
            Image(systemName: "chevron.left")
            Image(systemName: "chevron.right")
          }
          .font(.system(size: 8.5, weight: .semibold))
          .foregroundStyle(Color.black.opacity(0.35))
          .padding(.horizontal, 5)
          .padding(.vertical, 2.5)
          .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.04)))

          Text("Keyboard")
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.85))
        }

        Spacer()

        Color.clear.frame(width: 110, height: 1)
      }
      .frame(height: 32)
      .background(Color(red: 0.940, green: 0.943, blue: 0.950))

      Rectangle()
        .fill(Color.black.opacity(0.08))
        .frame(height: 0.5)

      // Background Window Content (Sidebar + Sliders preview)
      HStack(spacing: 0) {
        // Left background sidebar
        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 6) {
            Circle()
              .fill(Color.gray.opacity(0.35))
              .frame(width: 18, height: 18)
              .overlay(Image(systemName: "person.fill").font(.system(size: 8.5)).foregroundStyle(Color.gray))
            VStack(alignment: .leading, spacing: 0) {
              Text("User Account")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.75))
              Text("Apple Account")
                .font(.system(size: 7.5))
                .foregroundStyle(Color.black.opacity(0.40))
            }
          }
          .padding(.horizontal, 8)
          .padding(.top, 6)

          Rectangle().fill(Color.black.opacity(0.06)).frame(height: 0.5)

          bgSidebarItem(icon: "sun.max.fill", title: "Displays", color: .blue)
          bgSidebarItem(icon: "keyboard", title: "Keyboard", color: .gray, isSelected: true)
          bgSidebarItem(icon: "gearshape.2.fill", title: "General", color: .gray)
          Spacer()
        }
        .frame(width: 125)
        .background(Color(red: 0.948, green: 0.951, blue: 0.958))

        Rectangle().fill(Color.black.opacity(0.08)).frame(width: 0.5)

        // Right background keyboard controls preview
        VStack(alignment: .leading, spacing: 14) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Key repeat rate")
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(Color.black.opacity(0.70))
            sliderTrackPreview
          }
          VStack(alignment: .leading, spacing: 4) {
            Text("Delay until repeat")
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(Color.black.opacity(0.70))
            sliderTrackPreview
          }
          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.965, green: 0.968, blue: 0.974))
      }
    }
  }

  private func bgSidebarItem(icon: String, title: String, color: Color, isSelected: Bool = false) -> some View {
    HStack(spacing: 5) {
      Image(systemName: icon)
        .font(.system(size: 8.5))
        .foregroundStyle(isSelected ? Color.white : color)
        .frame(width: 14, height: 14)
        .background(RoundedRectangle(cornerRadius: 3).fill(isSelected ? Color(red: 0.08, green: 0.46, blue: 0.96) : Color.clear))
      Text(title)
        .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? Color.white : Color.black.opacity(0.75))
      Spacer()
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(RoundedRectangle(cornerRadius: 4).fill(isSelected ? Color(red: 0.08, green: 0.46, blue: 0.96) : Color.clear))
    .padding(.horizontal, 6)
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
    .frame(width: 486, height: 268)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.36), radius: 20, x: 0, y: 8)
    .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 1)
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
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(isSelected ? Color(red: 0.08, green: 0.46, blue: 0.96) : Color.clear)
    )
    .padding(.horizontal, 5)
  }

  // MARK: - Screenshots Shortcuts Pane

  private var sheetShortcutsPane: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Top helper note (exact wording from macOS System Settings)
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text("To change a shortcut, double click the key combination, and then type the new keys.")
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(Color.black.opacity(0.55))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 4)

          if hasAnyConflict {
            HStack(spacing: 3) {
              Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
              Text(L10n.Onboarding.mockConflictsActive)
                .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange.opacity(0.12)))
          } else {
            HStack(spacing: 3) {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 8))
              Text(L10n.Onboarding.mockNoConflicts)
                .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color.green)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.green.opacity(0.12)))
          }
        }

        if hasAnyConflict {
          HStack(spacing: 4) {
            Image(systemName: "arrow.turn.down.right")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(Color.orange)
            Text(L10n.Onboarding.mockUncheckInstruction)
              .font(.system(size: 8.5, weight: .medium))
              .foregroundStyle(Color(red: 0.55, green: 0.32, blue: 0.05))
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(Color.orange.opacity(0.10))
          )
          .padding(.top, 1)
        }
      }
      .padding(.horizontal, 10)
      .padding(.top, 7)
      .padding(.bottom, 5)

      Rectangle()
        .fill(Color.black.opacity(0.06))
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
          withAnimation(.easeInOut(duration: 0.2)) {
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
          withAnimation(.easeInOut(duration: 0.2)) {
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
          withAnimation(.easeInOut(duration: 0.2)) {
            hasRecordingConflict.toggle()
            notifyChanges()
          }
        }
      }
      .padding(.vertical, 3)

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
      HStack(spacing: 7) {
        // Native macOS Checkbox
        ZStack {
          RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(isChecked ? Color(red: 0.08, green: 0.46, blue: 0.96) : Color.white)
            .frame(width: 13, height: 13)

          RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .strokeBorder(isChecked ? Color(red: 0.08, green: 0.46, blue: 0.96) : Color.black.opacity(0.30), lineWidth: 1)
            .frame(width: 13, height: 13)

          if isChecked {
            Image(systemName: "checkmark")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(Color.white)
          }
        }

        // Shortcut Description
        Text(title)
          .font(.system(size: 9.5, weight: .regular))
          .foregroundStyle(Color.black.opacity(0.85))
          .lineLimit(1)

        Spacer(minLength: 4)

        // Conflict Pill
        if hasConflict {
          Text(L10n.Onboarding.mockConflictBadge)
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.orange.opacity(0.12)))
        }

        // Keys badge
        Text(keys)
          .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
          .foregroundStyle(Color.black.opacity(0.70))
          .padding(.horizontal, 5)
          .padding(.vertical, 1.5)
          .background(
            RoundedRectangle(cornerRadius: 3.5)
              .fill(Color.black.opacity(0.05))
              .overlay(RoundedRectangle(cornerRadius: 3.5).strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5))
          )
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(hoveredRow == id ? Color.black.opacity(0.04) : Color.clear)
      )
      .padding(.horizontal, 4)
    }
    .buttonStyle(.plain)
    .onHover { h in hoveredRow = h ? id : nil }
  }

  // MARK: - Sheet Footer Bar

  private var sheetFooterBar: some View {
    HStack(spacing: 8) {
      // Restore Defaults Button (Simulates native button)
      Button {
        withAnimation(.easeInOut(duration: 0.2)) {
          hasFullscreenConflict = true
          hasAreaConflict = true
          hasRecordingConflict = true
          notifyChanges()
        }
      } label: {
        Text(L10n.Onboarding.mockRestoreDefaults)
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.75))
          .padding(.horizontal, 8)
          .padding(.vertical, 3.5)
          .background(
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
              .fill(isRestoreHovered ? Color.black.opacity(0.10) : Color.black.opacity(0.06))
          )
      }
      .buttonStyle(.plain)
      .onHover { h in isRestoreHovered = h }

      // Direct macOS System Settings Link
      Button {
        onOpenRealSettings?()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "arrow.up.forward.app")
            .font(.system(size: 8.5, weight: .bold))
          Text(L10n.Onboarding.mockOpenSystemSettings)
            .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(Color(red: 0.08, green: 0.46, blue: 0.96))
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .background(
          RoundedRectangle(cornerRadius: 4.5)
            .fill(isOpenSettingsHovered ? Color(red: 0.08, green: 0.46, blue: 0.96).opacity(0.10) : Color.clear)
        )
      }
      .buttonStyle(.plain)
      .onHover { h in isOpenSettingsHovered = h }
      .help("Open macOS System Settings → Keyboard → Keyboard Shortcuts → Screenshots")

      Spacer()

      // Quick resolve on demo
      if hasAnyConflict {
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            hasFullscreenConflict = false
            hasAreaConflict = false
            hasRecordingConflict = false
            notifyChanges()
          }
        } label: {
          Text(L10n.Onboarding.mockUncheckToResolve)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
              RoundedRectangle(cornerRadius: 4.5)
                .fill(Color.orange.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
      } else {
        HStack(spacing: 3) {
          Image(systemName: "checkmark")
            .font(.system(size: 8, weight: .bold))
          Text(L10n.Onboarding.mockShortcutsReady)
            .font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(Color.green)
      }

      // Standard Done button (Apple Blue)
      Button {
        withAnimation {
          hasFullscreenConflict = false
          hasAreaConflict = false
          hasRecordingConflict = false
          notifyChanges()
        }
      } label: {
        Text(L10n.Onboarding.mockDone)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Color.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 3.5)
          .background(
            RoundedRectangle(cornerRadius: 5)
              .fill(Color(red: 0.08, green: 0.46, blue: 0.96))
          )
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5.5)
    .background(Color(red: 0.950, green: 0.952, blue: 0.960))
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
