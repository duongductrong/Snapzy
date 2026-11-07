//
//  HistoryEmptyStateView.swift
//  Snapzy
//
//  Empty state placeholder for capture history
//

import SwiftUI

struct HistoryEmptyStateView: View {
  @Environment(\.colorScheme) private var colorScheme

  let filter: CaptureHistoryType?
  let hasSearch: Bool

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: iconName)
        .font(.system(size: 48))
        .foregroundColor(.secondary.opacity(0.5))

      Text(title)
        .font(.title3)
        .fontWeight(.semibold)

      Text(subtitle)
        .font(.body)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 300)
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 26)
    .background(.regularMaterial, in: Radius.rect(Radius.panel))
    .overlay(
      Radius.rect(Radius.panel)
        .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), lineWidth: 1)
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var iconName: String {
    if hasSearch {
      return "magnifyingglass"
    }
    switch filter {
    case .screenshot: return CaptureHistoryType.screenshot.systemIconName
    case .video: return CaptureHistoryType.video.systemIconName
    case .gif: return CaptureHistoryType.gif.systemIconName
    case nil: return "square.grid.2x2"
    }
  }

  private var title: String {
    if hasSearch {
      return L10n.PreferencesHistory.emptyNoMatches
    }
    switch filter {
    case .screenshot: return L10n.PreferencesHistory.emptyNoScreenshots
    case .video: return L10n.PreferencesHistory.emptyNoVideos
    case .gif: return L10n.PreferencesHistory.emptyNoGifs
    case nil: return L10n.PreferencesHistory.emptyNoCaptures
    }
  }

  private var subtitle: String {
    if hasSearch {
      return L10n.PreferencesHistory.emptySearchHint
    }
    return L10n.PreferencesHistory.emptyHint
  }
}
