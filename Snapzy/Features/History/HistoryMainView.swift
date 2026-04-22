//
//  HistoryMainView.swift
//  Snapzy
//
//  Root SwiftUI view for the capture history browser
//

import SwiftUI

struct HistoryMainView: View {
  @ObservedObject private var themeManager = ThemeManager.shared
  @ObservedObject private var store = CaptureHistoryStore.shared
  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var backgroundStyle: HistoryBackgroundStyle = .defaultStyle
  @State private var selectedFilter: CaptureHistoryType? = nil
  @State private var searchText: String = ""
  @State private var selectedIds: Set<UUID> = []

  private var filteredRecords: [CaptureHistoryRecord] {
    var result = store.records

    if let filter = selectedFilter {
      result = result.filter { $0.captureType == filter }
    }

    if !searchText.isEmpty {
      result = result.filter {
        $0.fileName.localizedCaseInsensitiveContains(searchText)
      }
    }

    return result
  }

  var body: some View {
    ZStack {
      HistoryBackdropView(style: backgroundStyle)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        HistoryToolbar(
          searchText: $searchText,
          selectedCount: selectedIds.count,
          onClearSelection: { selectedIds.removeAll() }
        )

        HistoryFilterBar(
          selectedFilter: $selectedFilter,
          counts: filterCounts
        )
        .padding(.horizontal)
        .padding(.vertical, 8)

        if filteredRecords.isEmpty {
          HistoryEmptyStateView(
            filter: selectedFilter,
            hasSearch: !searchText.isEmpty
          )
        } else {
          HistoryGridView(
            records: filteredRecords,
            selectedIds: $selectedIds
          )
        }
      }
    }
    .preferredColorScheme(themeManager.systemAppearance)
    .onReceive(NotificationCenter.default.publisher(for: .historyCopySelection)) { notification in
      guard notification.object is HistoryWindow else { return }
      copySelectedRecords()
    }
  }

  private var filterCounts: [CaptureHistoryType?: Int] {
    var counts: [CaptureHistoryType?: Int] = [:]
    counts[nil] = store.records.count
    counts[.screenshot] = store.records.filter { $0.captureType == .screenshot }.count
    counts[.video] = store.records.filter { $0.captureType == .video }.count
    counts[.gif] = store.records.filter { $0.captureType == .gif }.count
    return counts
  }

  private var selectedRecords: [CaptureHistoryRecord] {
    filteredRecords.filter { selectedIds.contains($0.id) }
  }

  private func copySelectedRecords() {
    HistoryWindowController.shared.copyToClipboard(selectedRecords)
  }
}

struct HistoryBackdropView: View {
  let style: HistoryBackgroundStyle
  var cornerRadius: CGFloat = 0
  var compact = false

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      switch style {
      case .hud:
        Rectangle().fill(.ultraThinMaterial)
        Rectangle().fill(hudTint)
        glow(color: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.38), width: compact ? 44 : 220, height: compact ? 44 : 220, x: compact ? -14 : -170, y: compact ? -10 : -120)
        glow(color: Color.black.opacity(colorScheme == .dark ? 0.08 : 0.03), width: compact ? 50 : 240, height: compact ? 50 : 240, x: compact ? 18 : 180, y: compact ? 14 : 130)
      case .solid:
        Color(nsColor: .windowBackgroundColor)
        Rectangle().fill(solidTint)
      }

      Rectangle()
        .fill(
          LinearGradient(
            colors: [
              Color.white.opacity(colorScheme == .dark ? 0.05 : 0.24),
              Color.clear,
              Color.black.opacity(colorScheme == .dark ? 0.1 : 0.03),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      if compact {
        compactPreviewOverlay
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  private var hudTint: LinearGradient {
    LinearGradient(
      colors: colorScheme == .dark
        ? [
          Color.white.opacity(0.05),
          Color.black.opacity(0.12),
          Color.white.opacity(0.03),
        ]
        : [
          Color.white.opacity(0.18),
          Color.black.opacity(0.05),
          Color.white.opacity(0.12),
        ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var solidTint: LinearGradient {
    LinearGradient(
      colors: colorScheme == .dark
        ? [
          Color.white.opacity(0.02),
          Color.white.opacity(0.01),
          Color.black.opacity(0.06),
        ]
        : [
          Color.white.opacity(0.32),
          Color.white.opacity(0.12),
          Color.black.opacity(0.03),
        ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var compactPreviewOverlay: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(previewWindowFill)
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(previewWindowStroke, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 4, x: 0, y: 2)

      VStack(spacing: 0) {
        HStack(spacing: 3) {
          Circle().fill(Color.red.opacity(0.88)).frame(width: 3.6, height: 3.6)
          Circle().fill(Color.yellow.opacity(0.88)).frame(width: 3.6, height: 3.6)
          Circle().fill(Color.green.opacity(0.88)).frame(width: 3.6, height: 3.6)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(height: 9)
        .background(previewToolbarFill)

        HStack(spacing: 4) {
          ForEach(0..<3, id: \.self) { index in
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
              .fill(previewCardFill.opacity(index == 0 ? 1 : 0.86))
              .frame(width: 10.5, height: 14)
              .overlay(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                  .stroke(previewCardStroke, lineWidth: 0.7)
              )
          }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)

        Spacer(minLength: 0)

        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(previewChipFill.opacity(0.78))
          .frame(width: 18, height: 3.5)
          .padding(.bottom, 6)
      }
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .frame(width: 46, height: 34)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var previewChipFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.86)
  }

  private var previewCardFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.78)
  }

  private var previewCardStroke: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
  }

  private var previewWindowFill: Color {
    colorScheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.72)
  }

  private var previewWindowStroke: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
  }

  private var previewToolbarFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
  }

  private func glow(color: Color, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat) -> some View {
    Ellipse()
      .fill(color)
      .frame(width: width, height: height)
      .blur(radius: compact ? 18 : 90)
      .offset(x: x, y: y)
  }
}
