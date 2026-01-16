//
//  AfterCaptureMatrixView.swift
//  ZapShot
//
//  Grid component for configuring post-capture actions
//

import SwiftUI

struct AfterCaptureMatrixView: View {
  @ObservedObject private var manager = PreferencesManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Header row
      HStack {
        Text("Action")
          .frame(width: 180, alignment: .leading)
        Text("Screenshot")
          .frame(width: 80)
        Text("Recording")
          .frame(width: 80)
      }
      .font(.caption.weight(.medium))
      .foregroundColor(.secondary)

      Divider()

      // Action rows
      ForEach(AfterCaptureAction.allCases, id: \.self) { action in
        HStack {
          Text(action.displayName)
            .frame(width: 180, alignment: .leading)
            .font(.body)

          Toggle("", isOn: binding(for: action, type: .screenshot))
            .labelsHidden()
            .frame(width: 80)
            .accessibilityLabel("\(action.displayName) for screenshots")

          Toggle("", isOn: binding(for: action, type: .recording))
            .labelsHidden()
            .frame(width: 80)
            .accessibilityLabel("\(action.displayName) for recordings")
        }
      }
    }
    .padding()
    .background(Color.gray.opacity(0.05))
    .cornerRadius(8)
  }

  private func binding(for action: AfterCaptureAction, type: CaptureType) -> Binding<Bool> {
    Binding(
      get: { manager.isActionEnabled(action, for: type) },
      set: { manager.setAction(action, for: type, enabled: $0) }
    )
  }
}

#Preview {
  AfterCaptureMatrixView()
    .padding()
}
