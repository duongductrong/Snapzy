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

  private let columns = [
    GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
  ]

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(records) { record in
          HistoryItemView(
            record: record,
            isSelected: selectedIds.contains(record.id),
            onSelect: {
              handleTap(record: record)
            }
          )
          .contextMenu {
            HistoryContextMenu(record: record)
          }
        }
      }
      .padding()
    }
  }

  private func handleTap(record: CaptureHistoryRecord) {
    if NSEvent.modifierFlags.contains(.command) {
      // Cmd+click toggle
      if selectedIds.contains(record.id) {
        selectedIds.remove(record.id)
      } else {
        selectedIds.insert(record.id)
      }
    } else if NSEvent.modifierFlags.contains(.shift) {
      // Shift+click range selection (simplified)
      selectedIds.insert(record.id)
    } else {
      // Single click
      selectedIds = [record.id]
    }
  }
}
