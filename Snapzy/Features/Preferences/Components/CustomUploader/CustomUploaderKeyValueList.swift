//
//  CustomUploaderKeyValueList.swift
//  Snapzy
//
//  Editable name/value rows (headers, query parameters, form fields) for the custom uploader editor.
//

import SwiftUI

/// A row with a stable id so SwiftUI keeps focus while the user types.
struct CustomUploaderEditableRow: Identifiable, Equatable {
  let id = UUID()
  var key: String
  var value: String

  init(key: String = "", value: String = "") {
    self.key = key
    self.value = value
  }

  static func rows(from pairs: [CustomUploader.KeyValue]) -> [CustomUploaderEditableRow] {
    pairs.map { CustomUploaderEditableRow(key: $0.key, value: $0.value) }
  }

  /// Rows with a blank name are dropped.
  static func pairs(from rows: [CustomUploaderEditableRow]) -> [CustomUploader.KeyValue] {
    rows
      .filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
      .map { CustomUploader.KeyValue($0.key.trimmingCharacters(in: .whitespaces), $0.value) }
  }
}

struct CustomUploaderKeyValueList: View {
  let title: String
  @Binding var rows: [CustomUploaderEditableRow]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
        Spacer()
        Button {
          rows.append(CustomUploaderEditableRow())
        } label: {
          Label(L10n.CustomUploader.addRow, systemImage: "plus")
        }
        .controlSize(.small)
      }

      ForEach($rows) { $row in
        HStack(spacing: 6) {
          TextField("", text: $row.key, prompt: Text(L10n.CustomUploader.keyPlaceholder))
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
          TextField("", text: $row.value, prompt: Text(L10n.CustomUploader.valuePlaceholder))
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
          Button {
            rows.removeAll { $0.id == row.id }
          } label: {
            Image(systemName: "minus.circle")
              .foregroundColor(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(L10n.CustomUploader.removeRow)
        }
      }
    }
    .padding(.vertical, 2)
  }
}
