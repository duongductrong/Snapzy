//
//  SnapzyMockNotesWindow.swift
//  Snapzy
//
//  Faithful floating Apple Notes window for the onboarding walkthrough: toolbar, notes sidebar,
//  and prose column.
//

import SwiftUI

struct SnapzyMockNotesWindow: View, Equatable {
  static func == (_: SnapzyMockNotesWindow, _: SnapzyMockNotesWindow) -> Bool {
    true
  }

  static let sidebarWidth: CGFloat = 148
  static let toolbarHeight: CGFloat = 38

  var body: some View {
    HStack(spacing: 0) {
      // Authentic macOS full-height Notes sidebar (traffic lights + note list)
      sidebar
        .frame(width: Self.sidebarWidth)

      Rectangle()
        .fill(SnapzyMockPalette.chromeRule)
        .frame(width: 0.5)

      // Right pane: unified borderless toolbar + pure paper note body
      VStack(spacing: 0) {
        editorToolbar

        Rectangle()
          .fill(Color.black.opacity(0.055))
          .frame(height: 0.5)

        prose
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.white)
    }
    .background(Color.white)
    .clipShape(Radius.rect(Radius.card))
    .overlay(
      Radius.rect(Radius.card)
        .strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5)
    )
    .shadow(color: Color.black.opacity(0.24), radius: 26, x: 0, y: 14)
    .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 2)
    .accessibilityHidden(true)
  }

  // MARK: - Full-Height macOS Sidebar

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Traffic lights & sidebar toggle inside the translucent sidebar header
      HStack {
        SnapzyMockTrafficLights()
        Spacer()
        Image(systemName: "sidebar.left")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(SnapzyMockPalette.inkSecondary)
      }
      .padding(.horizontal, 12)
      .frame(height: Self.toolbarHeight)

      VStack(alignment: .leading, spacing: 2) {
        Text("Today")
          .font(.system(size: 9.5, weight: .semibold))
          .foregroundStyle(SnapzyMockPalette.inkTertiary)
          .padding(.horizontal, 8)
          .padding(.bottom, 2)

        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
          let isSelected = index == 0
          VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
              .font(.system(size: 10.5, weight: .semibold))
              .foregroundStyle(SnapzyMockPalette.ink.opacity(isSelected ? 0.96 : 0.84))
              .lineLimit(1)

            HStack(spacing: 4) {
              Text(row.time)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SnapzyMockPalette.inkSecondary.opacity(0.85))
              Text(row.preview)
                .font(.system(size: 9))
                .foregroundStyle(SnapzyMockPalette.inkTertiary)
                .lineLimit(1)
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            Radius.rect(Radius.controlXS)
              .fill(isSelected ? SnapzyMockPalette.notesGold.opacity(0.24) : Color.clear)
          )

          if !isSelected, index < rows.count - 1 {
            Rectangle()
              .fill(Color.black.opacity(0.055))
              .frame(height: 0.5)
              .padding(.horizontal, 8)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, 7)
      .padding(.top, 2)
    }
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(Color(red: 0.955, green: 0.955, blue: 0.962))
  }

  private var rows: [(title: String, time: String, preview: String)] {
    [
      ("Keeper’s last night", "19:08", "The beam swept across"),
      ("Gear list", "14:22", "Brass polish, spare bulbs"),
      ("Storm log — Nov", "Tue", "Wind 47 knots, power out"),
      ("Automation handover", "Mon", "Thirty-one pages, signed"),
      ("Letters", "Aug 12", "M. to R. — light stays lit"),
    ]
  }

  // MARK: - Unified Borderless Editor Toolbar

  private var editorToolbar: some View {
    HStack(spacing: 12) {
      toolbarGlyph("square.and.pencil")
      toolbarGlyph("checklist")
      toolbarGlyph("tablecells")
      toolbarGlyph("textformat")

      Spacer()

      toolbarGlyph("square.and.arrow.up")
      toolbarGlyph("magnifyingglass")
    }
    .padding(.horizontal, 14)
    .frame(height: Self.toolbarHeight)
    .background(Color(red: 0.985, green: 0.986, blue: 0.990))
  }

  private func toolbarGlyph(_ systemName: String) -> some View {
    Image(systemName: systemName)
      .font(.system(size: 11.5, weight: .regular))
      .foregroundStyle(SnapzyMockPalette.inkSecondary.opacity(0.85))
  }

  // MARK: - Prose

  private var prose: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("18 August 2026 at 19:08")
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(SnapzyMockPalette.inkTertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 1)

      Text("Keeper’s last night")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(SnapzyMockPalette.ink)

      paragraph(
        "The beam swept across the dark water one final time. Marcus had kept the lighthouse for "
          + "forty-three years, and tomorrow, automation would take over."
      )

      paragraph(
        "At the top, he sat in the keeper’s chair—the one he’d occupied during countless storms "
          + "and ordinary mornings. The brass was worn smooth from his hands."
      )

      Text("Aug 18, 2026. Light burning true. Sea calm. Work complete.")
        .font(.system(size: 11))
        .italic()
        .foregroundStyle(SnapzyMockPalette.inkSecondary)
        .lineSpacing(3.5)

      paragraph("Marcus smiled. That was exactly as it should be.")

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 18)
    .padding(.top, 11)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color.white)
  }

  private func paragraph(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 11.5))
      .foregroundStyle(SnapzyMockPalette.ink.opacity(0.92))
      .lineSpacing(3.5)
      .fixedSize(horizontal: false, vertical: true)
  }
}
