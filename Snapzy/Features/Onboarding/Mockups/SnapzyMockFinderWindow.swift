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
      // Left Navigation Sidebar
      sidebar
        .frame(width: 140)

      Rectangle()
        .fill(Color.black.opacity(0.08))
        .frame(width: 0.5)

      // Right Main Browser Content
      mainContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.24), radius: 26, x: 0, y: 12)
    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
  }

  // MARK: - Left Sidebar

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Traffic lights
      HStack(spacing: 6) {
        Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 9.5, height: 9.5)
        Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 9.5, height: 9.5)
        Circle().fill(Color(red: 0.16, green: 0.80, blue: 0.25)).frame(width: 9.5, height: 9.5)
      }
      .padding(.top, 12)
      .padding(.leading, 12)
      .padding(.bottom, 10)

      VStack(alignment: .leading, spacing: 1) {
        sidebarSectionHeader("Favorites")

        sidebarRow(title: "Applications", icon: "app.badge", isSelected: false)
        sidebarRow(title: "Desktop", icon: "menubar.dock.rectangle", isSelected: true)
        sidebarRow(title: "Documents", icon: "doc", isSelected: false)
        sidebarRow(title: "Downloads", icon: "arrow.down.circle", isSelected: false)
        sidebarRow(title: "Developer", icon: "hammer", isSelected: false)
      }
      .padding(.horizontal, 6)

      Spacer()
    }
    .background(Color(red: 0.945, green: 0.950, blue: 0.960))
  }

  private func sidebarSectionHeader(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 9.5, weight: .bold))
      .foregroundStyle(Color.black.opacity(0.42))
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
  }

  private func sidebarRow(title: String, icon: String, isSelected: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Color(red: 0.08, green: 0.46, blue: 0.96))
        .frame(width: 15)

      Text(title)
        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? Color(red: 0.08, green: 0.46, blue: 0.96) : Color.black.opacity(0.85))

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(isSelected ? Color.black.opacity(0.08) : Color.clear)
    )
  }

  // MARK: - Main Content

  private var mainContent: some View {
    VStack(spacing: 0) {
      // Toolbar
      HStack(spacing: 8) {
        HStack(spacing: 3) {
          Image(systemName: "chevron.left")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.35))
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.18))
        }

        Text("Desktop")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(Color.black.opacity(0.85))

        Spacer()

        HStack(spacing: 6) {
          Image(systemName: "list.bullet")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.75))

          Image(systemName: "square.grid.2x2")
            .font(.system(size: 10))
            .foregroundStyle(Color.black.opacity(0.45))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2.5)
        .background(
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.black.opacity(0.05))
        )
      }
      .frame(height: 34)
      .padding(.horizontal, 10)

      // Column Headers
      HStack(spacing: 0) {
        Text("Name")
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, 12)

        Text("Date Modified")
          .frame(width: 100, alignment: .leading)

        Text("Size")
          .frame(width: 55, alignment: .trailing)
          .padding(.trailing, 8)
      }
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(Color.black.opacity(0.48))
      .padding(.vertical, 3.5)
      .background(Color.black.opacity(0.02))

      Rectangle()
        .fill(Color.black.opacity(0.06))
        .frame(height: 0.5)

      // Rows
      VStack(spacing: 0) {
        ForEach(Self.items) { item in
          HStack(spacing: 6) {
            Image(systemName: item.isFolder ? "folder.fill" : "doc.text.fill")
              .font(.system(size: 11))
              .foregroundStyle(item.isFolder ? Color.blue : Color.gray)
              .frame(width: 14)

            Text(item.name)
              .font(.system(size: 10, weight: .regular))
              .foregroundStyle(Color.black.opacity(0.85))
              .lineLimit(1)

            Spacer()

            Text(item.dateModified)
              .font(.system(size: 9.5))
              .foregroundStyle(Color.black.opacity(0.48))
              .frame(width: 100, alignment: .leading)

            Text(item.size)
              .font(.system(size: 9.5))
              .foregroundStyle(Color.black.opacity(0.48))
              .frame(width: 55, alignment: .trailing)
              .padding(.trailing, 8)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
        }
      }

      Spacer()
    }
  }
}
