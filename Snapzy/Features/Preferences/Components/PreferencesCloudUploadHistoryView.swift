//
//  PreferencesCloudUploadHistoryView.swift
//  Snapzy
//
//  Window and view for managing all cloud upload history records
//

import AppKit
import SwiftUI

// MARK: - History Window Controller

/// Manages the cloud upload history window lifecycle
@MainActor
final class CloudUploadHistoryWindowController {
  static let shared = CloudUploadHistoryWindowController()

  private var window: CloudUploadHistoryPanel?
  private var localEscapeMonitor: Any?
  private var globalEscapeMonitor: Any?
  private let padding: CGFloat = 20

  private init() {}

  @discardableResult
  func toggleWindow() -> Bool {
    if isVisible {
      closeWindow()
      return false
    }

    showWindow()
    return true
  }

  func showWindow() {
    if let existingWindow = window, existingWindow.isVisible {
      updatePosition(CloudUploadFloatingPosition.stored())
      existingWindow.makeKeyAndOrderFront(nil)
      setupEscapeMonitors()
      return
    }

    let view = CloudUploadHistoryView()
    let hostingView = NSHostingView(rootView: view)
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor

    let size = CloudUploadHistoryLayout.panelSize
    let newWindow = CloudUploadHistoryPanel(contentRect: frame(for: size))
    let containerView = CloudUploadHistoryContainerView(frame: NSRect(origin: .zero, size: size))
    containerView.autoresizingMask = [.width, .height]
    containerView.addSubview(hostingView)

    NSLayoutConstraint.activate([
      hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
      hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
    ])

    newWindow.contentView = containerView
    newWindow.applyCornerRadius(CloudUploadHistoryLayout.cornerRadius)
    newWindow.isReleasedWhenClosed = false
    newWindow.makeKeyAndOrderFront(nil)

    window = newWindow
    setupEscapeMonitors()
  }

  func closeWindow() {
    removeEscapeMonitors()
    window?.close()
    window = nil
  }

  var isVisible: Bool {
    window?.isVisible == true
  }

  func updatePosition(_ position: CloudUploadFloatingPosition) {
    guard let window, window.isVisible else { return }
    let targetFrame = frame(for: window.frame.size, position: position)

    NSAnimationContext.runAnimationGroup { context in
      context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      window.animator().setFrame(targetFrame, display: true)
    }
  }

  private func frame(
    for size: CGSize,
    position: CloudUploadFloatingPosition = CloudUploadFloatingPosition.stored()
  ) -> NSRect {
    let screen = ScreenUtility.activeScreen()
    let origin = position.calculateOrigin(for: size, on: screen, padding: padding)
    return NSRect(origin: origin, size: size)
  }

  private func setupEscapeMonitors() {
    removeEscapeMonitors()

    localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard Self.isPlainEscape(event), self?.canCloseForEscape == true else { return event }
      self?.closeWindow()
      return nil
    }

    globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard Self.isPlainEscape(event) else { return }
      Task { @MainActor [weak self] in
        guard self?.canCloseForEscape == true else { return }
        self?.closeWindow()
      }
    }
  }

  private func removeEscapeMonitors() {
    if let localEscapeMonitor {
      NSEvent.removeMonitor(localEscapeMonitor)
      self.localEscapeMonitor = nil
    }

    if let globalEscapeMonitor {
      NSEvent.removeMonitor(globalEscapeMonitor)
      self.globalEscapeMonitor = nil
    }
  }

  private nonisolated static func isPlainEscape(_ event: NSEvent) -> Bool {
    guard event.keyCode == 53 else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return flags.isEmpty
  }

  private var canCloseForEscape: Bool {
    isVisible && window?.attachedSheet == nil && NSApp.modalWindow == nil
  }
}

private enum CloudUploadHistoryLayout {
  static let panelSize = CGSize(width: 1_040, height: 680)
  static let cornerRadius: CGFloat = 32
}

private final class CloudUploadHistoryPanel: NSPanel {
  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configurePanel()
  }

  private func configurePanel() {
    title = L10n.PreferencesCloudHistory.windowTitle
    level = .floating
    isFloatingPanel = true
    isMovableByWindowBackground = true
    hidesOnDeactivate = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
    ignoresMouseEvents = false
    appearance = ThemeManager.shared.nsAppearance
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown else {
      return super.performKeyEquivalent(with: event)
    }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if event.keyCode == 13 && flags == .command {
      CloudUploadHistoryWindowController.shared.closeWindow()
      return true
    }

    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
      event.keyCode == 53
    else {
      super.keyDown(with: event)
      return
    }

    CloudUploadHistoryWindowController.shared.closeWindow()
  }
}

private final class CloudUploadHistoryContainerView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configureLayer()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyStyle()
  }

  private func configureLayer() {
    wantsLayer = true
    applyStyle()
  }

  private func applyStyle() {
    appearance = ThemeManager.shared.nsAppearance
    window?.appearance = ThemeManager.shared.nsAppearance
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.cornerRadius = CloudUploadHistoryLayout.cornerRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
  }
}

// MARK: - Filter Types

enum HistoryStatusFilter: String, CaseIterable {
  case all, active, expired
  var label: String {
    switch self {
    case .all: return L10n.PreferencesCloudHistory.statusAll
    case .active: return L10n.PreferencesCloudHistory.statusActive
    case .expired: return L10n.PreferencesCloudHistory.statusExpired
    }
  }
}

enum HistorySortOrder: String, CaseIterable {
  case newestFirst = "newest"
  case oldestFirst = "oldest"
  case largestFirst = "largest"
  case smallestFirst = "smallest"

  var label: String {
    switch self {
    case .newestFirst: return L10n.PreferencesCloudHistory.newestFirst
    case .oldestFirst: return L10n.PreferencesCloudHistory.oldestFirst
    case .largestFirst: return L10n.PreferencesCloudHistory.largestFirst
    case .smallestFirst: return L10n.PreferencesCloudHistory.smallestFirst
    }
  }
}

// MARK: - History View

/// Main view for browsing and managing cloud upload history
struct CloudUploadHistoryView: View {
  @ObservedObject private var store = CloudUploadHistoryStore.shared
  @ObservedObject private var cloudManager = CloudManager.shared
  @ObservedObject private var themeManager = ThemeManager.shared
  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var backgroundStyle: HistoryBackgroundStyle = .defaultStyle
  @Environment(\.colorScheme) private var colorScheme

  @State private var searchText = ""
  @State private var statusFilter: HistoryStatusFilter = .all
  @State private var providerFilter: CloudProviderType?
  @State private var expireFilter: CloudExpireTime?
  @State private var sortOrder: HistorySortOrder = .newestFirst
  @State private var showFilterPopover = false

  @State private var confirmDeleteAll = false
  @State private var isDeleting = false
  @State private var deleteError: String?

  /// Number of active secondary filters for the toolbar filter badge.
  private var activeFilterCount: Int {
    var count = 0
    if providerFilter != nil { count += 1 }
    if expireFilter != nil { count += 1 }
    if sortOrder != .newestFirst { count += 1 }
    return count
  }

  private var hasActiveFilters: Bool {
    statusFilter != .all || activeFilterCount > 0
  }

  private var filteredRecords: [CloudUploadRecord] {
    var result = store.records

    // Search
    if !searchText.isEmpty {
      result = result.filter {
        $0.fileName.localizedCaseInsensitiveContains(searchText)
          || $0.publicURL.absoluteString.localizedCaseInsensitiveContains(searchText)
      }
    }

    // Status
    switch statusFilter {
    case .all: break
    case .active: result = result.filter { !$0.isExpired }
    case .expired: result = result.filter { $0.isExpired }
    }

    // Provider
    if let provider = providerFilter {
      result = result.filter { $0.providerType == provider }
    }

    // Expire time
    if let expire = expireFilter {
      result = result.filter { $0.expireTime == expire }
    }

    // Sort
    switch sortOrder {
    case .newestFirst: result.sort { $0.uploadedAt > $1.uploadedAt }
    case .oldestFirst: result.sort { $0.uploadedAt < $1.uploadedAt }
    case .largestFirst: result.sort { $0.fileSize > $1.fileSize }
    case .smallestFirst: result.sort { $0.fileSize < $1.fileSize }
    }

    return result
  }

  var body: some View {
    ZStack {
      HistoryBackdropView(style: backgroundStyle)
        .ignoresSafeArea()

      VStack(spacing: 18) {
        toolbar
        errorBanner
        contentArea
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 20)
    }
    .frame(width: CloudUploadHistoryLayout.panelSize.width, height: CloudUploadHistoryLayout.panelSize.height)
    .overlay(panelBorder)
    .preferredColorScheme(themeManager.systemAppearance)
    .alert(L10n.PreferencesCloudHistory.clearAllTitle, isPresented: $confirmDeleteAll) {
      Button(L10n.PreferencesCloudHistory.deleteFromCloudAndClear, role: .destructive) {
        deleteAllFromCloud()
      }
      Button(L10n.PreferencesCloudHistory.clearHistoryOnly) {
        store.removeAll()
      }
      Button(L10n.Common.cancel, role: .cancel) {}
    } message: {
      Text(L10n.PreferencesCloudHistory.clearAllMessage)
    }
  }

  // MARK: - Toolbar

  private var toolbar: some View {
    HStack(alignment: .center, spacing: 12) {
      statusFilterBar
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)

      searchBar

      trailingControls
        .fixedSize(horizontal: true, vertical: false)
    }
  }

  private var statusFilterBar: some View {
    HStack(spacing: 8) {
      ForEach(HistoryStatusFilter.allCases, id: \.self) { filter in
        selectionPill(
          title: filter.label,
          isSelected: statusFilter == filter,
          minWidth: statusFilterMinWidth(for: filter)
        ) {
          withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            statusFilter = filter
          }
        }
      }
    }
  }

  private var trailingControls: some View {
    HStack(spacing: 8) {
      filterButton

      if isDeleting {
        ProgressView()
          .scaleEffect(0.6)
          .frame(width: 14, height: 14)
      }

      uploadCountBadge

      toolbarIconButton(
        systemName: "trash",
        help: L10n.PreferencesCloudHistory.clearAllHistory,
        isDestructive: true,
        action: { confirmDeleteAll = true }
      )
      .disabled(store.records.isEmpty || isDeleting)

      toolbarIconButton(
        systemName: "xmark",
        help: L10n.Common.close,
        action: { CloudUploadHistoryWindowController.shared.closeWindow() }
      )
    }
  }

  private var searchBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.secondary.opacity(0.9))

      TextField(L10n.PreferencesCloudHistory.searchUploads, text: $searchText)
        .textFieldStyle(.plain)
        .font(.system(size: 12, weight: .medium))

      if !searchText.isEmpty {
        Button(action: { searchText = "" }) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.8))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .frame(width: 260)
    .background(chromeSurfaceFill, in: Capsule())
    .overlay(
      Capsule()
        .stroke(chromeSurfaceBorder, lineWidth: 1)
    )
    .shadow(color: chromeSurfaceShadow, radius: 7, x: 0, y: 3)
  }

  private var filterButton: some View {
    Button(action: { showFilterPopover.toggle() }) {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "line.3.horizontal.decrease")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 34, height: 34)
          .background(controlButtonBackground)
          .foregroundColor(.primary.opacity(0.86))
          .clipShape(Circle())

        if activeFilterCount > 0 {
          Text("\(activeFilterCount)")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 14, height: 14)
            .background(Circle().fill(Color.accentColor))
            .offset(x: 3, y: -3)
        }
      }
    }
    .buttonStyle(.plain)
    .help(L10n.PreferencesCloudHistory.filters)
    .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
      filterPopoverContent
    }
  }

  private var uploadCountBadge: some View {
    Text(L10n.PreferencesCloudHistory.uploadsCount(filteredRecords.count))
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(.primary.opacity(0.72))
      .lineLimit(1)
      .padding(.horizontal, 11)
      .padding(.vertical, 8)
      .background(unselectedPillBackground, in: Capsule())
      .overlay(
        Capsule()
          .stroke(chromeSurfaceBorder.opacity(colorScheme == .dark ? 0.45 : 0.7), lineWidth: 1)
      )
  }

  private func toolbarIconButton(
    systemName: String,
    help: String,
    isDestructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(role: isDestructive ? .destructive : nil, action: action) {
      Image(systemName: systemName)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 34, height: 34)
        .background(controlButtonBackground)
        .foregroundColor(isDestructive ? .red : .primary.opacity(0.86))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private var chromeSurfaceFill: AnyShapeStyle {
    if backgroundStyle == .solid {
      return colorScheme == .dark
        ? AnyShapeStyle(Color.white.opacity(0.07))
        : AnyShapeStyle(Color.white.opacity(0.76))
    }

    return colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.07))
      : AnyShapeStyle(Color.white.opacity(0.52))
  }

  private var chromeSurfaceBorder: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.64)
  }

  private var chromeSurfaceShadow: Color {
    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07)
  }

  private var unselectedPillBackground: AnyShapeStyle {
    colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.08))
      : AnyShapeStyle(Color.black.opacity(0.05))
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

  private var pillCountBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.84)
  }

  private var controlButtonBackground: AnyShapeStyle {
    colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.08))
      : AnyShapeStyle(Color.white.opacity(0.72))
  }

  private var panelBorder: some View {
    RoundedRectangle(cornerRadius: CloudUploadHistoryLayout.cornerRadius, style: .continuous)
      .strokeBorder(
        colorScheme == .dark
          ? Color.white.opacity(0.1)
          : Color.white.opacity(0.72),
        lineWidth: 1
      )
  }

  private func selectionPill(
    title: String,
    isSelected: Bool,
    count: Int? = nil,
    minWidth: CGFloat? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Text(title)
          .font(.system(size: 11, weight: .semibold))
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)

        if let count {
          Text("\(count)")
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(pillCountBackground.opacity(isSelected ? 0.18 : 1), in: Capsule())
        }
      }
      .foregroundColor(isSelected ? .white : .primary.opacity(0.82))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(minWidth: minWidth)
      .background(isSelected ? selectedFilterBackground : unselectedPillBackground)
      .overlay(
        Capsule()
          .stroke(
            isSelected
              ? Color.white.opacity(0.08)
              : chromeSurfaceBorder.opacity(colorScheme == .dark ? 0.45 : 0.7),
            lineWidth: 1
          )
      )
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private func statusFilterMinWidth(for filter: HistoryStatusFilter) -> CGFloat {
    switch filter {
    case .all: return 62
    case .active: return 78
    case .expired: return 82
    }
  }

  // MARK: - Filter Popover

  private var filterPopoverContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Provider
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.PreferencesCloudHistory.provider)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.secondary)
        Picker("", selection: $providerFilter) {
          Text(L10n.PreferencesCloudHistory.statusAll).tag(CloudProviderType?.none)
          ForEach(CloudProviderType.allCases, id: \.self) { p in
            Text(p.displayName).tag(CloudProviderType?.some(p))
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }

      // Expire Time
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.PreferencesCloudHistory.expireTime)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.secondary)
        Picker("", selection: $expireFilter) {
          Text(L10n.PreferencesCloudHistory.statusAll).tag(CloudExpireTime?.none)
          ForEach(CloudExpireTime.allCases, id: \.self) { e in
            Text(e.displayName).tag(CloudExpireTime?.some(e))
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }

      // Sort
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.PreferencesCloudHistory.sortBy)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.secondary)
        Picker("", selection: $sortOrder) {
          ForEach(HistorySortOrder.allCases, id: \.self) { s in
            Text(s.label).tag(s)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }

      // Reset
      if hasActiveFilters {
        Button(L10n.PreferencesCloudHistory.resetFilters) {
          statusFilter = .all
          providerFilter = nil
          expireFilter = nil
          sortOrder = .newestFirst
        }
        .font(.system(size: 11))
      }
    }
    .padding(14)
    .frame(width: 220)
  }

  // MARK: - Error Banner

  @ViewBuilder
  private var errorBanner: some View {
    if let error = deleteError {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(.orange)
          .font(.system(size: 11))
        Text(error)
          .font(.system(size: 11))
          .foregroundColor(.orange)
        Spacer()
        Button(L10n.PreferencesCloudHistory.dismiss) { deleteError = nil }
          .font(.system(size: 10))
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .background(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Color.orange.opacity(0.22), lineWidth: 1)
      )
    }
  }

  // MARK: - Content Area

  private var contentArea: some View {
    Group {
      if filteredRecords.isEmpty {
        emptyState
      } else {
        gridView
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Spacer()
      Image(systemName: "icloud.slash")
        .font(.system(size: 32))
        .foregroundColor(.secondary)
      Text(
        searchText.isEmpty && !hasActiveFilters
          ? L10n.PreferencesCloudHistory.noUploadsYet
          : L10n.PreferencesCloudHistory.noResultsFound
      )
        .font(.system(size: 14))
        .foregroundColor(.secondary)
      if hasActiveFilters {
        Button(L10n.PreferencesCloudHistory.resetFilters) {
          statusFilter = .all
          providerFilter = nil
          expireFilter = nil
          sortOrder = .newestFirst
          searchText = ""
        }
        .font(.system(size: 12))
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(chromeSurfaceFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(chromeSurfaceBorder, lineWidth: 1)
    )
  }

  // MARK: - Grid View

  private var gridView: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVGrid(columns: expandedColumns, spacing: 12) {
        ForEach(filteredRecords) { record in
          CloudUploadExpandedCardView(
            record: record,
            isDeleting: isDeleting,
            backgroundStyle: backgroundStyle
          ) {
            deleteRecord(record)
          }
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

  // MARK: - Actions

  private func deleteRecord(_ record: CloudUploadRecord) {
    isDeleting = true
    deleteError = nil
    Task {
      do {
        try await cloudManager.deleteFromCloud(record: record)
      } catch {
        deleteError = L10n.PreferencesCloudHistory.failedToDelete(record.fileName, error.localizedDescription)
      }
      isDeleting = false
    }
  }

  private func deleteAllFromCloud() {
    let records = store.records
    isDeleting = true
    deleteError = nil
    Task {
      do {
        try await cloudManager.deleteAllFromCloud(records: records)
      } catch {
        deleteError = L10n.PreferencesCloudHistory.someFilesCouldNotBeDeleted(error.localizedDescription)
      }
      isDeleting = false
    }
  }
}

// MARK: - Expanded Cloud Upload Card

private struct CloudUploadExpandedCardView: View {
  let record: CloudUploadRecord
  let isDeleting: Bool
  let backgroundStyle: HistoryBackgroundStyle
  let onDelete: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var isHovering = false
  @State private var copied = false

  var body: some View {
    VStack(spacing: 8) {
      preview

      VStack(alignment: .leading, spacing: 6) {
        Text(record.cloudDisplayTitle)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.primary)
          .lineLimit(1)
          .truncationMode(.middle)

        HStack(spacing: 6) {
          Text(record.relativeUploadTime)
          Circle()
            .fill(Color.secondary.opacity(0.38))
            .frame(width: 3, height: 3)
          Text(record.formattedFileSize)
          if record.isExpired {
            Spacer(minLength: 0)
            Text(L10n.PreferencesCloudHistory.expired)
              .font(.system(size: 9.5, weight: .semibold))
              .foregroundColor(.orange)
          }
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundColor(.secondary)
        .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(cardBorderColor, lineWidth: 1)
    )
    .shadow(color: cardShadowColor, radius: isHovering ? 12 : 8, x: 0, y: isHovering ? 7 : 5)
    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .scaleEffect(isHovering ? 1.005 : 1)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.16), value: isHovering)
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        NSWorkspace.shared.open(record.publicURL)
      }
    )
  }

  private var preview: some View {
    ZStack {
      CloudUploadPreview(record: record, iconSize: 30, cornerRadius: 16)

      if isHovering {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color.black.opacity(0.34))

        HStack(spacing: 12) {
          gridActionButton(
            icon: copied ? "checkmark" : "doc.on.doc",
            color: copied ? .green : .white,
            action: copyLink
          )
          gridActionButton(
            icon: "safari",
            color: .white,
            action: { NSWorkspace.shared.open(record.publicURL) }
          )
          gridActionButton(
            icon: "trash",
            color: .red,
            action: onDelete
          )
        }
        .disabled(isDeleting)
        .transition(.opacity)
      }
    }
    .aspectRatio(16 / 10, contentMode: .fit)
  }

  private var cardBackground: AnyShapeStyle {
    if backgroundStyle == .solid {
      return colorScheme == .dark
        ? AnyShapeStyle(Color.white.opacity(0.08))
        : AnyShapeStyle(Color.white.opacity(0.92))
    }

    return colorScheme == .dark
      ? AnyShapeStyle(Color.white.opacity(0.07))
      : AnyShapeStyle(Color.white.opacity(0.7))
  }

  private var cardBorderColor: Color {
    if isHovering {
      return colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    return colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.55)
  }

  private var cardShadowColor: Color {
    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08)
  }

  private func gridActionButton(
    icon: String, color: Color, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(color)
        .frame(width: 30, height: 30)
        .background(.regularMaterial, in: Circle())
        .overlay(
          Circle()
            .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.55), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }

  private func copyLink() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(record.publicURL.absoluteString, forType: .string)
    copied = true
    Task {
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      copied = false
    }
  }
}

// MARK: - Shared Cloud Upload Preview

private struct CloudUploadPreview: View {
  let record: CloudUploadRecord
  let iconSize: CGFloat
  let cornerRadius: CGFloat

  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottomTrailing) {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(previewBackground)

        thumbnailContent
          .frame(width: geometry.size.width, height: geometry.size.height)
          .clipped()

        if record.isExpired {
          Text(L10n.PreferencesCloudHistory.expired)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.92), in: Capsule())
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        typeBadge
          .padding(8)
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(previewBorderColor, lineWidth: 1)
      )
    }
  }

  @ViewBuilder
  private var thumbnailContent: some View {
    if let thumbURL = record.thumbnailURL,
      let nsImage = NSImage(contentsOf: thumbURL)
    {
      Image(nsImage: nsImage)
        .resizable()
        .scaledToFill()
    } else if record.isImageType {
      AsyncImage(url: record.publicURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFill()
        case .failure:
          placeholderIcon
        case .empty:
          ProgressView()
            .scaleEffect(0.62)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        @unknown default:
          placeholderIcon
        }
      }
    } else {
      placeholderIcon
    }
  }

  private var placeholderIcon: some View {
    VStack(spacing: 6) {
      Image(systemName: record.cloudFileTypeIcon)
        .font(.system(size: iconSize, weight: .medium))
        .foregroundColor(.secondary.opacity(0.55))

      if !record.cloudFileExtension.isEmpty {
        Text(record.cloudFileExtension)
          .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
          .foregroundColor(.secondary.opacity(0.64))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var previewBackground: Color {
    colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.9)
  }

  private var previewBorderColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
  }

  private var typeBadge: some View {
    Image(systemName: record.cloudFileTypeIcon)
      .font(.system(size: 10, weight: .semibold))
      .foregroundColor(.primary.opacity(0.82))
      .frame(width: 24, height: 24)
      .background(.regularMaterial, in: Circle())
      .overlay(
        Circle()
          .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.55), lineWidth: 1)
      )
  }
}

private extension CloudUploadRecord {
  var cloudDisplayTitle: String {
    let title = (fileName as NSString).deletingPathExtension
    return title.isEmpty ? fileName : title
  }

  var cloudFileExtension: String {
    (fileName as NSString).pathExtension.uppercased()
  }

  var cloudFileTypeIcon: String {
    let ext = (fileName as NSString).pathExtension.lowercased()

    if ext == "gif" {
      return "photo.stack"
    }

    if contentType?.hasPrefix("video/") == true || ["mp4", "mov", "m4v", "webm"].contains(ext) {
      return "film"
    }

    if isImageType {
      return "photo"
    }

    return "doc.fill"
  }

  var relativeUploadTime: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: uploadedAt, relativeTo: Date())
  }
}

#Preview {
  CloudUploadHistoryView()
    .frame(width: CloudUploadHistoryLayout.panelSize.width, height: CloudUploadHistoryLayout.panelSize.height)
}
