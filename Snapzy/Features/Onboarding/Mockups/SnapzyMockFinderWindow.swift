//
//  SnapzyMockFinderWindow.swift
//  Snapzy
//
//  Faithful macOS Finder window component for Step 3 Shortcuts & Config onboarding.
//

import SwiftUI

struct FinderRowItem: Identifiable {
  var id: String { name }
  var name: String
  var dateModified: String
  var size: String
  var kind: String
  var isFolder: Bool
}

struct SnapzyMockFinderWindow: View, Equatable {
  static func == (lhs: SnapzyMockFinderWindow, rhs: SnapzyMockFinderWindow) -> Bool {
    true
  }

  private static let items: [FinderRowItem] = [
    FinderRowItem(name: "Design Systems", dateModified: "Today, 1:52 PM", size: "--", kind: "Folder", isFolder: true),
    FinderRowItem(name: "Snapzy Captures", dateModified: "Today, 10:14 AM", size: "--", kind: "Folder", isFolder: true),
    FinderRowItem(name: "Product Roadmap.xlsx", dateModified: "Yesterday", size: "12.4 MB", kind: "Excel Document", isFolder: false),
    FinderRowItem(name: "config.toml", dateModified: "Aug 18, 2026", size: "4 KB", kind: "TOML Configuration", isFolder: false),
    FinderRowItem(name: "Release_Notes.md", dateModified: "Aug 15, 2026", size: "18 KB", kind: "Markdown", isFolder: false),
  ]

  var body: some View {
    HStack(spacing: 0) {
      // Left Navigation Sidebar (authentic full-height macOS Finder sidebar)
      sidebar
        .frame(width: 142)

      Rectangle()
        .fill(Color.black.opacity(0.08))
        .frame(width: 0.5)

      // Right Main Browser Content
      mainContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color.white)
    .clipShape(Radius.rect(Radius.card))
    .overlay(
      Radius.rect(Radius.card)
        .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.24), radius: 26, x: 0, y: 12)
    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    .accessibilityHidden(true)
  }

  // MARK: - Left Sidebar

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      SnapzyMockTrafficLights()
        .padding(.top, 13)
        .padding(.leading, 12)
        .padding(.bottom, 11)

      VStack(alignment: .leading, spacing: 1.5) {
        sidebarSectionHeader("Favorites")

        sidebarRow(title: "Applications", icon: "app.badge", isSelected: false)
        sidebarRow(title: "Desktop", icon: "menubar.dock.rectangle", isSelected: true)
        sidebarRow(title: "Documents", icon: "doc", isSelected: false)
        sidebarRow(title: "Downloads", icon: "arrow.down.circle", isSelected: false)
        sidebarRow(title: "Developer", icon: "hammer", isSelected: false)
      }
      .padding(.horizontal, 7)

      Spacer()
    }
    .background(Color(red: 0.946, green: 0.950, blue: 0.960))
  }

  private func sidebarSectionHeader(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 9.5, weight: .semibold))
      .foregroundStyle(Color.black.opacity(0.42))
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
  }

  private func sidebarRow(title: String, icon: String, isSelected: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(SnapzyMockPalette.macBlue)
        .frame(width: 15)

      Text(title)
        .font(.system(size: 11, weight: isSelected ? .medium : .regular))
        .foregroundStyle(SnapzyMockPalette.ink.opacity(isSelected ? 0.95 : 0.84))

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(
      Radius.rect(Radius.controlXS)
        .fill(isSelected ? Color.black.opacity(0.08) : Color.clear)
    )
  }

  // MARK: - Main Content

  private var mainContent: some View {
    VStack(spacing: 0) {
      // Unified macOS Finder Toolbar
      HStack(spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: "chevron.left")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.45))
          Image(systemName: "chevron.right")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.18))
        }

        Text("Desktop")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(SnapzyMockPalette.ink)

        Spacer()

        // Native Finder view-mode segmented control
        HStack(spacing: 2) {
          Image(systemName: "square.grid.2x2")
            .font(.system(size: 9.5))
            .foregroundStyle(Color.black.opacity(0.45))
            .frame(width: 20, height: 17)

          Image(systemName: "list.bullet")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(SnapzyMockPalette.ink)
            .frame(width: 20, height: 17)
            .background(
              Radius.rect(Radius.ornament)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.10), radius: 1, y: 0.5)
            )
        }
        .padding(2)
        .background(
          Radius.rect(Radius.controlXS)
            .fill(Color.black.opacity(0.055))
        )

        Image(systemName: "magnifyingglass")
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.48))
      }
      .frame(height: 36)
      .padding(.horizontal, 12)
      .background(Color(red: 0.985, green: 0.986, blue: 0.990))

      Rectangle()
        .fill(Color.black.opacity(0.07))
        .frame(height: 0.5)

      // Column Headers
      HStack(spacing: 0) {
        Text("Name")
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, 12)

        Text("Date Modified")
          .frame(width: 96, alignment: .leading)

        Text("Size")
          .frame(width: 54, alignment: .trailing)
          .padding(.trailing, 10)
      }
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(Color.black.opacity(0.46))
      .padding(.vertical, 4)
      .background(Color.black.opacity(0.018))

      Rectangle()
        .fill(Color.black.opacity(0.06))
        .frame(height: 0.5)

      // Alternating Finder List Rows
      VStack(spacing: 0) {
        ForEach(Array(Self.items.enumerated()), id: \.element.id) { index, item in
          let isSelected = index == 1
          HStack(spacing: 6) {
            Image(systemName: item.isFolder ? "folder.fill" : "doc.text.fill")
              .font(.system(size: 11.5))
              .foregroundStyle(
                isSelected
                  ? Color.white
                  : (item.isFolder ? SnapzyMockPalette.finderFolderBlue : Color.gray.opacity(0.75))
              )
              .frame(width: 15)

            Text(item.name)
              .font(.system(size: 10, weight: isSelected ? .medium : .regular))
              .foregroundStyle(isSelected ? Color.white : SnapzyMockPalette.ink.opacity(0.90))
              .lineLimit(1)

            Spacer()

            Text(item.dateModified)
              .font(.system(size: 9.5))
              .foregroundStyle(isSelected ? Color.white.opacity(0.88) : Color.black.opacity(0.48))
              .frame(width: 96, alignment: .leading)

            Text(item.size)
              .font(.system(size: 9.5))
              .foregroundStyle(isSelected ? Color.white.opacity(0.88) : Color.black.opacity(0.48))
              .frame(width: 54, alignment: .trailing)
              .padding(.trailing, 10)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4.5)
          .background(
            Radius.rect(Radius.ornament)
              .fill(
                isSelected
                  ? SnapzyMockPalette.macBlue
                  : (index.isMultiple(of: 2) ? Color.clear : Color.black.opacity(0.025))
              )
              .padding(.horizontal, 4)
          )
        }
      }
      .padding(.top, 2)

      Spacer(minLength: 0)

      // Native macOS Finder bottom status bar
      Rectangle()
        .fill(Color.black.opacity(0.07))
        .frame(height: 0.5)

      HStack {
        Spacer()
        Text("5 items, 142.8 GB available")
          .font(.system(size: 8.5, weight: .medium))
          .foregroundStyle(Color.black.opacity(0.45))
        Spacer()
      }
      .frame(height: 19)
      .background(Color(red: 0.975, green: 0.977, blue: 0.982))
    }
  }
}
