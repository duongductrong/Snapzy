//
//  HistoryFloatingContentView.swift
//  Snapzy
//
//  SwiftUI content for the floating history panel
//

import Combine
import SwiftUI

struct HistoryFloatingContentView: View {
  @ObservedObject var manager: HistoryFloatingManager
  @ObservedObject private var themeManager = ThemeManager.shared
  @ObservedObject private var store = CaptureHistoryStore.shared
  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var backgroundStyle: HistoryBackgroundStyle = .defaultStyle
  @Environment(\.colorScheme) private var colorScheme

  @State private var selectedCompactFilter: CaptureHistoryType? = nil
  @State private var usesExplicitCompactFilterSelection = false
  @State private var selectedId: UUID? = nil
  @State private var expandedSelectedIds: Set<UUID> = []
  @State private var expandedLastSelectedId: UUID?
  @State private var compactScrollOffset: CGFloat = 0
  @State private var compactSelectionRevealTrigger = 0
  @State private var isExpandedGridReady = false
  @State private var expandedGridWarmupTask: Task<Void, Never>?
  @StateObject private var scrollController = HistoryScrollController()
  @StateObject private var searchViewModel: HistorySearchViewModel

  init(manager: HistoryFloatingManager) {
    self.manager = manager
    _searchViewModel = StateObject(wrappedValue: HistorySearchViewModel(
      searchTextPublisher: manager.$searchText.eraseToAnyPublisher(),
      selectedFilterPublisher: manager.$expandedFilter.eraseToAnyPublisher(),
      selectedTimeFilterPublisher: manager.$expandedTimeFilter.eraseToAnyPublisher()
    ))
  }

  private var sortedRecords: [CaptureHistoryRecord] {
    // CaptureHistoryStore already publishes rows ordered by capturedAt desc.
    store.records
  }

  private var compactRecords: [CaptureHistoryRecord] {
    filteredRecords(
      typeFilter: effectiveCompactFilter,
      searchText: "",
      timeFilter: .all,
      limit: manager.maxDisplayedItems
    )
  }

  private var expandedRecords: [CaptureHistoryRecord] {
    searchViewModel.filteredRecords
  }

  private var activeRecords: [CaptureHistoryRecord] {
    manager.presentationMode == .compact ? compactRecords : expandedRecords
  }

  private var activeRecordIDs: [UUID] {
    activeRecords.map(\.id)
  }

  private var expandedRecordIDs: [UUID] {
    expandedRecords.map(\.id)
  }

  private var expandedSelectedRecords: [CaptureHistoryRecord] {
    expandedRecords.filter { expandedSelectedIds.contains($0.id) }
  }

  private var basePanelSize: CGSize {
    HistoryFloatingLayout.basePanelSize(for: manager.presentationMode)
  }

  private var resolvedPanelScale: CGFloat {
    HistoryFloatingLayout.effectiveScale(
      for: manager.panelScale,
      mode: manager.presentationMode,
      on: ScreenUtility.activeScreen()
    )
  }

  private var scaledPanelSize: CGSize {
    HistoryFloatingLayout.panelSize(
      for: manager.panelScale,
      mode: manager.presentationMode,
      on: ScreenUtility.activeScreen()
    )
  }

  var body: some View {
    content
      .frame(width: basePanelSize.width, height: basePanelSize.height)
      .background(HistoryBackdropView(style: backgroundStyle))
      .overlay(panelBorder)
      .scaleEffect(resolvedPanelScale)
      .frame(width: scaledPanelSize.width, height: scaledPanelSize.height)
      .preferredColorScheme(themeManager.systemAppearance)
      .onAppear {
        syncSelectionIfNeeded()
        syncExpandedGridPresentation(for: manager.presentationMode)
      }
      .onDisappear {
        expandedGridWarmupTask?.cancel()
      }
      .onChange(of: activeRecordIDs) { _ in
        syncSelectionIfNeeded()
      }
      .onChange(of: expandedRecordIDs) { _ in
        pruneExpandedSelection()
        prefetchExpandedThumbnailsIfNeeded()
      }
      .onChange(of: manager.presentationMode) { _ in
        if manager.presentationMode != .expanded {
          clearExpandedSelection()
        }
        syncSelectionIfNeeded()
        syncExpandedGridPresentation(for: manager.presentationMode)
      }
      .onReceive(NotificationCenter.default.publisher(for: .historyCopySelection)) { notification in
        guard notification.object is HistoryFloatingPanel else { return }
        copySelectedRecord()
      }
      .onReceive(NotificationCenter.default.publisher(for: .historyActivateSelection)) { notification in
        guard notification.object is HistoryFloatingPanel else { return }
        openSelectedRecord()
      }
      .onReceive(NotificationCenter.default.publisher(for: .historyDeleteSelection)) { notification in
        guard notification.object is HistoryFloatingPanel else { return }
        deleteSelectedRecords()
      }
      .onReceive(NotificationCenter.default.publisher(for: .historySelectAll)) { notification in
        guard notification.object is HistoryFloatingPanel else { return }
        guard manager.presentationMode == .expanded else { return }
        selectAllExpandedRecords()
      }
  }

  private var content: some View {
    Group {
      switch manager.presentationMode {
      case .compact:
        compactContent
      case .expanded:
        expandedContent
      }
    }
  }

  private var panelShape: RoundedRectangle {
    RoundedRectangle(
      cornerRadius: HistoryFloatingLayout.baseCornerRadius(for: manager.presentationMode),
      style: .continuous
    )
  }

  private var panelBorder: some View {
    panelShape
      .strokeBorder(
        colorScheme == .dark
          ? Color.white.opacity(0.1)
          : Color.white.opacity(0.72),
        lineWidth: 1
      )
  }

  // MARK: - Compact

  private var compactContent: some View {
    VStack(spacing: 18) {
      compactHeader

      if compactRecords.isEmpty {
        compactEmptyState
      } else {
        compactScrollContent
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 18)
    .padding(.bottom, 18)
  }

  private var compactHeader: some View {
    ZStack {
      compactFilterBar
        .frame(maxWidth: .infinity)

      HStack(spacing: 8) {
        Spacer()

        controlButton(
          systemName: "arrow.up.forward.app",
          help: L10n.Actions.openHistory,
          action: openFullHistory
        )

        controlButton(
          systemName: manager.isPinned ? "pin.fill" : "pin",
          help: manager.isPinned ? L10n.PreferencesHistory.unpinPanel : L10n.PreferencesHistory.pinPanel,
          isActive: manager.isPinned,
          action: manager.togglePin
        )

        controlButton(
          systemName: "xmark",
          help: L10n.Common.close,
          action: manager.hide
        )
      }
    }
  }

  private var compactFilterBar: some View {
    HStack(spacing: 10) {
      ForEach(Array(captureTypeFilters.enumerated()), id: \.offset) { _, filter in
        selectionPill(
          title: filter.title,
          isSelected: filter.type == effectiveCompactFilter,
          count: nil,
          action: { selectCompactFilter(filter.type) }
        )
      }
    }
  }

  private var compactScrollContent: some View {
    HistoryCompactCarouselView(
      records: compactRecords,
      selectedId: selectedId,
      selectionRevealTrigger: compactSelectionRevealTrigger,
      scrollOffset: $compactScrollOffset,
      onSelect: { record in
        selectRecord(record)
      }
    )
  }

  private var compactEmptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: compactEmptyIconName)
        .font(.system(size: 28, weight: .medium))
        .foregroundColor(.secondary.opacity(0.68))

      Text(compactEmptyTitle)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Expanded

  private var expandedContent: some View {
    ZStack(alignment: .bottom) {
      VStack(spacing: 18) {
        expandedHeader

        if expandedRecords.isEmpty {
          expandedEmptyState
        } else if isExpandedGridReady {
          expandedGrid
        } else {
          expandedGridPlaceholder
        }
      }

      if !expandedSelectedRecords.isEmpty {
        expandedSelectionBar
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 20)
  }

  private var expandedHeader: some View {
    HStack(alignment: .center, spacing: 12) {
      expandedTypeFilters
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)

      expandedSearchBar

      expandedTrailingControls
        .fixedSize(horizontal: true, vertical: false)
    }
  }

  private var expandedTypeFilters: some View {
    return HStack(spacing: 8) {
      ForEach(Array(captureTypeFilters.enumerated()), id: \.offset) { _, filter in
        selectionPill(
          title: filter.title,
          isSelected: manager.expandedFilter == filter.type,
          count: nil,
          horizontalPadding: 12,
          verticalPadding: 8,
          fontSize: 11,
          minWidth: expandedTypeFilterMinWidth(for: filter.type),
          action: {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
              manager.expandedFilter = filter.type
            }
          }
        )
      }
    }
  }

  private var expandedSearchBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.secondary.opacity(0.9))

      TextField("Search captures", text: $manager.searchText)
        .textFieldStyle(.plain)
        .font(.system(size: 12, weight: .medium))

      if !manager.searchText.isEmpty {
        Button(action: { manager.searchText = "" }) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.8))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .frame(width: 238)
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: 0.18,
      tint: 0.06,
      // The native branch draws its own refractive edge and ignores `highlight`; the composite
      // path resolves the specular hairline. Reading the capability statically here would leave a
      // stale `.none` behind after a live toggle.
      highlight: .specular
    )
    .shadow(color: chromeSurfaceShadow, radius: 7, x: 0, y: 3)
  }

  private var expandedTimeFilters: some View {
    HStack(spacing: 8) {
      ForEach(HistoryFloatingTimeFilter.allCases) { filter in
        selectionPill(
          title: filter.title,
          isSelected: manager.expandedTimeFilter == filter,
          count: nil,
          horizontalPadding: 12,
          verticalPadding: 8,
          fontSize: 11,
          minWidth: expandedTimeFilterMinWidth(for: filter),
          action: {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
              manager.expandedTimeFilter = filter
            }
          }
        )
      }
    }
  }

  private var expandedTrailingControls: some View {
    HStack(spacing: 8) {
      expandedTimeFilters
      expandedControls
    }
  }

  private var expandedControls: some View {
    HStack(spacing: 6) {
      if manager.isEnabled {
        controlButton(
          systemName: "arrow.down.right.and.arrow.up.left",
          help: "Collapse",
          size: 34,
          action: manager.collapse
        )
      }

      controlButton(
        systemName: manager.isPinned ? "pin.fill" : "pin",
        help: manager.isPinned ? L10n.PreferencesHistory.unpinPanel : L10n.PreferencesHistory.pinPanel,
        size: 34,
        isActive: manager.isPinned,
        action: manager.togglePin
      )

      controlButton(
        systemName: "xmark",
        help: L10n.Common.close,
        size: 34,
        action: manager.hide
      )
    }
  }

  private var expandedSelectionBar: some View {
    HStack(spacing: 10) {
      Label(
        L10n.PreferencesHistory.selectedCaptures(expandedSelectedRecords.count),
        systemImage: "checkmark.circle.fill"
      )
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(.primary.opacity(0.84))

      if expandedSelectedRecords.count < expandedRecords.count {
        selectionControlButton(
          title: L10n.PreferencesHistory.selectAll,
          systemName: "checkmark.circle",
          action: selectAllExpandedRecords
        )
      }

      selectionControlButton(
        title: L10n.PreferencesHistory.clearSelection,
        systemName: "xmark.circle",
        action: clearExpandedSelection
      )

      selectionControlButton(
        title: L10n.Common.deleteAction,
        systemName: "trash",
        isDestructive: true,
        action: deleteSelectedRecords
      )
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .liquidGlassSurface(
      shape: Capsule(style: .continuous),
      substrate: LiquidGlassTokens.baseDarkness,
      tint: 0.06,
      // Native ignores `highlight`; resolving it statically made the composite path lose its
      // hairline after a live toggle-off.
      highlight: .specular
    )
    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 18, x: 0, y: 8)
    .fixedSize(horizontal: true, vertical: false)
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.bottom, 4)
    .transition(.scale(scale: 0.96, anchor: .bottom))
  }

  private var expandedGrid: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVGrid(columns: expandedColumns, spacing: 12) {
        ForEach(expandedRecords) { record in
          HistoryExpandedCaptureCardView(
            record: record,
            isSelected: expandedSelectedIds.contains(record.id),
            backgroundStyle: backgroundStyle,
            onTap: {
              selectExpandedRecord(record)
            },
            reservedScrollAxis: expandedRecords.count > expandedColumns.count ? .vertical : nil
          )
          .equatable()
          .contextMenu {
            HistoryContextMenu(record: record)
          }
        }
      }
      .padding(.horizontal, 6)
      .padding(.top, 4)
      .padding(.bottom, 88)

      HistoryScrollViewReader(controller: scrollController)
        .frame(height: 0)
    }
    .overlay(
      HistoryFloatingScrollbar(controller: scrollController, scale: resolvedPanelScale)
        .padding(.trailing, 2),
      alignment: .trailing
    )
  }

  private var expandedGridPlaceholder: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVGrid(columns: expandedColumns, spacing: 12) {
        ForEach(0..<8, id: \.self) { _ in
          VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(placeholderFill)
              .aspectRatio(16 / 10, contentMode: .fit)

            VStack(alignment: .leading, spacing: 7) {
              RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(placeholderFill)
                .frame(height: 12)

              HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                  .fill(placeholderFill)
                  .frame(width: 96, height: 10)
              }
            }
          }
          .padding(10)
          .background(placeholderCardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .stroke(placeholderStroke, lineWidth: 1)
          )
          .redacted(reason: .placeholder)
        }
      }
      .padding(.horizontal, 6)
      .padding(.top, 4)
      .padding(.bottom, 14)
    }
  }

  private var expandedColumns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top),
      count: 4
    )
  }

  private var expandedEmptyState: some View {
    HistoryEmptyStateView(
      filter: manager.expandedFilter,
      hasSearch: !manager.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
    .padding(.horizontal, 160)
    .padding(.bottom, 6)
  }

  // MARK: - Styling

  private var captureTypeFilters: [(title: String, type: CaptureHistoryType?)] {
    [
      ("All", nil),
      ("Screenshots", .screenshot),
      ("Videos", .video),
      ("GIFs", .gif),
    ]
  }

  private var effectiveCompactFilter: CaptureHistoryType? {
    usesExplicitCompactFilterSelection ? selectedCompactFilter : manager.defaultFilter
  }

  private var chromeSurfaceShadow: Color {
    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07)
  }

  private var pillCountBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.84)
  }

  private var placeholderFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
  }

  private var placeholderCardFill: Color {
    colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.64)
  }

  private var placeholderStroke: Color {
    colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
  }

  private var compactEmptyIconName: String {
    switch effectiveCompactFilter {
    case .screenshot: return CaptureHistoryType.screenshot.systemIconName
    case .video: return CaptureHistoryType.video.systemIconName
    case .gif: return CaptureHistoryType.gif.systemIconName
    case nil: return "clock.arrow.circlepath"
    }
  }

  private var compactEmptyTitle: String {
    switch effectiveCompactFilter {
    case .screenshot: return "No screenshots yet"
    case .video: return "No videos yet"
    case .gif: return "No GIFs yet"
    case nil: return "No captures yet"
    }
  }

  // MARK: - Helpers

  private func selectionPill(
    title: String,
    isSelected: Bool,
    count: Int?,
    horizontalPadding: CGFloat = 12,
    verticalPadding: CGFloat = 7,
    fontSize: CGFloat = 12,
    minWidth: CGFloat? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Text(title)
          .font(.system(size: fontSize, weight: .semibold))
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)

        if let count {
          Text("\(count)")
            .font(.system(size: max(fontSize - 2, 9), weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(pillCountBackground.opacity(isSelected ? 0.18 : 1), in: Capsule())
        }
      }
      // The glass surface carries the selection tint, so the label stays neutral.
      .foregroundColor(isSelected ? LiquidGlassTokens.inkOnAccent : LiquidGlassTokens.inkBody)
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .frame(minWidth: minWidth)
      .liquidGlassControl(isActive: isSelected, in: Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func controlButton(
    systemName: String,
    help: String,
    size: CGFloat = 30,
    isActive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: size <= 34 ? 10.5 : 11, weight: .semibold))
        .frame(width: size, height: size)
        .foregroundColor(isActive ? LiquidGlassTokens.inkOnAccent : LiquidGlassTokens.inkBody)
        .liquidGlassControl(isActive: isActive, in: Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private func selectionControlButton(
    title: String,
    systemName: String,
    isDestructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: isDestructive ? .destructive : nil, action: action) {
      Label(title, systemImage: systemName)
        .font(.system(size: 11, weight: .semibold))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .buttonStyle(.plain)
    .foregroundColor(isDestructive ? .red : .primary.opacity(0.82))
  }

  private func filteredRecords(
    typeFilter: CaptureHistoryType?,
    searchText: String,
    timeFilter: HistoryFloatingTimeFilter,
    limit: Int? = nil
  ) -> [CaptureHistoryRecord] {
    let now = Date()
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

    var result = sortedRecords

    if let typeFilter {
      result = result.filter { $0.captureType == typeFilter }
    }

    if timeFilter != .all {
      result = result.filter { timeFilter.includes($0.capturedAt, relativeTo: now) }
    }

    if !query.isEmpty {
      result = result.filter { $0.fileName.localizedCaseInsensitiveContains(query) }
    }

    if let limit {
      return Array(result.prefix(limit))
    }

    return result
  }

  private func selectCompactFilter(_ filter: CaptureHistoryType?) {
    let nextSelectionId = filteredRecords(
      typeFilter: filter,
      searchText: "",
      timeFilter: .all,
      limit: manager.maxDisplayedItems
    ).first?.id

    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
      usesExplicitCompactFilterSelection = true
      selectedCompactFilter = filter
      selectedId = nextSelectionId
      compactScrollOffset = 0
    }
  }

  private func syncSelectionIfNeeded() {
    guard !activeRecords.isEmpty else {
      selectedId = nil
      return
    }

    guard let selectedId, activeRecords.contains(where: { $0.id == selectedId }) else {
      self.selectedId = activeRecords.first?.id
      if manager.presentationMode == .compact, self.selectedId != nil {
        compactSelectionRevealTrigger += 1
      }
      return
    }
  }

  private func selectRecord(_ record: CaptureHistoryRecord) {
    selectedId = record.id
    manager.focusPanel()
  }

  private func selectExpandedRecord(_ record: CaptureHistoryRecord) {
    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

    if flags.contains(.shift), let expandedLastSelectedId,
      let startIndex = expandedRecords.firstIndex(where: { $0.id == expandedLastSelectedId }),
      let endIndex = expandedRecords.firstIndex(where: { $0.id == record.id })
    {
      let range = min(startIndex, endIndex)...max(startIndex, endIndex)
      expandedSelectedIds.formUnion(expandedRecords[range].map(\.id))
    } else if flags.contains(.command) {
      if expandedSelectedIds.contains(record.id) {
        expandedSelectedIds.remove(record.id)
      } else {
        expandedSelectedIds.insert(record.id)
      }
      expandedLastSelectedId = record.id
    } else if flags.contains(.shift) {
      expandedSelectedIds.insert(record.id)
      expandedLastSelectedId = record.id
    } else {
      expandedSelectedIds = [record.id]
      expandedLastSelectedId = record.id
    }

    selectedId = record.id
    manager.focusPanel()
  }

  private func selectAllExpandedRecords() {
    expandedSelectedIds = Set(expandedRecords.map(\.id))
    expandedLastSelectedId = expandedRecords.last?.id
  }

  private func clearExpandedSelection() {
    expandedSelectedIds.removeAll()
    expandedLastSelectedId = nil
  }

  private func pruneExpandedSelection() {
    let visibleIds = Set(expandedRecordIDs)
    expandedSelectedIds.formIntersection(visibleIds)

    if let expandedLastSelectedId, !visibleIds.contains(expandedLastSelectedId) {
      self.expandedLastSelectedId = expandedSelectedIds.first
    }
  }

  private func openFullHistory() {
    manager.showExpanded(initialFilter: effectiveCompactFilter)
  }

  private func copySelectedRecord() {
    if manager.presentationMode == .expanded, !expandedSelectedRecords.isEmpty {
      HistoryWindowController.shared.copyToClipboard(expandedSelectedRecords)
      return
    }

    guard let selectedId,
      let record = activeRecords.first(where: { $0.id == selectedId })
    else { return }

    HistoryWindowController.shared.copyToClipboard([record])
  }

  private func openSelectedRecord() {
    if manager.presentationMode == .expanded {
      if expandedSelectedRecords.count == 1, let record = expandedSelectedRecords.first {
        HistoryWindowController.shared.openItem(record)
        return
      }

      if expandedSelectedRecords.count > 1 {
        return
      }
    }

    guard let selectedId,
      let record = activeRecords.first(where: { $0.id == selectedId })
    else { return }

    HistoryWindowController.shared.openItem(record)
  }

  private func deleteSelectedRecords() {
    guard manager.presentationMode == .expanded else { return }

    let deletedCount = HistoryWindowController.shared.deleteRecords(
      expandedSelectedRecords,
      asksConfirmation: true
    )
    guard deletedCount > 0 else { return }

    clearExpandedSelection()
  }

  private func expandedTypeFilterMinWidth(for filter: CaptureHistoryType?) -> CGFloat {
    switch filter {
    case .screenshot:
      return 108
    case .video:
      return 78
    case .gif:
      return 70
    case nil:
      return 62
    }
  }

  private func expandedTimeFilterMinWidth(for filter: HistoryFloatingTimeFilter) -> CGFloat {
    switch filter {
    case .all:
      return 84
    case .last24Hours:
      return 58
    case .last7Days, .last30Days:
      return 54
    }
  }

  private func prefetchExpandedThumbnailsIfNeeded() {
    guard manager.presentationMode == .expanded, !expandedRecords.isEmpty else { return }
    HistoryThumbnailGenerator.shared.preloadThumbnails(for: Array(expandedRecords.prefix(10)))
  }

  private func syncExpandedGridPresentation(for mode: HistoryFloatingPresentationMode) {
    expandedGridWarmupTask?.cancel()

    guard mode == .expanded else {
      isExpandedGridReady = false
      return
    }

    prefetchExpandedThumbnailsIfNeeded()

    guard !expandedRecords.isEmpty else {
      isExpandedGridReady = true
      return
    }

    isExpandedGridReady = false
    expandedGridWarmupTask = Task {
      try? await Task.sleep(nanoseconds: 140_000_000)
      guard !Task.isCancelled else { return }
      await MainActor.run {
        isExpandedGridReady = true
      }
    }
  }
}
