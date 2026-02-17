//
//  AboutCreditRow.swift
//  Snapzy
//
//  Credit/acknowledgment row for About settings tab
//

import SwiftUI

struct AboutCreditRow: View {
  let name: String
  let role: String
  let icon: String

  var body: some View {
    HStack(spacing: Spacing.md) {
      Image(systemName: icon)
        .font(.body)
        .foregroundColor(.secondary)
        .frame(width: 24)

      Text(name)
        .font(.system(size: 12, weight: .medium))

      Spacer()

      Text(role)
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }
}

#Preview {
  VStack {
    AboutCreditRow(name: "SwiftUI", role: "UI Framework", icon: "swift")
    AboutCreditRow(name: "Sparkle", role: "Auto Updates", icon: "arrow.triangle.2.circlepath")
  }
  .padding()
}
