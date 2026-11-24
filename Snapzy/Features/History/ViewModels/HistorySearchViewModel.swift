//
//  HistorySearchViewModel.swift
//  Snapzy
//
//  Reactive debounced search and background filtering for capture history
//

import Combine
import Foundation

@MainActor
final class HistorySearchViewModel: ObservableObject {
  @Published var searchText: String = ""
  @Published var selectedFilter: CaptureHistoryType? = nil
  @Published var selectedTimeFilter: HistoryFloatingTimeFilter = .all
  @Published private(set) var filteredRecords: [CaptureHistoryRecord] = []

  private let store = CaptureHistoryStore.shared
  private var cancellables = Set<AnyCancellable>()

  // SwiftUI can release this outside a task on macOS 13–15; avoid isolated deinit back-deployment.
  deinit {}

  init(
    searchTextPublisher: AnyPublisher<String, Never>? = nil,
    selectedFilterPublisher: AnyPublisher<CaptureHistoryType?, Never>? = nil,
    selectedTimeFilterPublisher: AnyPublisher<HistoryFloatingTimeFilter, Never>? = nil
  ) {
    let textSource = searchTextPublisher ?? $searchText.eraseToAnyPublisher()
    let filterSource = selectedFilterPublisher ?? $selectedFilter.eraseToAnyPublisher()
    let timeSource = selectedTimeFilterPublisher ?? $selectedTimeFilter.eraseToAnyPublisher()

    Publishers.CombineLatest4(
      store.$records,
      textSource
        .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        .removeDuplicates(),
      filterSource,
      timeSource
    )
    .receive(on: DispatchQueue.global(qos: .userInitiated))
    .map { records, searchText, selectedFilter, selectedTimeFilter in
      let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
      let now = Date()
      
      return records.filter { record in
        let matchesType = selectedFilter == nil || record.captureType == selectedFilter
        let matchesTime = selectedTimeFilter == .all || selectedTimeFilter.includes(record.capturedAt, relativeTo: now)
        let matchesSearch = query.isEmpty || record.fileName.localizedCaseInsensitiveContains(query)
        return matchesType && matchesTime && matchesSearch
      }
    }
    .receive(on: RunLoop.main)
    .sink { [weak self] filtered in
      self?.filteredRecords = filtered
    }
    .store(in: &cancellables)
  }
}
