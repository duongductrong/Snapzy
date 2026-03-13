//
//  AfterCaptureMatrixView.swift
//  Snapzy
//
//  Grid component for configuring post-capture actions
//

import SwiftUI

struct AfterCaptureMatrixView: View {
  @ObservedObject private var manager = PreferencesManager.shared

  var body: some View {
    VStack(spacing: 0) {
      // Column headers
      HStack(spacing: 12) {
        Spacer()
          .frame(width: 28)
        Spacer()
        HStack(spacing: 16) {
          Text("Screenshot")
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(width: 70)
          Text("Recording")
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(width: 70)
        }
      }
      .padding(.bottom, 4)

      ForEach(AfterCaptureAction.allCases, id: \.self) { action in
        actionRow(for: action)
      }
    }
  }

  @ViewBuilder
  private func actionRow(for action: AfterCaptureAction) -> some View {
    HStack(spacing: 12) {
      Image(systemName: iconName(for: action))
        .font(.title2)
        .foregroundColor(.secondary)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(action.displayName)
          .fontWeight(.medium)
        Text(description(for: action))
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      HStack(spacing: 16) {
        toggleColumn(label: "Screenshot", action: action, type: .screenshot)
        toggleColumn(label: "Recording", action: action, type: .recording)
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func toggleColumn(label: String, action: AfterCaptureAction, type: CaptureType) -> some View {
    Toggle("", isOn: binding(for: action, type: type))
      .labelsHidden()
      .accessibilityLabel("\(action.displayName) for \(label.lowercased())")
      .frame(width: 70)
  }

  private func iconName(for action: AfterCaptureAction) -> String {
    switch action {
    case .showQuickAccess:
      return "rectangle.on.rectangle.angled"
    case .copyFile:
      return "doc.on.clipboard"
    case .save:
      return "square.and.arrow.down"
    }
  }

  private func description(for action: AfterCaptureAction) -> String {
    switch action {
    case .showQuickAccess:
      return "Display overlay with quick actions"
    case .copyFile:
      return "Copy to clipboard automatically"
    case .save:
      return "Automatically save to export location"
    }
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
