//
//  CaptureToolbarView.swift
//  Snapzy
//
//  The capture toolbar shown under a selection: one button per item with its
//  accelerator badge, and a close button. Reuses the recording toolbar's
//  button and divider components.
//

import SwiftUI

struct CaptureToolbarView: View {
  let entries: [CaptureToolbarEntry]
  let title: (CaptureToolbarItem) -> String
  let symbol: (CaptureToolbarItem) -> String
  let onSelect: (CaptureToolbarItem) -> Void
  let onCancel: () -> Void

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(entries.enumerated()), id: \.element.item) { index, entry in
        if index > 0, isGroupBoundary(entries[index - 1].item, entry.item) {
          RecordingToolbarDivider()
        }
        button(entry, isPrimary: index == 0)
      }
      RecordingToolbarDivider()
      ToolbarIconButton(systemName: "xmark", action: onCancel, accessibilityLabel: L10n.Common.cancel)
        .help(L10n.CaptureToolbar.cancelHelp)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(L10n.CaptureToolbar.accessibilityLabel)
  }

  private func button(_ entry: CaptureToolbarEntry, isPrimary: Bool) -> some View {
    let label = title(entry.item)
    let key = isPrimary ? "↩" : entry.accelerator
    return Button {
      onSelect(entry.item)
    } label: {
      VStack(spacing: 2) {
        Image(systemName: symbol(entry.item))
          .font(.system(size: 14, weight: .medium))
          .frame(width: 30, height: 20)
        Text(key ?? " ")
          .font(.system(size: 9, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
      }
      .frame(minWidth: 36, minHeight: 36)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(key.map { "\(label)  \($0)" } ?? label)
    .accessibilityLabel(label)
    .accessibilityHint(key.map { L10n.CaptureToolbar.acceleratorHint($0) } ?? "")
  }

  /// Still-image actions | recordings | automations.
  private func isGroupBoundary(_ previous: CaptureToolbarItem, _ next: CaptureToolbarItem) -> Bool {
    func group(_ item: CaptureToolbarItem) -> Int {
      switch item {
      case .builtin(let builtin): builtin.startsNewCapture ? 1 : 0
      case .automation: 2
      }
    }
    return group(previous) != group(next)
  }
}
