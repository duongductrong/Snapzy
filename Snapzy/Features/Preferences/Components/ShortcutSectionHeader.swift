//
//  ShortcutSectionHeader.swift
//  Snapzy
//
//  Consistent header for shortcut settings sections: title, optional help
//  (info icon + hover popover), and optional reset action.
//

import SwiftUI

struct ShortcutSectionHeader: View {
  let title: String
  var help: String? = nil
  var onReset: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 6) {
      if let help, !help.isEmpty {
        Text(title)
          .hint(help, variant: .icon(.info))
      } else {
        Text(title)
      }

      Spacer()

      if let onReset {
        Button(L10n.Common.reset, action: onReset)
          .buttonStyle(.borderless)
          .font(.caption)
      }
    }
  }
}
