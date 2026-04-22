//
//  HistoryFloatingContentView.swift
//  Snapzy
//
//  SwiftUI content for the floating history panel
//

import SwiftUI

struct HistoryFloatingContentView: View {
  @ObservedObject var manager: HistoryFloatingManager
  @ObservedObject private var themeManager = ThemeManager.shared
  @ObservedObject private var store = CaptureHistoryStore.shared
  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var backgroundStyle: HistoryBackgroundStyle = .defaultStyle
  @Environment(\.colorScheme) private var colorScheme

  @State private var selectedFilter: CaptureHistoryType? = nil
  @State private var usesExplicitFilterSelection = false
  @State private var selectedId: UUID? = nil

  private var filteredRecords: [CaptureHistoryRecord] {
    var result = store.records

    if let filter = effectiveFilter {
      result = result.filter { $0.captureType == filter }
    }

    return Array(result.prefix(manager.maxDisplayedItems))
  }

  private var filteredRecordIDs: [UUID] {
    filteredRecords.map(\.id)
  }

  private var panelScale: CGFloat {
    CGFloat(manager.panelScale)
  }

  private var scaledPanelSize: CGSize {
    HistoryFloatingLayout.panelSize(for: manager.panelScale)
  }

  var body: some View {
    VStack(spacing: 18) {
      header

      if filteredRecords.isEmpty {
        emptyState
      } else {
        scrollContent
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 18)
    .padding(.bottom, 18)
    .frame(
      width: HistoryFloatingLayout.basePanelSize.width,
      height: HistoryFloatingLayout.basePanelSize.height
    )
    .background(HistoryBackdropView(style: backgroundStyle))
    .overlay(panelBorder)
    .scaleEffect(panelScale)
    .frame(width: scaledPanelSize.width, height: scaledPanelSize.height)
    .preferredColorScheme(themeManager.systemAppearance)
    .onAppear {
      syncSelectionIfNeeded()
    }
    .onChange(of: filteredRecordIDs) { _ in
      syncSelectionIfNeeded()
    }
    .onReceive(NotificationCenter.default.publisher(for: .historyCopySelection)) { notification in
      guard notification.object is HistoryFloatingPanel else { return }
      copySelectedRecord()
    }
  }

  private var panelShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: HistoryFloatingLayout.baseCornerRadius, style: .continuous)
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

  // MARK: - Header

  private var header: some View {
    ZStack {
      filterBar
        .frame(maxWidth: .infinity)

      HStack(spacing: 8) {
        Spacer()

        controlButton(
          systemName: "arrow.up.forward.app",
          help: L10n.Actions.openHistory,
          action: openFullHistory
        )

        controlButton(
          systemName: "xmark",
          help: L10n.Common.close,
          action: manager.hide
        )
      }
    }
  }

  private var filterBar: some View {
    HStack(spacing: 10) {
      ForEach(filters, id: \.label) { filter in
        Button(action: { selectFilter(filter.type) }) {
          Text(filter.label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(filter.type == effectiveFilter ? .white : .primary.opacity(0.82))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(filter.type == effectiveFilter ? selectedFilterBackground : unselectedFilterBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var selectedFilterBackground: AnyShapeStyle {
    AnyShapeStyle(
      LinearGradient(
        colors: [
          Color.accentColor.opacity(colorScheme == .dark ? 0.95 : 0.98),
          Color.accentColor.opacity(colorScheme == .dark ? 0.82 : 0.9),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private var unselectedFilterBackground: AnyShapeStyle {
    colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.08))
      : AnyShapeStyle(Color.black.opacity(0.05))
  }

  private func controlButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 30, height: 30)
        .background(controlButtonBackground)
        .foregroundColor(.primary.opacity(0.86))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private var controlButtonBackground: AnyShapeStyle {
    colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.08))
      : AnyShapeStyle(Color.white.opacity(0.72))
  }

  private var filters: [(label: String, type: CaptureHistoryType?)] {
    [
      ("All", nil),
      ("Screenshots", .screenshot),
      ("Videos", .video),
      ("GIFs", .gif),
    ]
  }

  private var effectiveFilter: CaptureHistoryType? {
    usesExplicitFilterSelection ? selectedFilter : manager.defaultFilter
  }

  // MARK: - Content

  private var scrollContent: some View {
    GeometryReader { geometry in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 26) {
          ForEach(filteredRecords) { record in
            HistoryCardView(
              record: record,
              isSelected: selectedId == record.id,
              onTap: {
                manager.focusPanel()
                selectedId = record.id
              }
            )
            .frame(width: 196)
            .contextMenu {
              HistoryContextMenu(record: record)
            }
          }
        }
        .frame(minWidth: geometry.size.width - 4, alignment: .center)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: emptyIconName)
        .font(.system(size: 28, weight: .medium))
        .foregroundColor(.secondary.opacity(0.68))

      Text(emptyTitle)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyIconName: String {
    switch effectiveFilter {
    case .screenshot: return CaptureHistoryType.screenshot.systemIconName
    case .video: return CaptureHistoryType.video.systemIconName
    case .gif: return CaptureHistoryType.gif.systemIconName
    case nil: return "clock.arrow.circlepath"
    }
  }

  private var emptyTitle: String {
    switch effectiveFilter {
    case .screenshot: return "No screenshots yet"
    case .video: return "No videos yet"
    case .gif: return "No GIFs yet"
    case nil: return "No captures yet"
    }
  }

  // MARK: - Actions

  private func selectFilter(_ filter: CaptureHistoryType?) {
    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
      usesExplicitFilterSelection = true
      selectedFilter = filter
    }
  }

  private func syncSelectionIfNeeded() {
    guard !filteredRecords.isEmpty else {
      selectedId = nil
      return
    }

    guard let selectedId, filteredRecords.contains(where: { $0.id == selectedId }) else {
      self.selectedId = filteredRecords.first?.id
      return
    }
  }

  private func openFullHistory() {
    manager.hide()
    HistoryWindowController.shared.showWindow()
  }

  private func copySelectedRecord() {
    guard let selectedId,
          let record = filteredRecords.first(where: { $0.id == selectedId })
    else { return }

    HistoryWindowController.shared.copyToClipboard([record])
  }
}
