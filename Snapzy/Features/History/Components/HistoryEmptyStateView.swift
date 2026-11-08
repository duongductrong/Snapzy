//
//  HistoryEmptyStateView.swift
//  Snapzy
//
//  Empty state placeholder for capture history
//

import SwiftUI

struct HistoryEmptyStateView: View {
  let filter: CaptureHistoryType?
  let hasSearch: Bool

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: iconName)
        .font(.system(size: 36, weight: .light))
        .foregroundColor(.secondary.opacity(0.5))
        .padding(.bottom, 4)

      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.primary.opacity(0.85))

      Text(subtitle)
        .font(.system(size: 13))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 280)
    }
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
