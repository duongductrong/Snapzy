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

  private var window: NSWindow?

  private init() {}

  func showWindow() {
    if let existingWindow = window, existingWindow.isVisible {
      existingWindow.makeKeyAndOrderFront(nil)
      return
    }

    let view = CloudUploadHistoryView()
    let hostingView = NSHostingView(rootView: view)

    let newWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    newWindow.title = L10n.PreferencesCloudHistory.windowTitle
    newWindow.contentView = hostingView
    newWindow.minSize = NSSize(width: 700, height: 400)
    newWindow.center()
    newWindow.isReleasedWhenClosed = false
    newWindow.makeKeyAndOrderFront(nil)

    window = newWindow
  }
}

// MARK: - Filter Types

enum HistoryDisplayMode: String, CaseIterable {
  case list, grid
  var icon: String {
    switch self {
    case .list: return "list.bullet"
    case .grid: return "square.grid.2x2"
    }
  }
}

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

  @State private var searchText = ""
  @State private var displayMode: HistoryDisplayMode = .list
  @State private var statusFilter: HistoryStatusFilter = .all
  @State private var providerFilter: CloudProviderType?
  @State private var expireFilter: CloudExpireTime?
  @State private var sortOrder: HistorySortOrder = .newestFirst
  @State private var showFilterPopover = false

  @State private var confirmDeleteAll = false
  @State private var isDeleting = false
  @State private var deleteError: String?

  /// Number of active (non-default) filters for badge
  private var activeFilterCount: Int {
    var count = 0
    if statusFilter != .all { count += 1 }
    if providerFilter != nil { count += 1 }
    if expireFilter != nil { count += 1 }
    if sortOrder != .newestFirst { count += 1 }
    return count
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
    VStack(spacing: 0) {
      toolbar
      errorBanner
      Divider()
      contentArea
    }
    .frame(minWidth: 700, minHeight: 400)
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
    HStack(spacing: 10) {
      // Search
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.secondary)
          .font(.system(size: 12))
        TextField(L10n.PreferencesCloudHistory.searchUploads, text: $searchText)
          .textFieldStyle(.plain)
          .font(.system(size: 13))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
      .frame(maxWidth: 240)

      Spacer()

      // Display mode toggle
      Picker("", selection: $displayMode) {
        ForEach(HistoryDisplayMode.allCases, id: \.self) { mode in
          Image(systemName: mode.icon).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 70)

      // Filter button
      Button(action: { showFilterPopover.toggle() }) {
        ZStack(alignment: .topTrailing) {
          Image(systemName: "line.3.horizontal.decrease.circle")
            .font(.system(size: 14))
          if activeFilterCount > 0 {
            Text("\(activeFilterCount)")
              .font(.system(size: 8, weight: .bold))
              .foregroundColor(.white)
              .frame(width: 13, height: 13)
              .background(Circle().fill(Color.accentColor))
              .offset(x: 5, y: -5)
          }
        }
      }
      .buttonStyle(.plain)
      .help(L10n.PreferencesCloudHistory.filters)
      .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
        filterPopoverContent
      }

      if isDeleting {
        ProgressView()
          .scaleEffect(0.6)
          .frame(width: 14, height: 14)
      }

      Text(L10n.PreferencesCloudHistory.uploadsCount(filteredRecords.count))
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Button(role: .destructive) {
        confirmDeleteAll = true
      } label: {
        Image(systemName: "trash")
          .font(.system(size: 12))
      }
      .buttonStyle(.plain)
      .help(L10n.PreferencesCloudHistory.clearAllHistory)
      .disabled(store.records.isEmpty || isDeleting)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  // MARK: - Filter Popover

  private var filterPopoverContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Status
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.PreferencesCloudHistory.status)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.secondary)
        Picker("", selection: $statusFilter) {
          ForEach(HistoryStatusFilter.allCases, id: \.self) { s in
            Text(s.label).tag(s)
          }
        }
        .pickerStyle(.segmented)
      }

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
      if activeFilterCount > 0 {
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
      .background(Color.orange.opacity(0.1))
    }
  }

  // MARK: - Content Area

  @ViewBuilder
  private var contentArea: some View {
    if filteredRecords.isEmpty {
      emptyState
    } else {
      switch displayMode {
      case .list: listView
      case .grid: gridView
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Spacer()
      Image(systemName: "icloud.slash")
        .font(.system(size: 32))
        .foregroundColor(.secondary)
      Text(
        searchText.isEmpty && activeFilterCount == 0
          ? L10n.PreferencesCloudHistory.noUploadsYet
          : L10n.PreferencesCloudHistory.noResultsFound
      )
        .font(.system(size: 14))
        .foregroundColor(.secondary)
      if activeFilterCount > 0 {
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
    .frame(maxWidth: .infinity)
  }

  // MARK: - List View

  private var listView: some View {
    List {
      ForEach(filteredRecords) { record in
        HistoryRecordRow(record: record, isDeleting: isDeleting) {
          deleteRecord(record)
        }
      }
    }
    .listStyle(.inset(alternatesRowBackgrounds: true))
  }

  // MARK: - Grid View

  private var gridView: some View {
    ScrollView {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 12)],
        spacing: 12
      ) {
        ForEach(filteredRecords) { record in
          HistoryGridItem(record: record, isDeleting: isDeleting) {
            deleteRecord(record)
          }
        }
      }
      .padding(16)
    }
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

// MARK: - History Record Row (List)

private struct HistoryRecordRow: View {
  let record: CloudUploadRecord
  let isDeleting: Bool
  let onDelete: () -> Void

  @State private var isHovering = false
  @State private var copied = false

  var body: some View {
    HStack(spacing: 12) {
      // Thumbnail or icon
      thumbnailOrIcon
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))

      // File info
      VStack(alignment: .leading, spacing: 3) {
        Text(record.fileName)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(1)

        HStack(spacing: 8) {
          Label(record.formattedDate, systemImage: "calendar")
          Label(record.formattedFileSize, systemImage: "doc")
          Label(record.expireTime.displayName, systemImage: "clock")
          Label(record.providerType.displayName, systemImage: "cloud")

          if record.isExpired {
            Text(L10n.PreferencesCloudHistory.expired)
              .fontWeight(.medium)
              .foregroundColor(.orange)
          }
        }
        .font(.system(size: 10))
        .foregroundColor(.secondary)

        Text(record.publicURL.absoluteString)
          .font(.system(size: 10, design: .monospaced))
          .foregroundColor(.blue)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      // Actions on hover
      if isHovering {
        HStack(spacing: 8) {
          Button(action: copyLink) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
              .font(.system(size: 11))
              .foregroundColor(copied ? .green : .primary)
          }
          .buttonStyle(.plain)
          .help(L10n.PreferencesCloudHistory.copyLink)

          Button(action: openInBrowser) {
            Image(systemName: "safari")
              .font(.system(size: 11))
          }
          .buttonStyle(.plain)
          .help(L10n.PreferencesCloudHistory.openInBrowser)

          Button(role: .destructive, action: onDelete) {
            Image(systemName: "trash")
              .font(.system(size: 11))
              .foregroundColor(.red)
          }
          .buttonStyle(.plain)
          .help(L10n.PreferencesCloudHistory.removeFromHistory)
        }
        .transition(.opacity)
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .onHover { isHovering = $0 }
    .animation(.easeInOut(duration: 0.15), value: isHovering)
  }

  @ViewBuilder
  private var thumbnailOrIcon: some View {
    if let thumbURL = record.thumbnailURL,
      let nsImage = NSImage(contentsOf: thumbURL)
    {
      Image(nsImage: nsImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      Image(systemName: record.isExpired ? "doc.badge.clock" : fileTypeIcon)
        .font(.system(size: 18))
        .foregroundColor(record.isExpired ? .orange : .accentColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.04))
    }
  }

  private var fileTypeIcon: String {
    record.isImageType ? "photo.fill" : "doc.fill"
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

  private func openInBrowser() {
    NSWorkspace.shared.open(record.publicURL)
  }
}

// MARK: - History Grid Item

private struct HistoryGridItem: View {
  let record: CloudUploadRecord
  let isDeleting: Bool
  let onDelete: () -> Void

  @State private var isHovering = false
  @State private var copied = false

  var body: some View {
    VStack(spacing: 0) {
      // Thumbnail area
      ZStack {
        thumbnailArea
          .frame(height: 120)
          .frame(maxWidth: .infinity)
          .clipped()

        // Status badge (top-trailing)
        VStack {
          HStack {
            Spacer()
            if record.isExpired {
              Text(L10n.PreferencesCloudHistory.expired)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange))
            }
          }
          .padding(6)
          Spacer()
        }

        // Hover overlay (centered)
        if isHovering {
          Color.black.opacity(0.4)
          HStack(spacing: 12) {
            gridActionButton(
              icon: copied ? "checkmark" : "doc.on.doc",
              color: copied ? .green : .white
            ) {
              copyLink()
            }
            gridActionButton(icon: "safari", color: .white) {
              NSWorkspace.shared.open(record.publicURL)
            }
            gridActionButton(icon: "trash", color: .red) {
              onDelete()
            }
          }
          .transition(.opacity)
        }
      }
      .frame(height: 120)
      .clipShape(
        UnevenRoundedRectangle(
          topLeadingRadius: 8,
          bottomLeadingRadius: 0,
          bottomTrailingRadius: 0,
          topTrailingRadius: 8
        )
      )

      // Info area
      VStack(alignment: .leading, spacing: 3) {
        Text(record.fileName)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
          .truncationMode(.middle)

        HStack(spacing: 6) {
          Text(record.formattedDate)
          Text("·")
          Text(record.formattedFileSize)
        }
        .font(.system(size: 10))
        .foregroundColor(.secondary)
        .lineLimit(1)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.primary.opacity(isHovering ? 0.06 : 0.03))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(Color.primary.opacity(isHovering ? 0.15 : 0.08), lineWidth: 1)
    )
    .contentShape(Rectangle())
    .onHover { isHovering = $0 }
    .animation(.easeInOut(duration: 0.15), value: isHovering)
  }

  @ViewBuilder
  private var thumbnailArea: some View {
    if let thumbURL = record.thumbnailURL,
      let nsImage = NSImage(contentsOf: thumbURL)
    {
      Image(nsImage: nsImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else if record.isImageType {
      // Fallback: load from cloud URL for older uploads without local thumbnail
      AsyncImage(url: record.publicURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        case .failure:
          placeholderIcon
        case .empty:
          ProgressView()
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
      Image(systemName: record.isImageType ? "photo" : "doc.fill")
        .font(.system(size: 28))
        .foregroundColor(.secondary.opacity(0.5))
      Text(
        (record.fileName as NSString).pathExtension.uppercased()
      )
      .font(.system(size: 10, weight: .medium, design: .monospaced))
      .foregroundColor(.secondary.opacity(0.6))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.primary.opacity(0.03))
  }

  private func gridActionButton(
    icon: String, color: Color, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 13))
        .foregroundColor(color)
        .frame(width: 30, height: 30)
        .background(Circle().fill(Color.black.opacity(0.5)))
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

#Preview {
  CloudUploadHistoryView()
    .frame(width: 800, height: 560)
}
