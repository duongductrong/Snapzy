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
  @StateObject private var viewModel = HistorySearchViewModel()
  @State private var selectedIds: Set<UUID> = []

  private var filteredRecords: [CaptureHistoryRecord] {
    viewModel.filteredRecords
  }

  private var filteredRecordIDs: [UUID] {
    filteredRecords.map(\.id)
  }

  var body: some View {
    ZStack {
      HistoryBackdropView(style: backgroundStyle)
        .ignoresSafeArea()

      VStack(spacing: 18) {
        HistoryToolbar(
          searchText: $viewModel.searchText,
          selectedCount: selectedRecords.count,
          canSelectAll: selectedRecords.count < filteredRecords.count,
          onSelectAll: selectAllFilteredRecords,
          onClearSelection: { selectedIds.removeAll() },
          onDeleteSelection: deleteSelectedRecords
        )

        HistoryFilterBar(
          selectedFilter: $viewModel.selectedFilter,
          counts: filterCounts
        )

        if filteredRecords.isEmpty {
          HistoryEmptyStateView(
            filter: viewModel.selectedFilter,
            hasSearch: !viewModel.searchText.isEmpty
          )
        } else {
          HistoryGridView(
            records: filteredRecords,
            selectedIds: $selectedIds
          )
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 20)
    }
    .preferredColorScheme(themeManager.systemAppearance)
    .onReceive(NotificationCenter.default.publisher(for: .historyCopySelection)) { notification in
      guard notification.object is HistoryWindow else { return }
      copySelectedRecords()
    }
    .onReceive(NotificationCenter.default.publisher(for: .historyDeleteSelection)) { notification in
      guard notification.object is HistoryWindow else { return }
      deleteSelectedRecords()
    }
    .onReceive(NotificationCenter.default.publisher(for: .historySelectAll)) { notification in
      guard notification.object is HistoryWindow else { return }
      selectAllFilteredRecords()
    }
    .onChange(of: filteredRecordIDs) { ids in
      selectedIds.formIntersection(Set(ids))
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

  private func selectAllFilteredRecords() {
    selectedIds = Set(filteredRecords.map(\.id))
  }

  private func deleteSelectedRecords() {
    let deletedCount = HistoryWindowController.shared.deleteRecords(
      selectedRecords,
      asksConfirmation: true
    )
    guard deletedCount > 0 else { return }
    selectedIds.removeAll()
  }
}

struct HistoryBackdropView: View {
  let style: HistoryBackgroundStyle
  var cornerRadius: CGFloat = 0
  var compact = false
  /// Applies the darker, more directional glass treatment used by the onboarding window to the
  /// transient floating panel without changing the full History browser's quieter substrate.
  var isFloatingPanel = false

  @ObservedObject private var themeManager = ThemeManager.shared
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      if compact {
        switch style {
        case .hud:
          if isFloatingPanel {
            onboardingGlassBackdrop
          } else {
            compactHUDBase
          }
        case .solid:
          Color(nsColor: WindowSurfacePalette.backgroundColor(for: themeManager.preferredAppearance))
        }
      } else {
        switch style {
        case .hud:
          if isFloatingPanel {
            onboardingGlassBackdrop
          } else {
            Rectangle().fill(.ultraThinMaterial)
            floatingGlassOverlay
          }
        case .solid:
          Color(nsColor: WindowSurfacePalette.backgroundColor(for: themeManager.preferredAppearance))
        }
      }

      if compact {
        compactPreviewOverlay
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  /// Reuse the onboarding backdrop itself so the floating History HUD has the same material,
  /// directional scrim, leading bloom, top hairline, border, and dark appearance — not a second
  /// approximation of those layers.
  private var onboardingGlassBackdrop: some View {
    SnapzyGlassWindowBackdrop(radius: resolvedBackdropCornerRadius)
      .environment(\.colorScheme, .dark)
  }

  private var resolvedBackdropCornerRadius: CGFloat {
    cornerRadius > 0 ? cornerRadius : SnapzyOnboardingMetrics.windowRadius
  }

  /// Balanced Liquid Glass overlays on top of the vibrancy substrate: a vertical thickness sheen,
  /// a leading bloom, and a soft trailing grounding — light from above, weight below. The material
  /// stays beneath because the panel's glass chrome (pills, control buttons, search/selection
  /// surfaces) samples this substrate to resolve dark; without it the chrome renders flat.
  private var floatingGlassOverlay: some View {
    ZStack {
      LinearGradient(
        colors: colorScheme == .dark
          ? darkGlassGradientColors
          : lightGlassGradientColors,
        startPoint: .top,
        endPoint: .bottom
      )

      RadialGradient(
        colors: [Color.white.opacity(topLeadingBloomOpacity), Color.clear],
        center: .topLeading,
        startRadius: 0,
        endRadius: 560
      )

      RadialGradient(
        colors: [Color.black.opacity(bottomTrailingGroundingOpacity), Color.clear],
        center: .bottomTrailing,
        startRadius: 0,
        endRadius: 640
      )
    }
    .overlay(alignment: .top) {
      LinearGradient(
        colors: [
          Color.white.opacity(topHairlineEdgeOpacity),
          Color.white.opacity(topHairlineCenterOpacity),
          Color.white.opacity(topHairlineEdgeOpacity),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(height: 1)
    }
  }

  private var compactHUDBase: some View {
    Rectangle()
      .fill(
        colorScheme == .dark
          ? Color(red: 0.10, green: 0.11, blue: 0.14)
          : Color(red: 0.95, green: 0.95, blue: 0.97)
      )
  }

  private var darkGlassGradientColors: [Color] {
    return [
      Color.white.opacity(0.07),
      Color.clear,
      Color.black.opacity(0.05),
    ]
  }

  private var lightGlassGradientColors: [Color] {
    return [
      Color.white.opacity(0.26),
      Color.clear,
      Color.black.opacity(0.02),
    ]
  }

  private var topLeadingBloomOpacity: Double {
    return colorScheme == .dark ? 0.07 : 0.20
  }

  private var bottomTrailingGroundingOpacity: Double {
    return colorScheme == .dark ? 0.10 : 0.04
  }

  private var topHairlineEdgeOpacity: Double {
    colorScheme == .dark ? 0.02 : 0.05
  }

  private var topHairlineCenterOpacity: Double {
    colorScheme == .dark ? 0.30 : 0.72
  }

  private var compactPreviewOverlay: some View {
    VStack(spacing: 0) {
      // Header: traffic lights, miniature filter pills, and circular action button
      HStack(spacing: 0) {
        HStack(spacing: 3) {
          Circle().fill(Color.red.opacity(0.9)).frame(width: 3.5, height: 3.5)
          Circle().fill(Color.yellow.opacity(0.9)).frame(width: 3.5, height: 3.5)
          Circle().fill(Color.green.opacity(0.9)).frame(width: 3.5, height: 3.5)
        }
        .padding(.leading, 6)

        Spacer()

        HStack(spacing: 3) {
          Capsule()
            .fill(Color.accentColor)
            .frame(width: 10, height: 5)
          Capsule()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .frame(width: 10, height: 5)
          Capsule()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            .frame(width: 10, height: 5)
        }

        Spacer()

        Circle()
          .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
          .frame(width: 5, height: 5)
          .padding(.trailing, 6)
      }
      .frame(height: 14)
      .background(previewToolbarFill)

      // Content area: Symmetrical grid of capture items (landscape screenshot cards)
      HStack(spacing: 6) {
        ForEach(0..<3, id: \.self) { index in
          RoundedRectangle(cornerRadius: 2, style: .continuous) // radius-lint:allow — miniature illustration of the history HUD, drawn at ~1:10 scale
            .fill(previewCardFill.opacity(index == 0 ? 1.0 : 0.68))
            .frame(width: 16, height: 26)
            .overlay(
              RoundedRectangle(cornerRadius: 2, style: .continuous) // radius-lint:allow — miniature illustration of the history HUD, drawn at ~1:10 scale
                .stroke(previewWindowStroke, lineWidth: 0.5)
            )
        }
      }
      .padding(.horizontal, 6)
      .padding(.top, 6)

      Spacer(minLength: 0)
    }
  }

  private var previewCardFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.78)
  }

  private var previewWindowStroke: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
  }

  private var previewToolbarFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
  }
}
