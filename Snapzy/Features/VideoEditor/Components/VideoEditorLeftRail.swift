//
//  VideoEditorLeftRail.swift
//  Snapzy
//
//  Collapsed left rail for the video editor: icon entries that expand the left
//  sidebar with the matching configuration panel.
//

import SwiftUI

/// Vertical icon rail on the leading edge of the editor workspace. Inactive
/// entries render in secondary gray; the active entry is tinted with the
/// accent (primary) color.
struct VideoEditorLeftRail: View {
  @ObservedObject var state: VideoEditorState

  private enum Metrics {
    static let railWidth: CGFloat = 44
    static let buttonSize: CGFloat = 32
    static let buttonSpacing: CGFloat = 4
    static let topPadding: CGFloat = 10
    static let iconSize: CGFloat = 15
  }

  var body: some View {
    VStack(spacing: Metrics.buttonSpacing) {
      ForEach(VideoEditorLeftSidebarPanel.allCases, id: \.self) { panel in
        VideoEditorRailButton(
          panel: panel,
          isSelected: state.isLeftSidebarVisible && state.leftSidebarPanel == panel
        ) {
          state.selectLeftSidebarPanel(panel)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.top, Metrics.topPadding)
    .frame(width: Metrics.railWidth)
    .frame(maxHeight: .infinity, alignment: .top)
  }
}

/// Single rail entry. Inactive glyphs sit in secondary gray; the selected glyph
/// takes the primary color over a soft accent surface.
struct VideoEditorRailButton: View {
  let panel: VideoEditorLeftSidebarPanel
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(iconColor)
        .frame(width: 32, height: 32)
        .background(surface)
        .clipShape(Radius.controlRect(forHeight: 32))
        .contentShape(Radius.controlRect(forHeight: 32))
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(LiquidGlassTokens.hoverSpring) { isHovering = hovering }
    }
    .animation(LiquidGlassTokens.hoverSpring, value: isSelected)
    .help(tooltip)
  }

  private var icon: String {
    switch panel {
    case .background: return "paintpalette"
    case .zoom: return "plus.magnifyingglass"
    }
  }

  private var tooltip: String {
    switch panel {
    case .background: return L10n.Common.background
    case .zoom: return L10n.VideoEditor.zoomSettings
    }
  }

  private var iconColor: Color {
    isSelected ? ZoomColors.primary : SidebarColors.labelSecondary
  }

  private var surface: Color {
    if isSelected { return ZoomColors.primary.opacity(0.15) }
    if isHovering { return SidebarColors.itemHover.opacity(0.35) }
    return .clear
  }
}
