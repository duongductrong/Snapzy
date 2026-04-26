//
//  HistoryGridView.swift
//  Snapzy
//
//  Responsive grid of capture history items
//

import SwiftUI

struct HistoryGridView: View {
  let records: [CaptureHistoryRecord]
  @Binding var selectedIds: Set<UUID>
  @AppStorage(PreferencesKeys.historyBackgroundStyle) private var backgroundStyle: HistoryBackgroundStyle = .defaultStyle
  @State private var lastSelectedId: UUID?

  private let columns = [
    GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 12)
  ]

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(records) { record in
          HistoryExpandedCaptureCardView(
            record: record,
            isSelected: selectedIds.contains(record.id),
            backgroundStyle: backgroundStyle,
            onTap: {
              handleTap(record: record)
            }
          )
          .contextMenu {
            HistoryContextMenu(record: record)
          }
        }
      }
      .padding(.horizontal, 2)
      .padding(.top, 4)
      .padding(.bottom, 16)
    }
  }

  private func handleTap(record: CaptureHistoryRecord) {
    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

    if flags.contains(.shift), let lastSelectedId,
      let startIndex = records.firstIndex(where: { $0.id == lastSelectedId }),
      let endIndex = records.firstIndex(where: { $0.id == record.id })
    {
      let range = min(startIndex, endIndex)...max(startIndex, endIndex)
      selectedIds.formUnion(records[range].map(\.id))
    } else if flags.contains(.command) {
      if selectedIds.contains(record.id) {
        selectedIds.remove(record.id)
      } else {
        selectedIds.insert(record.id)
      }
      lastSelectedId = record.id
    } else if flags.contains(.shift) {
      selectedIds.insert(record.id)
      lastSelectedId = record.id
    } else {
      selectedIds = [record.id]
      lastSelectedId = record.id
    }
  }
}
