//
//  AppearanceThumbnailView.swift
//  ClaudeShot
//
//  Visual thumbnail picker for appearance mode, styled like macOS System Preferences
//

import SwiftUI

/// Individual appearance mode thumbnail with window chrome preview
struct AppearanceThumbnailView: View {
  let mode: AppearanceMode
  let isSelected: Bool
  let action: () -> Void

  private var isDarkPreview: Bool {
    switch mode {
    case .system:
      // Show split light/dark for system mode
      return false
    case .light:
      return false
    case .dark:
      return true
    }
  }

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        thumbnailPreview
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
          )
          .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

        Text(mode.displayName)
          .font(.system(size: 12))
          .foregroundColor(isSelected ? .accentColor : .primary)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var thumbnailPreview: some View {
    if mode == .system {
      // Split view for Auto mode - left light, right dark
      splitThumbnail
    } else {
      // Single mode thumbnail
      singleThumbnail(isDark: isDarkPreview)
    }
  }

  // MARK: - Split Thumbnail (Auto mode)

  private var splitThumbnail: some View {
    ZStack {
      HStack(spacing: 0) {
        // Light half
        windowPreview(isDark: false)
          .clipShape(
            UnevenRoundedRectangle(
              topLeadingRadius: 8,
              bottomLeadingRadius: 8,
              bottomTrailingRadius: 0,
              topTrailingRadius: 0
            )
          )

        // Dark half
        windowPreview(isDark: true)
          .clipShape(
            UnevenRoundedRectangle(
              topLeadingRadius: 0,
              bottomLeadingRadius: 0,
              bottomTrailingRadius: 8,
              topTrailingRadius: 8
            )
          )
      }
    }
    .frame(width: 90, height: 64)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  // MARK: - Single Thumbnail

  private func singleThumbnail(isDark: Bool) -> some View {
    windowPreview(isDark: isDark)
      .frame(width: 90, height: 64)
      .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  // MARK: - Window Preview

  private func windowPreview(isDark: Bool) -> some View {
    VStack(spacing: 0) {
      // Title bar with traffic lights
      HStack(spacing: 4) {
        // Traffic lights
        Circle()
          .fill(Color.red.opacity(0.9))
          .frame(width: 6, height: 6)
        Circle()
          .fill(Color.yellow.opacity(0.9))
          .frame(width: 6, height: 6)
        Circle()
          .fill(Color.green.opacity(0.9))
          .frame(width: 6, height: 6)

        Spacer()
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 5)
      .background(isDark ? Color(white: 0.22) : Color(white: 0.92))

      // Window content area with mock sidebar and content
      HStack(spacing: 0) {
        // Sidebar
        VStack(spacing: 3) {
          ForEach(0..<3, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 2)
              .fill(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
              .frame(height: 4)
          }
          Spacer()
        }
        .padding(4)
        .frame(width: 22)
        .background(isDark ? Color(white: 0.18) : Color(white: 0.95))

        // Content area
        VStack(spacing: 3) {
          RoundedRectangle(cornerRadius: 2)
            .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
            .frame(height: 6)
          RoundedRectangle(cornerRadius: 2)
            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
            .frame(height: 4)
          Spacer()
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(isDark ? Color(white: 0.14) : Color.white)
      }
    }
    .background(isDark ? Color(white: 0.14) : Color.white)
  }
}

/// Horizontal picker showing all appearance mode thumbnails
struct AppearanceModePicker: View {
  @Binding var selection: AppearanceMode

  var body: some View {
    HStack(spacing: 20) {
      ForEach(AppearanceMode.allCases) { mode in
        AppearanceThumbnailView(
          mode: mode,
          isSelected: selection == mode
        ) {
          withAnimation(.easeInOut(duration: 0.15)) {
            selection = mode
          }
        }
      }
    }
    .padding(.vertical, 8)
  }
}

#Preview("Appearance Picker") {
  VStack {
    AppearanceModePicker(selection: .constant(.system))
  }
  .padding()
  .frame(width: 400)
}

#Preview("Individual Thumbnails") {
  HStack(spacing: 20) {
    AppearanceThumbnailView(mode: .system, isSelected: true) {}
    AppearanceThumbnailView(mode: .light, isSelected: false) {}
    AppearanceThumbnailView(mode: .dark, isSelected: false) {}
  }
  .padding()
}
