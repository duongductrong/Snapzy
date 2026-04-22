//
//  HistoryToolbar.swift
//  Snapzy
//
//  Top toolbar for the history browser
//

import SwiftUI

struct HistoryToolbar: View {
  @Binding var searchText: String
  let selectedCount: Int
  let onClearSelection: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      // Search
      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.secondary)
        TextField("Search by filename", text: $searchText)
          .textFieldStyle(PlainTextFieldStyle())
        if !searchText.isEmpty {
          Button(action: { searchText = "" }) {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.secondary)
          }
          .buttonStyle(PlainButtonStyle())
        }
      }
      .padding(8)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      )

      Spacer()

      // Selection info
      if selectedCount > 0 {
        Text("\(selectedCount) selected")
          .font(.caption)
          .foregroundColor(.secondary)

        Button(action: onClearSelection) {
          Text("Clear")
            .font(.caption)
        }
        .buttonStyle(PlainButtonStyle())
      }
    }
    .padding(.horizontal)
    .padding(.top, 12)
    .padding(.bottom, 4)
  }
}
